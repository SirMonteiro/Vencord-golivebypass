# Development and Test Workflow

## 1. Repository layout

```text
/home/gabriel/projects/Vencord-golivebypass/
├── BroadcastBoxScreenShare/     # plugin source (the only folder edited for features)
├── docs/                        # this documentation
├── vencord -> ../../clones/Vencord
└── install-vencord.*            # end-user installers

/home/gabriel/clones/Vencord/    # upstream Vencord clone used for building
├── src/userplugins/BroadcastBoxScreenShare/  # copied by build.sh
├── dist/                        # build output
└── build.sh                     # build + VM test helper
```

The VM mounts the clone through sshfs:

```text
gabriel@gabrielsworkstationlinux:/home/gabriel/clones/Vencord
    on /data/home/vencord type fuse.sshfs
```

Vesktop's `state.json` points at that mount:

```json
{ "vencordDir": "/data/home/vencord/dist" }
```

So a host build is immediately visible to the VM. Nothing needs to be copied to
the VM manually.

## 2. Prerequisites

- Node.js (`node -v`; the clone currently expects pnpm 12.15, a nearby version
  works).
- `pnpm`.
- The upstream Vencord clone at `/home/gabriel/clones/Vencord`.
- `instabox` CLI signed in.
- The `instabox-sirmonteiro` box running with Vesktop installed at
  `~/Desktop/vesktop`.

Install dependencies once:

```bash
cd /home/gabriel/clones/Vencord
pnpm install --frozen-lockfile
```

If pnpm fails with `ERR_PNPM_STORE_DIR_OPEN_OPERATION_LOCK` or a permission
error on the store, fix the store directory permissions (the user already did
this once) or pass `--store-dir`.

## 3. Building

Always build from the clone, never from the plugin folder:

```bash
cd /home/gabriel/clones/Vencord
./build.sh
```

`build.sh` copies `BroadcastBoxScreenShare/` into
`src/userplugins/BroadcastBoxScreenShare/` and runs `pnpm build`.

> Do not symlink the plugin folder into `src/userplugins`. esbuild resolves the
> real path outside the Vencord root and then cannot resolve Vencord's `@api`,
> `@utils` and `@webpack` aliases. A real copy is required.

### Helper flags

| Command | What it does |
| --- | --- |
| `./build.sh` | Copy + build. |
| `./build.sh --test` | `pnpm test:ts`, `eslint` on the plugin, then build. |
| `./build.sh --restart` | Build, restart Vesktop, reload Discord and verify the plugin start log. |
| `./build.sh --test --restart` | Everything. Use this before asking for a manual test. |
| `./build.sh --verify` | No build; restart Vesktop and verify only. |

`INSTABOX_BOX` overrides the box name (default `instabox-sirmonteiro`).

## 4. How the restart/verify helper works

1. Kills Vesktop by process name (`vesktop.bin`, `vesktop`) so the helper's own
   shell is never matched by `pkill -f`.
2. Waits for the process and port `9222` to be released.
3. Launches:

   ```bash
   DISPLAY=:1 nohup /data/home/Desktop/vesktop \
       --enable-devtools --remote-debugging-port=9222 \
       > /tmp/vesktop-console.log 2>&1 &
   ```

4. Connects to the Chrome DevTools Protocol endpoint, reloads the Discord page
   and listens for `Runtime.consoleAPICalled`.
5. Evaluates:

   ```js
   window.Vencord.Plugins.plugins.BroadcastBoxScreenShare
   window.Vencord.PlainSettings.plugins.BroadcastBoxScreenShare
   ```

6. Succeeds only when a `WhipRelay ... Plugin started` log is observed.

Example success:

```text
[verify] Plugin loaded successfully.
EVAL: {"vencord":"object","pluginLoaded":true,"hasStart":true,"enabled":true,"baseUrl":"https://stream.gabrielsouza.top"}
PLUGIN_START_LOG: true
```

## 5. Manual test checklist

Before handing the box to the user:

```bash
cd /home/gabriel/clones/Vencord
./build.sh --test --restart
```

Then confirm from the host:

```bash
curl -s https://stream.gabrielsouza.top/api/status | jq
```

When the user starts a screen share, the plugin logs:

```text
[WHIP] Initializing publish session for token "<userId>-scrn"
[WHIP] Track settings: <width>x<height> @ <fps>
Applied sender quality target <height>p @ <fps>fps (capture ...)
[WHIP] Configured codec order (media-capabilities, vp9Hardware=false): video/VP9, video/VP8, video/H264, video/AV1, ...
[WHIP] PeerConnection connectionState: connected
```

`/api/status?key=<userId>-scrn` should show the active stream.

For viewer testing, the user should watch the tile on a second account or a
second client. The plugin logs:

```text
[WHEP] [<userId>-scrn] Video track ready (id: ..., state: live)
```

## 6. Reading logs without the helper

Inside the VM:

```bash
tail -f /tmp/vesktop-console.log
```

Or open DevTools (the helper launches with `--enable-devtools`) and filter the
console for `WhipRelay`.

The CDP endpoint is only bound to `127.0.0.1` inside the VM. Use
`instabox exec` (as the helper does) or `instabox port-forward` if you need it
from the host.

## 7. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `Could not resolve "@webpack/common"` | The plugin was symlinked into `src/userplugins`. Use `build.sh` (copy). |
| `pnpm` store lock / permission denied | Fix the pnpm store permissions or pass `--store-dir`. |
| `bind() failed: Address already in use` on port 9222 | The previous Vesktop had not exited. The helper waits for the process and port; if it still happens, kill `vesktop.bin` manually and re-run `--verify`. |
| Plugin not in the Vencord plugin list | Check `~/.config/vesktop/settings/settings.json` → `plugins.BroadcastBoxScreenShare.enabled === true`. |
| WHIP POST blocked | `native.ts` CSP host does not match `baseUrl`; update `BROADCAST_BOX_HOST` and restart. |
| Screen share starts but `/api/status` is empty | Check the WHIP logs for a non-2xx response, ICE failure, or a stale session `DELETE`. |
| Viewer tile is black | The PiP/UI interception issue documented in [plugin-flow.md](./plugin-flow.md#5-ui-interception-and-the-pip-limitation). Deferred until the initial compile is approved. |

## 8. Code conventions

- TypeScript strict mode; avoid `any` where a small interface is practical.
- Keep modules single-purpose. Protocol code must not import Discord stores.
- Comments explain *why* a non-obvious decision exists, not *what* the next line
  does.
- Use the Vencord header with the copyright line; `eslint` enforces it.
- Never commit the `vencord` symlink or the clone (`.gitignore` contains
  `vencord`).
- Commit with `git commit --no-gpg-sign` (the local git config signs by default).