# Architecture Decisions

ADR-style notes for decisions that are easy to revisit incorrectly.

---

## ADR-001: Video-only WHIP/WHEP

**Status:** accepted

**Context:** Discord already carries voice audio. Adding audio to the Broadcast
Box ingest would duplicate audio, complicate mute/deafen semantics and require
server-side mixing decisions.

**Decision:** Publish and subscribe video only. Audio always stays on Discord's
native path.

**Consequences:** No audio in the Broadcast Box player. The plugin cannot be used
as a standalone audio broadcaster.

---

## ADR-002: Tap Discord's native track instead of re-capturing

**Status:** accepted

**Context:** The plugin must send the exact screen the user chose in Discord's Go
Live dialog, at the same capture settings.

**Decision:** Prefer `window.createDiscordStream` / DirectVideo's native
`MediaStream`. Fall back to `getDisplayMedia`/`getUserMedia` only when the native
track is unavailable.

**Consequences:** The plugin depends on Discord internals for the best path, but
the fallback keeps it usable on Vesktop/Web.

---

## ADR-003: Apply quality to the RTP sender, not the capture

**Status:** accepted

**Context:** Discord's Go Live dialog selects a height and frame rate. Applying
`track.applyConstraints` would also change the track Discord sends to its own
servers and can be rejected by display-capture tracks.

**Decision:** Keep the native track untouched. Apply
`maxFramerate`/`scaleResolutionDownBy` to the WHIP `RTCRtpSender` only.

**Consequences:**

- The Broadcast Box feed matches the requested height/fps when the capture is
  large enough.
- The native Discord stream keeps its own quality.
- The plugin never upscales; a 720p capture cannot become 1080p.

**Alternatives rejected:** `applyConstraints` on a clone (shared source may
affect the original), canvas re-encode (CPU cost, extra failure mode).

---

## ADR-004: Platform-aware codec order with VP9 hardware detection

**Status:** accepted (2026-11-07)

**Context:** The previous implementation explicitly preferred AV1, which
Broadcast Box and most WebRTC decoders handle poorly. The maintainer wants VP9
when it is hardware accelerated, otherwise the first codec the platform
supports, and AV1 only as a last resort.

**Decision:**

1. Probe `navigator.mediaCapabilities.encodingInfo({ type: "webrtc" })` for VP9,
   H265, VP8, H264 and AV1. `powerEfficient` identifies hardware acceleration.
2. If MediaCapabilities is unavailable, use Discord's
   `getCodecCapabilities` list (500 ms timeout).
3. If both are unavailable, use the static order with AV1 last.
4. Priority:
   - VP9 hardware accelerated → `VP9 → H265 → VP8 → H264 → AV1`.
   - Otherwise → promote the first supported codec in
     `VP9 → H265 → VP8 → H264 → AV1`.
   - `forceAv1First` (off by default) → `AV1` first.
5. Drop codecs the platform cannot encode; keep RTX adjacent to its base codec.

**Consequences:** AV1 is never first unless the experimental setting is enabled.
VP9 software encoding may be chosen on machines without hardware VP9 because it
is the first supported codec in the requested list. H265 is usually not
supported by browsers today and is filtered out.

**Open:** whether the "first supported" fallback should consider only
hardware-accelerated codecs; see below.

---

## ADR-005: Persistent WHEP subscriptions decoupled from DOM

**Status:** accepted

**Context:** Discord re-renders call tiles frequently. Reconnecting WHEP per
render would cause freezes and connection churn.

**Decision:** One `WhepSubscription` per `<userId>-<kind>`, kept alive across
element attach/detach with a 25 s orphan grace period, 3 s retry and connection
generations.

**Consequences:** Faster tile changes and popouts. The subscription outlives a
single `<video>` element.

---

## ADR-006: Lock `srcObject` on the video element

**Status:** accepted (for the main tile)

**Context:** Discord's media engine assigns its own `MediaStream` to the tile and
can overwrite the WHEP stream after a render.

**Decision:** Once the WHEP stream is applied, redefine the element's own
`srcObject` property: the getter returns the WHEP stream, the setter is a no-op.
Restore the native descriptor on destroy.

**Consequences:** Works for the main/fullscreen/theater tile. PiP and some
re-created surfaces are not reliably covered; see the open question below.

---

## ADR-007: No TURN server

**Status:** accepted for now

**Context:** The plugin only ships public STUN servers.

**Decision:** Rely on STUN + Broadcast Box's public endpoint.

**Consequences:** Participants behind symmetric NAT or restrictive firewalls may
fail to connect. Adding TURN is a deployment decision (credentials, cost,
privacy).

---

## ADR-008: Build through a copy, not a symlink

**Status:** accepted

**Context:** esbuild resolves a symlinked plugin to its real path outside the
Vencord root, then fails to resolve Vencord's path aliases.

**Decision:** `build.sh` copies `BroadcastBoxScreenShare/` into
`src/userplugins/` before building.

**Consequences:** The plugin source remains in the project repository; the clone
always builds from a snapshot. Remember to run `build.sh`, not `pnpm build`
alone, after editing the plugin.

---

## Open questions

These need a product/architecture decision from the maintainer.

### Q1. Does "first supported" mean hardware-supported?

Resolved: AV1 is last resort and `forceAv1First` is an experimental setting,
off by default. One ambiguity remains:

- Current behavior: if VP9 is not hardware accelerated, promote the first
  codec **the platform supports** (including software VP9).
- Alternative: promote the first codec **with hardware acceleration**; if none,
  fall back to `VP8 → H264`.

This only matters on machines where VP9 is software-only. Confirm which reading
is intended.

### Q2. Should the plugin add a TURN option?

Current behavior: STUN only. If participants behind restrictive NATs matter, a
TURN URL/credential setting is needed.

### Q3. How should the PiP black-screen issue be fixed?

Chosen approach: **A + B**.

- Extend `StreamWatcher` discovery to PiP containers.
- Re-apply the active hook on DOM mutations when the element is replaced.
- Keep the existing `VideoHook` contract; no canvas re-encode.

Implementation is deferred until the initial compile/publisher fix is approved.

### Q4. Documentation language

Resolved: English, matching the code and Vencord upstream.

### Q5. Audio in the Broadcast Box feed

Current behavior: video only. Confirm that viewers should never receive audio
from Broadcast Box (voice remains on Discord).

---

## Changelog of decisions

| Date | Change |
| --- | --- |
| 2026-11-07 | Fixed TypeScript strict-narrowing errors in `WhepSubscription` stale callbacks. |
| 2026-11-07 | Replaced AV1-first codec order with Discord-style H264/VP8 priority. |
| 2026-11-07 | Removed hard-coded 1080p30; quality now comes from Discord and the capture. |