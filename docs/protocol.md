# Protocol and Broadcast Box API

## 1. Stream identity

Broadcast Box identifies a stream by its **stream key**. The plugin uses:

| Kind | Key | Direction |
| --- | --- | --- |
| Screen share | `<DiscordUserId>-scrn` | Publish WHIP, receive WHEP |
| Camera | `<DiscordUserId>-cam` | Publish WHIP, receive WHEP |

The same key is the bearer token for both WHIP and WHEP. The `-scrn`/`-cam`
suffix lets one user publish both streams without collisions.

The player URL is therefore:

```text
https://stream.gabrielsouza.top/<DiscordUserId>-scrn
https://stream.gabrielsouza.top/<DiscordUserId>-cam
```

## 2. Endpoints used by the plugin

| Endpoint | Method | Auth | Purpose |
| --- | --- | --- | --- |
| `/api/whip` | `POST` | `Bearer <userId>-<kind>` | Start a WHIP ingest. Body: SDP offer. Returns SDP answer + `Location`. |
| `/api/whip/{sessionID}` | `PATCH` | `Bearer <userId>-<kind>` | Trickle ICE for an ingest (not currently used; the plugin sends a complete offer). |
| `/api/whip/{sessionID}` | `DELETE` | `Bearer <userId>-<kind>` | End an ingest session. |
| `/api/whep` | `POST` | `Bearer <userId>-<kind>` | Start a WHEP playback session. Body: SDP offer. Returns SDP answer + `Location`. |
| `/api/whep/{sessionID}` | `PATCH` | `Bearer <userId>-<kind>` | Trickle ICE for playback (not currently used). |
| `/api/status` | `GET` | none | List active public WHIP streams. `?key=<streamKey>` returns one stream. |

The plugin does **not** call `/api/sse`, `/api/layer`, `/api/log` or the admin
endpoints.

## 3. WHIP publish sequence

```http
POST /api/whip HTTP/1.1
Host: stream.gabrielsouza.top
Authorization: Bearer 123456789012345678-scrn
Content-Type: application/sdp
Accept: application/sdp

v=0
o=- ... IN IP4 0.0.0.0
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF ...
a=sendonly
...
```

Successful response:

```http
HTTP/1.1 201 Created
Content-Type: application/sdp
Location: /api/whip/abc123

v=0
...
```

The plugin resolves `Location` against `baseUrl` and stores it in
`sessionStorage` under `whip_res_<token>`. On the next publish for the same
token it first sends `DELETE` to that URL, which frees a host slot left behind by
a crash or reload.

## 4. WHEP subscribe sequence

```http
POST /api/whep HTTP/1.1
Host: stream.gabrielsouza.top
Authorization: Bearer 123456789012345678-scrn
Content-Type: application/sdp
Accept: application/sdp

...offer with a=recvonly...
```

The answer's tracks are passed to `WhepSubscription`, which emits the first
`MediaStream` to every attached `<video>` element.

A WHEP viewer must **not** send `DELETE`: the viewer does not own the ingest
session. `WhepSubscription.close()` only closes the local peer connection; the
server expires the viewer session on its own.

## 5. ICE

```ts
const ICE_SERVERS = [
    { urls: ["stun:stun.cloudflare.com:3478", "stun:stun.cloudflare.com:53"] },
    { urls: ["stun:stun1.l.google.com:19302", "stun:stun2.l.google.com:19302"] }
];
```

- Cloudflare STUN is anycast and usually reachable when Google STUN is throttled.
- There is **no TURN server**. If a participant is behind a restrictive NAT or
  firewall, the WHEP connection can fail. Adding TURN is an open decision in
  [decisions.md](./decisions.md).
- The plugin uses non-trickle ICE: it waits up to 1.5 s for gathering to finish,
  then sends the SDP with all candidates. This is simpler and works with
  Broadcast Box's WHIP endpoint.

## 6. Codec negotiation

Broadcast Box (Pion) supports H264, VP8, VP9 and AV1 depending on its build.
The plugin resolves its codec order at publish/subscribe time:

1. **MediaCapabilities probe** (`type: "webrtc"`) for VP9, H265, VP8, H264 and
   AV1. `powerEfficient` tells whether the codec is hardware accelerated.
2. **Discord capability list** if MediaCapabilities is unavailable.
3. **Static order** if both are unavailable.

Policy:

| Condition | Order |
| --- | --- |
| VP9 hardware accelerated | `VP9 → H265 → VP8 → H264 → AV1` |
| No VP9 hardware | Promote the first supported codec in `VP9 → H265 → VP8 → H264 → AV1`; AV1 last |
| `forceAv1First` setting | `AV1 → VP9 → H265 → VP8 → H264` |

Codecs the platform cannot encode are removed. RTX stays adjacent to its base
codec. AV1 is never first unless the experimental setting is enabled.

The final codec is still whatever Broadcast Box negotiates from this offer; the
order only expresses preference.

The receiver side (WHEP) uses the receiver capabilities with the same policy;
the final playback codec is selected by the server's offer/answer.

## 7. Resolution and frame rate

Discord's Go Live dialog stores a **height** and a **frame rate**, for example:

```ts
{ quality: { resolution: 720, frameRate: 60 } }
```

The plugin translates that into WHIP sender parameters:

```ts
sender.setParameters({
    encodings: [{
        maxFramerate: Math.min(requestedFps, captureFps),
        scaleResolutionDownBy: captureHeight / requestedHeight
    }]
});
```

Rules:

- Never upscale. If the capture is smaller than the request, the capture size is
  kept.
- Never exceed the capture frame rate.
- The native Discord track is not constrained, so Discord's own Go Live keeps
  its quality.
- If the request is unavailable (older Discord payload), the track's own
  settings are used. There is no hard-coded 1080p30 default.

## 8. Verifying a live stream from the host

Broadcast Box exposes a public status endpoint:

```bash
curl -s https://stream.gabrielsouza.top/api/status | jq
curl -s 'https://stream.gabrielsouza.top/api/status?key=<userId>-scrn' | jq
```

A healthy ingest shows a session for the key with the expected video layer. The
plugin's own logs also print:

```text
[WHIP] Track settings: 1920x1080 @ 60fps
Applied sender quality target 720p @ 60fps (capture 1920x1080 @ 60fps).
[WHIP] [<userId>-scrn] PeerConnection connectionState: connected
```

## 9. CSP

`native.ts` adds `stream.gabrielsouza.top` to Vencord's main-process
`ConnectSrc` policy. `fetch`, WebRTC signalling and the WHIP/WHEP POSTs are
allowed by that policy. Changing `baseUrl` without updating
`BROADCAST_BOX_HOST` will cause the renderer's requests to be blocked.

## 10. Error handling

| Situation | Behavior |
| --- | --- |
| WHIP POST non-2xx | Error includes status + response body; publisher session fails and is cleaned up. |
| WHIP DELETE failure | Logged as a warning; local peer connection still closes. |
| WHEP POST failure | `WhepSubscription` schedules a retry after 3 s. |
| ICE failure | `connectionstatechange` → retry. |
| Track ended | Retry; if the subscription is closed or orphaned, stop. |
| Codec capability probe timeout | Static codec order. |
| Sender parameter rejection | Warning; stream continues at capture quality. |