# BroadcastBoxScreenShare — Documentation

This folder documents the **BroadcastBoxScreenShare** Vencord plugin that runs
inside Vesktop. The plugin replaces Discord's native Go Live/WebRTC screen share
with a WHIP ingest to a self-hosted [Broadcast Box](https://github.com/glimesh/broadcast-box)
instance, and replaces the incoming Discord stream playback with a WHEP
subscription from the same instance.

## Reading order

| Document | What it covers |
| --- | --- |
| [architecture.md](./architecture.md) | Component boundaries, responsibilities, SOLID decisions and state ownership. |
| [plugin-flow.md](./plugin-flow.md) | End-to-end runtime flows for publishing, viewing, UI interception and teardown. |
| [modules.md](./modules.md) | Per-file and per-symbol reference for every module in the plugin. |
| [protocol.md](./protocol.md) | WHIP/WHEP and Broadcast Box API usage, stream keys, ICE and codecs. |
| [development.md](./development.md) | Local build, VM/Vesktop workflow, console verification and troubleshooting. |
| [decisions.md](./decisions.md) | Architecture decisions in ADR form, plus open questions. |

## Source layout

```text
BroadcastBoxScreenShare/
├── index.tsx                    # Plugin entry point, Discord hooks, publisher manager
├── whip.ts                      # WHIP publish and WHEP subscribe primitives
├── WhepSubscription.ts          # One persistent WHEP connection per remote stream
├── WhepSubscriptionManager.ts   # Registry of all WHEP subscriptions
├── StreamWatcher.ts             # Finds Discord <video> tiles, binds them to subscriptions
├── VideoHook.ts                 # Locks a <video> element to a WHEP MediaStream
├── VideoInjector.ts             # Compatibility re-export of VideoHook
├── types.ts                     # Shared TypeScript types
├── native.ts                    # Main-process CSP allow-list for Broadcast Box
├── discordCodecs.ts             # Discord-compatible codec ordering
├── streamQuality.ts             # Extracts Discord's Go Live resolution/frame-rate
└── senderQuality.ts             # Applies quality to the WHIP RTP sender
```

## One-paragraph summary

When the user starts a screen share, Discord calls `MediaEngineActions.setGoLiveSource`.
The plugin intercepts that call, taps the native capture track (or falls back to
`getDisplayMedia`), and publishes a **video-only** WHIP session to
`https://stream.gabrielsouza.top/api/whip` using the stream key
`<discordUserId>-scrn`. Every call participant runs the same plugin; when a
remote participant's `<video>` tile appears, the plugin identifies whether it is
a screen share or camera, opens a persistent WHEP subscription for
`<remoteUserId>-scrn`/`-cam`, and forces that `<video>` element to render the
WHEP `MediaStream`. Discord's own WebRTC stream still exists, but the tile is
visually replaced by the Broadcast Box feed.