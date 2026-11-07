/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Gabriel Monteiro de Souza
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { Logger } from "@utils/Logger";
import { MediaEngineStore } from "@webpack/common";

const logger = new Logger("WhipRelay:Codecs", "#e5a00d");

/**
 * Discord's native Go Live codec order.
 *
 * Discord encodes Live streams with H264 by default and falls back to VP8 for
 * compatibility. VP9/AV1/HEVC are platform-specific encoders and are never the
 * first choice for the "stream" context. Keeping AV1 last (instead of first)
 * avoids negotiations that Broadcast Box and most WebRTC decoders handle
 * poorly while still allowing a last-resort fallback.
 */
const DISCORD_CODEC_PRIORITY = ["H264", "VP8", "VP9", "AV1", "H265", "HEVC"];

/** Non-encodable helper codecs that must stay after the real video codecs. */
const UTILITY_CODECS = new Set(["RTX", "RED", "ULPFEC", "FLEXFEC", "FLEXFEC-03"]);

const CODEC_CAPABILITY_TIMEOUT_MS = 500;

let cachedDiscordCodecs: string[] | null | undefined;

function codecName(mimeType: string | undefined): string {
    return (mimeType?.split("/")[1] ?? "").toUpperCase();
}

/**
 * Asks Discord's media engine which video codecs it can actually encode.
 * Returns null when the native bridge is unavailable or takes too long, in
 * which case the static priority list is used.
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
                    logger.warn("Could not parse Discord codec capabilities:", err);
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
 * Orders browser video capabilities the way Discord orders its native stream
 * encoders. When Discord exposes its encode-capable codec list, codecs it
 * cannot encode are dropped entirely; otherwise the static priority applies.
 */
export function orderVideoCodecsLikeDiscord(
    capabilities: RTCRtpCodec[],
    discordCodecs?: string[] | null
): RTCRtpCodec[] {
    if (capabilities.length === 0) return capabilities;

    const nativePriority = discordCodecs?.length
        ? [
            ...DISCORD_CODEC_PRIORITY.filter(name => discordCodecs.includes(name)),
            ...DISCORD_CODEC_PRIORITY.filter(name => !discordCodecs.includes(name))
        ]
        : DISCORD_CODEC_PRIORITY;

    const encodable = discordCodecs?.length ? new Set(discordCodecs) : null;

    const groups = groupCodecs(capabilities).filter(group => {
        if (!encodable) return true;
        if (UTILITY_CODECS.has(group.name)) return true;
        return encodable.has(group.name);
    });

    if (groups.length === 0) return capabilities;

    groups.sort((a, b) => rankOf(a.name, nativePriority) - rankOf(b.name, nativePriority));
    return groups.flatMap(group => group.codecs);
}
