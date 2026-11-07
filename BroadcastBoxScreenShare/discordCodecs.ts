/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Gabriel Monteiro de Souza
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { Logger } from "@utils/Logger";
import { MediaEngineStore } from "@webpack/common";

import { StreamQuality } from "./streamQuality";

const logger = new Logger("WhipRelay:Codecs", "#e5a00d");

/**
 * Codec preference order requested for Broadcast Box ingest.
 *
 * VP9 is preferred when the platform can encode it in hardware. Without VP9
 * hardware support the first codec in this list that the platform supports is
 * promoted; AV1 always stays last unless the experimental forceAv1First setting
 * is enabled.
 */
const BASE_CODEC_ORDER = ["VP9", "H265", "VP8", "H264", "AV1"] as const;

type CodecName = typeof BASE_CODEC_ORDER[number];

/** Non-encodable helper codecs that must stay after the real video codecs. */
const UTILITY_CODECS = new Set(["RTX", "RED", "ULPFEC", "FLEXFEC", "FLEXFEC-03"]);

/** WebRTC MIME types accepted by MediaCapabilities.encodingInfo(). */
const CODEC_CONTENT_TYPES: Record<CodecName, string> = {
    H264: "video/H264",
    VP8: "video/VP8",
    VP9: "video/VP9",
    AV1: "video/AV1",
    H265: "video/H265"
};

const CODEC_CAPABILITY_TIMEOUT_MS = 500;
const DEFAULT_PROBE_WIDTH = 1920;
const DEFAULT_PROBE_HEIGHT = 1080;
const DEFAULT_PROBE_BITRATE = 4_000_000;
const DEFAULT_PROBE_FRAMERATE = 30;

let cachedDiscordCodecs: string[] | null | undefined;

function codecName(mimeType: string | undefined): string {
    return (mimeType?.split("/")[1] ?? "").toUpperCase();
}

/**
 * Asks Discord's media engine which video codecs it can actually encode.
 * Returns null when the native bridge is unavailable or takes too long.
 */
export function getDiscordEncodeCodecs(): Promise<string[] | null> {
    if (cachedDiscordCodecs !== undefined) {
        return Promise.resolve(cachedDiscordCodecs);
    }

    return new Promise(resolve => {
        let settled = false;

        const finish = (names: string[] | null) => {
            if (settled) return;
            settled = true;
            cachedDiscordCodecs = names;
            resolve(names);
        };

        const timer = window.setTimeout(() => finish(null), CODEC_CAPABILITY_TIMEOUT_MS);

        try {
            const engine = MediaEngineStore?.getMediaEngine?.();
            if (!engine?.getCodecCapabilities) {
                window.clearTimeout(timer);
                finish(null);
                return;
            }

            engine.getCodecCapabilities(json => {
                window.clearTimeout(timer);
                if (!json || json.trim().length === 0) {
                    // Some Discord builds expose the bridge without a payload.
                    finish(null);
                    return;
                }
                try {
                    const capabilities = JSON.parse(json) as Array<{ name?: string; encode?: boolean; }>;
                    const names = capabilities
                        .filter(codec => codec.encode !== false && typeof codec.name === "string")
                        .map(codec => codec.name!.toUpperCase());

                    if (names.length === 0) {
                        finish(null);
                        return;
                    }

                    logger.debug("Discord reports encodable video codecs:", names.join(", "));
                    finish(names);
                } catch (err) {
                    logger.debug("Discord codec capabilities were not JSON; using browser probes.", err);
                    finish(null);
                }
            });
        } catch (err) {
            window.clearTimeout(timer);
            logger.warn("Could not query Discord codec capabilities:", err);
            finish(null);
        }
    });
}

interface CodecProbe {
    supported: boolean;
    smooth: boolean;
    powerEfficient: boolean;
}

async function probeCodec(name: CodecName, quality: StreamQuality | null): Promise<CodecProbe | null> {
    const { mediaCapabilities } = navigator;
    if (!mediaCapabilities?.encodingInfo) return null;

    try {
        return await mediaCapabilities.encodingInfo({
            type: "webrtc",
            video: {
                contentType: CODEC_CONTENT_TYPES[name],
                width: quality?.width ?? DEFAULT_PROBE_WIDTH,
                height: quality?.height ?? DEFAULT_PROBE_HEIGHT,
                bitrate: DEFAULT_PROBE_BITRATE,
                framerate: quality?.frameRate ?? DEFAULT_PROBE_FRAMERATE
            }
        });
    } catch (err) {
        logger.debug(`MediaCapabilities probe failed for ${name}:`, err);
        return null;
    }
}

async function probeAllCodecs(quality: StreamQuality | null): Promise<Map<CodecName, CodecProbe> | null> {
    if (!navigator.mediaCapabilities?.encodingInfo) return null;

    const entries = await Promise.all(
        BASE_CODEC_ORDER.map(async name => [name, await probeCodec(name, quality)] as const)
    );

    const probes = new Map<CodecName, CodecProbe>();
    for (const [name, probe] of entries) {
        if (probe) probes.set(name, probe);
    }

    return probes.size > 0 ? probes : null;
}

export type CodecPolicySource = "media-capabilities" | "discord" | "static";

export interface CodecPolicy {
    /** Ordered codec names used to rank browser capabilities. */
    priority: string[];
    /** Codecs the platform can encode, or null when unknown. */
    allowed: Set<string> | null;
    supported: string[];
    vp9Hardware: boolean;
    source: CodecPolicySource;
}

export interface CodecPolicyOptions {
    quality?: StreamQuality | null;
    /** Experimental: put AV1 in front of every other codec. */
    forceAv1First?: boolean;
}

function buildPriority(supported: Set<string>, vp9Hardware: boolean, forceAv1First: boolean): string[] {
    if (forceAv1First) {
        return ["AV1", ...BASE_CODEC_ORDER.filter(name => name !== "AV1")];
    }

    let order: string[];

    if (vp9Hardware && supported.has("VP9")) {
        order = [...BASE_CODEC_ORDER];
    } else {
        // Without VP9 hardware support, promote the first codec this platform
        // can encode and keep the rest as negotiated fallbacks.
        const firstSupported = BASE_CODEC_ORDER.find(name => supported.has(name));
        order = firstSupported
            ? [firstSupported, ...BASE_CODEC_ORDER.filter(name => name !== firstSupported && supported.has(name))]
            : [...BASE_CODEC_ORDER];
    }

    // AV1 is always the last real video codec unless explicitly forced first.
    order = order.filter(name => name !== "AV1");
    order.push("AV1");
    return order;
}

/**
 * Resolves the effective codec policy from Discord's capabilities and the
 * browser's MediaCapabilities API. The browser probe is authoritative for
 * hardware acceleration; Discord's list is the fallback; the static order is
 * the final fallback.
 */
export async function resolveCodecPolicy(options: CodecPolicyOptions = {}): Promise<CodecPolicy> {
    const forceAv1First = options.forceAv1First === true;
    const probes = await probeAllCodecs(options.quality ?? null);
    const discordCodecs = await getDiscordEncodeCodecs();

    let supported: string[] = [];
    let vp9Hardware = false;
    let source: CodecPolicySource = "static";

    if (probes) {
        supported = BASE_CODEC_ORDER.filter(name => probes.get(name)?.supported === true);
        vp9Hardware = probes.get("VP9")?.powerEfficient === true;
        source = "media-capabilities";
    } else if (discordCodecs?.length) {
        supported = [...discordCodecs];
        source = "discord";
    }

    const supportedSet = new Set(supported);
    const allowed = supported.length > 0 ? supportedSet : null;
    const priority = buildPriority(supportedSet, vp9Hardware, forceAv1First);

    logger.debug(
        `Codec policy (${source}): supported=${supported.join(",") || "unknown"}, ` +
        `vp9Hardware=${vp9Hardware}, priority=${priority.join(" > ")}`
    );

    return { priority, allowed, supported, vp9Hardware, source };
}

/**
 * Groups a base video codec with the RTX entries that immediately follow it.
 * WebRTC requires each RTX codec to stay adjacent to its base codec, so the
 * whole group is moved together when sorting.
 */
function groupCodecs(capabilities: RTCRtpCodec[]): Array<{ name: string; codecs: RTCRtpCodec[]; }> {
    const groups: Array<{ name: string; codecs: RTCRtpCodec[]; }> = [];

    for (const codec of capabilities) {
        const name = codecName(codec.mimeType);
        if (name === "RTX" && groups.length > 0) {
            groups[groups.length - 1].codecs.push(codec);
            continue;
        }
        groups.push({ name, codecs: [codec] });
    }

    return groups;
}

function rankOf(name: string, priority: string[]): number {
    const index = priority.indexOf(name);
    return index === -1 ? priority.length : index;
}

/**
 * Orders browser video capabilities according to a resolved codec policy.
 * Codecs outside the platform's encode set are dropped, except for utility
 * codecs (RTX/RED/FEC), which are always kept at the end.
 */
export function orderVideoCodecs(capabilities: RTCRtpCodec[], policy: CodecPolicy): RTCRtpCodec[] {
    if (capabilities.length === 0) return capabilities;

    const groups = groupCodecs(capabilities).filter(group => {
        if (!policy.allowed) return true;
        if (UTILITY_CODECS.has(group.name)) return true;
        return policy.allowed.has(group.name);
    });

    if (groups.length === 0) return capabilities;

    groups.sort((a, b) => rankOf(a.name, policy.priority) - rankOf(b.name, policy.priority));
    return groups.flatMap(group => group.codecs);
}
