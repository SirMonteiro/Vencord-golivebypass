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

## ADR-004: Mirror Discord's codec order instead of forcing AV1

**Status:** accepted (2026-11-07)

**Context:** The previous implementation explicitly preferred AV1, then HEVC,
VP9, VP8, H264. Broadcast Box and most WebRTC decoders are more reliable with
H264/VP8, and Discord's native stream encoder defaults to H264 with VP8 as the
fallback.

**Decision:**

1. Query Discord's media engine for encodable codecs (500 ms timeout).
2. Drop codecs Discord cannot encode.
3. Order as `H264 → VP8 → VP9 → AV1 → H265/HEVC → utility`.
4. Keep RTX adjacent to its base codec.
5. Fall back to the same static order when the probe returns nothing.

**Consequences:** AV1 is no longer prioritized. It remains a last-resort
fallback. The stream is more likely to negotiate the same codec Discord would
have used.

**Open:** whether AV1 should be removed entirely (see below).

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

### Q1. Should AV1 be disabled entirely?

Current behavior: `H264 → VP8 → VP9 → AV1` (AV1 last resort).

Options:

- **A. Keep AV1 last** (current). Maximum compatibility fallback.
- **B. Allow only H264/VP8**. Closest to Discord's documented stream codecs;
  no risk of an AV1 negotiation Broadcast Box mishandles.
- **C. Add a setting** (`allowAv1`, default off). Requires a settings entry and a
  re-negotiation path.

### Q2. Should the plugin add a TURN option?

Current behavior: STUN only. If participants behind restrictive NATs matter, a
TURN URL/credential setting is needed.

### Q3. How should the PiP black-screen issue be fixed?

Current behavior: `VideoHook` only reliably covers the main tile. Options:

- **A. Extend `StreamWatcher` discovery** to PiP containers and re-attach on DOM
  replacement.
- **B. Re-apply the hook on every mutation** for the active PiP element.
- **C. Replace the PiP surface with a canvas/`captureStream` renderer** (larger
  change, more CPU).

Recommended: A + B, keeping the existing `VideoHook` contract.

### Q4. Documentation language

This documentation is written in English to match the code and Vencord upstream.
If Portuguese is preferred, the files can be translated.

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