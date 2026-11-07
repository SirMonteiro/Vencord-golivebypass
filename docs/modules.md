# Module Reference

This is the symbol-level reference for every source file in
`BroadcastBoxScreenShare/`.

## `types.ts`

Shared types only.

| Symbol | Meaning |
| --- | --- |
| `StreamKind` | `"scrn" | "cam"`. Used as the Broadcast Box key suffix and publisher/camera selector. |
| `WhipSession` | Contract for an active WebRTC session: `id`, `pc`, `resourceUrl`, `close()`. Used by both publisher and subscriber. |
| `SubscriptionState` | `"idle" | "connecting" | "connected" | "reconnecting" | "closed"`. |

## `index.tsx`

The plugin entry point and Discord integration layer.

### Settings

```ts
definePluginSettings({
    baseUrl: {
        type: OptionType.STRING,
        description: "Broadcast Box base URL (no trailing slash)",
        default: "https://stream.gabrielsouza.top"
    },
    forceAv1First: {
        type: OptionType.BOOLEAN,
        description: "Experimental: force AV1 to the front of codec negotiation (off by default)",
        default: false
    }
});
```

`baseUrl` is read through a getter when creating subscriptions and publishers so
a settings edit applies to new sessions without a restart. `forceAv1First` is
experimental and off by default. The CSP host in `native.ts` is **not** dynamic.

### `class PublisherManager`

Owns the publishing lifecycle for `scrn` and `cam`.

| Field | Purpose |
| --- | --- |
| `active: Map<StreamKind, WhipSession>` | Connected WHIP sessions. |
| `pending: Map<StreamKind, { abort, id }>` | Sessions still negotiating; can be aborted. |
| `currentTrackId` | Track currently attached per kind. |
| `currentStreamId` | Discord stream ID per kind. |
| `sessionCounter` | Diagnostic session number. |

| Method | Behavior |
| --- | --- |
| `isCurrent(kind, streamId?, trackId?)` | True when a session/pending session exists and the provided IDs match. Used to ignore duplicate acquisition callbacks. |
| `isBusy(kind)` | `active` or `pending` exists. |
| `start(kind, track, streamId?, quality?)` | If connected and only the track changed, `replaceTrack` + sender quality. Otherwise abort pending, stop active, build token `<userId>-<kind>`, call `publish` (including `forceAv1First` from settings), register the session. |
| `stop(kind)` | Abort pending, clear IDs, close the active session. |
| `stopAll()` | Stops both kinds. |

The `quality` argument is passed to `publish` and to `applySenderQuality` on
track replacement.

### `interface DirectVideoHandle` / `DirectVideoModule`

Shape of Discord's internal direct-video module (`nz(streamId)` returns a
`MediaStream` plus an optional `release`).

### `class DirectVideoManager`

| Method | Behavior |
| --- | --- |
| `findModule()` | Tries webpack module `229209`, then scans `wreq.m` factories for `Direct video streams are unavailable` / `createDiscordStream` + `addDirectVideoOutputSink`. Caches the module. |
| `acquire(streamId)` | Returns a cached stream if present; otherwise calls `nz(streamId)`, stores the stream and release callback. |
| `cacheStream` / `getCachedStream` / `clearCache` | Stream cache keyed by Discord stream ID. |
| `releaseDesktop` / `releaseCam` / `releaseAll` | Invoke stored release callbacks and clear the cache. |

### Module-level state

| Variable | Purpose |
| --- | --- |
| `currentDesktopTrack` | The native screen track currently published. |
| `currentCamTrack` | The native camera track currently published. |
| `isScreenSharingActive` / `isCameraActive` | Whether Discord believes each capture is active. |
| `ownScreenshareStreamId` / `ownCameraStreamId` | Discord stream IDs for the local user. |
| `requestedScreenQuality` | `StreamQuality` read from `setGoLiveSource`. |

### Media helpers

| Function | Behavior |
| --- | --- |
| `hasVideoTracks(val)` | Safe check for `getVideoTracks().length > 0`. |
| `isDesktopCapture(constraints)` | Detects `chromeMediaSource === "desktop" | "screen"`. |
| `extractDesktopSourceId(sourceConfig)` | Reads `desktopDescription.id`, `desktopSource.id`, `id`, or a string config. |
| `onDesktopStreamAcquired(stream, hint, streamId?)` | Rejects wrong/camera/duplicate tracks, merges requested + actual quality, calls `publisherManager.start("scrn", ...)`. |
| `onCameraStreamAcquired(stream, hint, streamId?)` | Same for `"cam"` using the track's own settings. |
| `acquireStreamForKind(streamId, kind, retryCount)` | Cached direct video → `acquire`; on failure retries up to 10 times with a linear backoff. |
| `handleGoLiveSourceChange(sourceConfig)` | Stop/start/fallback logic for screenshare. |
| `handleCameraToggle(enabled)` | Stop/start/fallback logic for camera. |

### Hooks

| Function | Behavior |
| --- | --- |
| `installDiscordStreamHook()` | Wraps `window.createDiscordStream`, caches every video stream and feeds it to the active publisher. |
| `installSrcObjectHook()` | Wraps the `srcObject` setter; when a `VideoHook` owns the element, the native assignment is ignored. |
| `installMediaEngineHooks()` | Wraps `setGoLiveSource` and `setVideoEnabled`. |
| `installMediaDevicesHooks()` | Wraps `getUserMedia` and `getDisplayMedia`; clones tracks, binds teardown and publishes. |
| `installDispatcherInterceptors()` | Suppresses Discord stream-timeout actions. |
| `uninstall*` | Restore the original functions/descriptors. |

### `bindTrackTeardown(original, cloned, kind)`

Marks the publisher as stopped when either the original or cloned track ends or
`stop()` is called. Idempotent through a `cleaned` flag.

### `definePlugin`

- `name`: `BroadcastBoxScreenShare`
- `authors`: SirMonteiro
- `settings`
- `flux` handlers: `MEDIA_ENGINE_SET_GO_LIVE_SOURCE`,
  `MEDIA_ENGINE_SET_VIDEO_ENABLED`, `RTC_CONNECTION_VIDEO`, `STREAM_DELETE`,
  `VOICE_STATE_UPDATES`, `VOICE_CHANNEL_SELECT`.
- `start()` installs hooks and starts `StreamWatcher`.
- `stop()` uninstalls hooks, tears down media and stops the watcher.

## `whip.ts`

Protocol primitives. It has no Discord dependency.

### Constants

| Name | Value / purpose |
| --- | --- |
| `ICE_SERVERS` | Cloudflare STUN (3478/53) and Google STUN. |
| `sessionStore` | In-memory `token → Location URL` map. |

### Functions

| Function | Behavior |
| --- | --- |
| `postSdp(endpoint, sdp, token, protocol, signal)` | POSTs `application/sdp` with Bearer auth, returns `{ sdp, location }`. Logs status and server error body. |
| `resolveUrl(base, path)` | Resolves the `Location` header against the base URL. |
| `waitForIceGathering(pc, token, protocol, timeoutMs = 1500, signal)` | Resolves on `complete` or timeout; rejects on abort. |
| `deleteWhipSession(url, token)` | `DELETE` with Bearer auth; tolerates 404/405. |
| `getSavedSessionUrl` / `setSavedSessionUrl` / `removeSavedSessionUrl` | Persist the WHIP resource URL in memory + `sessionStorage` so a reload can clear a stale host slot. |
| `publish(...)` | Full WHIP publish. See below. |
| `applyCodecPreferences(transceiver, protocol)` | Async; picks sender or receiver capabilities, asks `discordCodecs` for the order, calls `setCodecPreferences`. |
| `subscribe(...)` | Full WHEP subscribe. See below. |

### `publish(whipUrl, token, track, options?)`

`PublishOptions`:

| Option | Meaning |
| --- | --- |
| `onCreated` | Called with the peer connection immediately after creation. |
| `signal` | Abort signal for the whole negotiation. |
| `quality` | Discord Go Live `StreamQuality` to mirror on the sender. |
| `forceAv1First` | Experimental codec override (off by default). |

Steps:

1. Logs track kind/id/label/readyState and `getSettings()`.
2. Deletes a previously saved session for the same token (stale slot cleanup).
3. Creates `RTCPeerConnection` with `bundlePolicy: "max-bundle"`.
4. Adds a **sendonly** video transceiver.
5. Resolves the codec policy and applies it.
6. Creates the offer, sets the local description, waits for ICE (1.5 s cap).
7. POSTs the offer; applies the answer.
8. Applies `quality` to the sender via `applySenderQuality`.
9. Persists `Location` and returns a `WhipSession`.
10. `close()` clears the stats interval, sends `DELETE`, removes the saved URL and
    closes the peer connection.

Stats are logged every 5 s after the connection reaches `connected`.

### `subscribe(whepUrl, token, onTrack, signal?)`

1. Creates a peer connection.
2. Adds a **recvonly** video transceiver.
3. Applies codec preferences.
4. Creates/sets the offer, waits for ICE, POSTs to WHEP.
5. Applies the answer.
6. Calls `onTrack(stream, track)` for every received track (video is consumed by
   the caller).
7. `close()` only closes the peer connection; it never `DELETE`s the WHEP
   session because viewers do not own the ingest.

## `WhepSubscription.ts`

One persistent WHEP connection per remote stream key (`<userId>-<kind>`).

### Fields

| Field | Purpose |
| --- | --- |
| `userId`, `kind`, `token` | Identity of the remote stream. |
| `baseUrl` | Broadcast Box base URL (trailing slashes trimmed). |
| `state` | `SubscriptionState`. |
| `session` | Active `WhipSession`. |
| `mediaStream` / `activeTrack` | Last received stream/track. |
| `attachedElements` | DOM elements currently bound. |
| `streamListeners` | Callbacks for each attached element. |
| `abortController` | Aborts the in-flight connection. |
| `retryTimer` / `orphanTimer` | Reconnect and grace timers. |
| `connectionGen` | Monotonic generation; stale callbacks are ignored. |

### Methods

| Method | Behavior |
| --- | --- |
| `getState()` / `getStream()` / `isAlive()` / `isConnected()` / `getAttachedCount()` | Read-only accessors. |
| `start()` | Starts if `idle`; does nothing if connecting/connected; refuses when `closed`. |
| `attach(videoEl, onStream)` | Adds the element/listener, cancels the orphan timer, delivers the current stream immediately, starts if idle. Returns a detach function. |
| `close()` | Sets `closed`, aborts, clears timers, clears listeners, closes the session. |
| `isStale(gen)` | `state === "closed" || gen !== connectionGen`. |
| `scheduleOrphanGraceTimer()` | After the last element detaches, closes the subscription after 25 s if nothing re-attaches. |
| `scheduleRetry()` | Sets `reconnecting` and retries `connect()` after 3 s. |
| `connect()` | Builds the WHEP session, wires track/connection listeners, notifies listeners, retries on failure unless stale. |

## `WhepSubscriptionManager.ts`

Registry keyed by `<userId>-<kind>`.

| Method | Behavior |
| --- | --- |
| `getOrCreate(userId, kind, baseUrl)` | Returns an alive subscription or replaces a dead one. |
| `get(userId, kind)` | Read-only lookup. |
| `close(userId, kind)` | Closes and removes one entry. |
| `closeForUser(userId)` | Closes both kinds for a user. |
| `closeAll()` | Closes every entry. |

## `StreamWatcher.ts`

Discovers Discord `<video>` elements and binds them to WHEP subscriptions.

### Helpers

| Function | Behavior |
| --- | --- |
| `getAllDocuments()` | Main document + every `PopoutWindowStore` document. |
| `isUserStreaming(userId)` | `ApplicationStreamingStore.getAnyStreamForUser`. |
| `isUserCameraActiveInVoiceState(userId)` | Voice state `selfVideo`. |
| `hasCameraIconInUserList(userId, doc)` | Scans user list icons. |
| `tileHasCameraError(tile)` | Detects Discord camera-failure text. |
| `getFiber(node)` | Finds the React fiber key on a DOM node. |
| `isCameraActiveForUser(userId, tile)` | Voice state, icon, error text, fiber props. |
| `hasLiveBadgeInTile(tile)` | Live indicator/overlay/aria-label. |
| `getUserIdFromVideo(video)` | Tile attributes → React fiber props → ancestor attributes. |
| `resolveStreamKind(video, userId)` | The 6-step heuristic described in [plugin-flow.md](./plugin-flow.md). |
| `qualifyVideo(video)` | Returns `{ userId, kind }` or `null`; skips the current user. |

### `class StreamWatcher`

| Member | Behavior |
| --- | --- |
| `constructor(getBaseUrl)` | Stores the settings getter. |
| `start()` | Installs a 250 ms debounced `MutationObserver` on each document and a periodic scan; also listens for popout window creation. |
| `stop()` | Disconnects observers, clears intervals, destroys every `VideoHook`. |
| `scan()` | Walks every document and processes qualifying videos. |
| `ensureHook(video, info)` | Reuses an existing hook for the same subscription, otherwise creates `VideoHook` and starts the subscription. |
| `prune()` | Destroys hooks whose element left the DOM, and re-applies hooks when Discord re-rendered styles. |

## `VideoHook.ts`

Binds one `<video>` element to one `WhepSubscription`.

| Member | Behavior |
| --- | --- |
| `NATIVE_SRC_OBJECT_DESC` | Captured native `srcObject` descriptor so it can be restored. |
| `nativeSet(el, value)` | Uses the native setter directly. |
| `constructor(videoEl, subscription)` | Calls `subscription.attach(...)`. |
| `getUserId()` / `getKind()` | Identity from the subscription. |
| `isActive()` | Element is still in the document. |
| `reapply()` | Re-applies the stream when Discord replaced the descriptor or paused the element. |
| `destroy()` | Detaches and restores native DOM state. Does not close the subscription. |
| `applyStream(stream)` | Sets autoplay/playsinline/muted, native `srcObject`, locks the property, calls `play()`, wires frame-ready events, hides placeholders. |
| `hasRenderedFrames()` | `readyState >= 2` and non-zero video dimensions. |
| `hidePlaceholders()` | Hides loading spinners/covers while preserving overlays and indicators. |
| `restoreNativeState()` | Deletes the instance `srcObject`, sets `null` via the native setter, un-hides placeholders. |

## `VideoInjector.ts`

Compatibility surface:

```ts
export { VideoHook, VideoHook as VideoInjector } from "./VideoHook";
export type { VideoInjectorOpts } from "./StreamWatcher";
```

`index.tsx` imports `VideoHook` directly; the alias exists for older code and
external imports.

## `native.ts`

Registers the Broadcast Box host in Vencord's main-process CSP allow-list:

```ts
CspPolicies[BROADCAST_BOX_HOST] = ConnectSrc;
```

`BROADCAST_BOX_HOST` is hard-coded to `stream.gabrielsouza.top`. If `baseUrl` is
changed, update this constant and restart the client.

## `discordCodecs.ts`

Codec policy: platform probing, priority building and capability ordering.

### Constants

| Name | Behavior |
| --- | --- |
| `BASE_CODEC_ORDER` | `VP9 → H265 → VP8 → H264 → AV1`. |
| `UTILITY_CODECS` | `RTX`, `RED`, `ULPFEC`, `FLEXFEC`, `FLEXFEC-03`; always kept after real codecs. |
| `CODEC_CONTENT_TYPES` | Maps codec names to `MediaCapabilities` MIME types (`video/VP9`, ...). |

### Functions

| Symbol | Behavior |
| --- | --- |
| `getDiscordEncodeCodecs()` | Calls `MediaEngineStore.getMediaEngine().getCodecCapabilities(cb)` with a 500 ms timeout, parses the JSON array and returns encodable names, or `null`. Cached. |
| `probeCodec(name, quality)` | `navigator.mediaCapabilities.encodingInfo({ type: "webrtc", video: ... })` for one codec. Returns `supported`, `smooth`, `powerEfficient`. |
| `probeAllCodecs(quality)` | Probes every `BASE_CODEC_ORDER` codec in parallel. |
| `resolveCodecPolicy({ quality, forceAv1First })` | Chooses the effective policy. Priority: MediaCapabilities probe → Discord's encode list → static order. |
| `groupCodecs(caps)` | Groups each base codec with the RTX entries that follow it. |
| `orderVideoCodecs(caps, policy)` | Drops codecs outside `policy.allowed` (keeping utility codecs), sorts by `policy.priority`, keeps RTX adjacent, and falls back to the original list if filtering removes everything. |

### Policy rules

1. If `forceAv1First` is enabled: `AV1 → VP9 → H265 → VP8 → H264`.
2. Else if VP9 encoding is hardware-accelerated (`powerEfficient === true`):
   `VP9 → H265 → VP8 → H264 → AV1`.
3. Else: promote the first supported codec in `VP9 → H265 → VP8 → H264 → AV1`
   and keep the remaining supported codecs as fallbacks.
4. AV1 is always moved to the end unless `forceAv1First` is enabled.

`resolveCodecPolicy` logs the chosen source, VP9 hardware flag and final order at
debug level.

## `streamQuality.ts`

| Symbol | Behavior |
| --- | --- |
| `StreamQuality` | `{ width?, height?, frameRate? }`. |
| `qualityFromGoLiveSource(sourceConfig)` | Reads `quality.resolution/height`, `qualityOptions.resolution`, `quality.frameRate/fps`, or top-level values. Returns `null` when nothing is present. |
| `qualityFromTrack(track)` | Reads `track.getSettings()` width/height/frameRate. |
| `mergeQuality(requested, actual)` | Requested values win; actual values fill gaps. |

## `senderQuality.ts`

| Function | Behavior |
| --- | --- |
| `applySenderQuality(sender, track, requested)` | Reads `sender.getParameters()`, ensures one encoding, sets `maxFramerate = min(requested, actual)` and `scaleResolutionDownBy = actual.height / requested.height` when downscaling is needed, then `setParameters`. Best-effort: failures only log. |