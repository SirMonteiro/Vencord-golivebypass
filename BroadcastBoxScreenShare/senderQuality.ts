/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Gabriel Monteiro de Souza
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { Logger } from "@utils/Logger";

import { qualityFromTrack, StreamQuality } from "./streamQuality";

const logger = new Logger("WhipRelay:SenderQuality", "#e5a00d");

const MIN_SCALE_DELTA = 0.001;

/**
 * Aligns the outgoing RTP encoding with the quality Discord is sending.
 *
 * This deliberately changes only the WHIP sender parameters:
 * - `scaleResolutionDownBy` downscales when Discord's capture is larger than
 *   the requested Go Live height.
 * - `maxFramerate` caps at the requested frame rate (never above the capture).
 *
 * The native Discord track is never constrained, so the original Go Live
 * stream to Discord keeps its own quality and stays untouched.
 */
export async function applySenderQuality(
    sender: RTCRtpSender,
    track: MediaStreamTrack,
    requested: StreamQuality | null | undefined
): Promise<void> {
    if (!requested) return;

    const actual = qualityFromTrack(track);
    if (actual.height == null && actual.frameRate == null) return;

    let parameters: RTCRtpSendParameters;
    try {
        parameters = sender.getParameters();
    } catch (err) {
        logger.warn("Could not read sender parameters:", err);
        return;
    }

    if (!parameters.encodings || parameters.encodings.length === 0) {
        parameters.encodings = [{}];
    }

    const encoding = parameters.encodings[0];
    let changed = false;

    if (requested.frameRate != null) {
        const maxFramerate = Math.min(requested.frameRate, actual.frameRate ?? requested.frameRate);
        if (maxFramerate > 0) {
            encoding.maxFramerate = Math.round(maxFramerate);
            changed = true;
        }
    }

    if (requested.height != null && actual.height != null && actual.height > requested.height) {
        const scale = actual.height / requested.height;
        if (scale > 1 + MIN_SCALE_DELTA) {
            encoding.scaleResolutionDownBy = Number(scale.toFixed(3));
            changed = true;
        }
    }

    if (!changed) {
        logger.debug(`Sender quality already matches ${actual.width ?? "?"}x${actual.height ?? "?"} @ ${actual.frameRate ?? "?"}fps.`);
        return;
    }

    try {
        await sender.setParameters(parameters);
        logger.log(
            `Applied sender quality target ${requested.height ?? "?"}p @ ${requested.frameRate ?? "?"}fps ` +
            `(capture ${actual.width ?? "?"}x${actual.height ?? "?"} @ ${actual.frameRate ?? "?"}fps).`
        );
    } catch (err) {
        // Some WebRTC stacks reject scaleResolutionDownBy before negotiation;
        // the stream still works, it just keeps the capture resolution.
        logger.warn("Could not apply sender quality constraints:", err);
    }
}
