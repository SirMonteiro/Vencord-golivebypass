/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Gabriel Monteiro de Souza
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

/**
 * Resolution/frame-rate requested by Discord's Go Live dialog.
 * Width is optional because Discord stores the user choice as a height.
 */
export interface StreamQuality {
    width?: number;
    height?: number;
    frameRate?: number;
}

function positiveNumber(value: unknown): number | undefined {
    const parsed = typeof value === "number" ? value : Number(value);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
}

/**
 * Reads the quality from the payload Discord passes to setGoLiveSource.
 * Different Discord builds nest the values slightly differently, so both the
 * current `quality` object and the legacy `qualityOptions` shape are accepted.
 */
export function qualityFromGoLiveSource(sourceConfig: any): StreamQuality | null {
    if (!sourceConfig) return null;

    const quality = sourceConfig.quality ?? sourceConfig.qualityOptions ?? {};
    const height =
        positiveNumber(quality.resolution) ??
        positiveNumber(quality.height) ??
        positiveNumber(sourceConfig.resolution);
    const frameRate =
        positiveNumber(quality.frameRate) ??
        positiveNumber(quality.fps) ??
        positiveNumber(sourceConfig.frameRate);

    if (height == null && frameRate == null) return null;
    return { height, frameRate };
}

/** Reads the resolution/frame-rate the capture track is actually producing. */
export function qualityFromTrack(track?: MediaStreamTrack | null): StreamQuality {
    if (!track) return {};

    try {
        const settings = track.getSettings();
        return {
            width: positiveNumber(settings.width),
            height: positiveNumber(settings.height),
            frameRate: positiveNumber(settings.frameRate)
        };
    } catch {
        return {};
    }
}

/** Fills gaps in the requested quality with the track's real settings. */
export function mergeQuality(
    requested: StreamQuality | null | undefined,
    actual: StreamQuality | null | undefined
): StreamQuality {
    return {
        width: requested?.width ?? actual?.width,
        height: requested?.height ?? actual?.height,
        frameRate: requested?.frameRate ?? actual?.frameRate
    };
}
