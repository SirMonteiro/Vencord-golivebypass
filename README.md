# Vencord GoLiveBypass

A prebuilt, self-updating **Vencord** build for **Discord** and **Vesktop** that
ships the [`BroadcastBoxScreenShare`](./BroadcastBoxScreenShare) userplugin.

You do **not** need Node, pnpm, git or any other dev tool on the machine you
install it on. The build updates itself from this repository's releases.

- Plugin documentation: [`docs/`](./docs/README.md)
- CI definition: [`.github/workflows/build.yml`](./.github/workflows/build.yml)
- Installers: [`install-vencord.sh`](./install-vencord.sh) (Linux) and
  [`install-vencord.ps1`](./install-vencord.ps1) / [`install-vencord.bat`](./install-vencord.bat) (Windows)

---

## How it works

1. **CI builds a fresh Vencord** every 6 hours (and on manual dispatch). It checks
   out the latest official Vencord, injects the userplugins from this repository
   (`custom/*/`), and builds the standalone desktop bundles.
2. **The build points at this repo.** CI compiles Vencord with
   `VENCORD_REMOTE=<this repo>` and patches the standalone updater so it checks
   *this* repository's releases instead of the official Vencord one.
   The patch is needed because the official updater also calls the GitHub
   "compare" API, which 404s for a fork that only publishes builds.
3. **One release per build.** CI publishes the tag `devbuild` with the title
   `DevBuild <hash>`, where
   `<hash> = sha1(upstream Vencord commit + this repo commit)[:7]`.
   Because the hash also changes when this repo (plugins, workflow) changes,
   plugin-only updates are picked up too.
4. **Installed clients auto-update.** Vencord's updater reads
   `https://api.github.com/repos/<owner>/<repo>/releases/latest`, sees that the
   release hash differs from the hash baked into the local build, and downloads
   the new files into its install folder. Auto-update is on by default
   (`Settings -> Vencord -> Updater`); a restart (or the update notification's
   "Click here to restart") activates the downloaded build. No action is needed
   for the check/download itself.

Only the release files are consumed by clients; no toolchain is needed there.

---

## Requirements

| Platform | Needs |
| --- | --- |
| Linux (tested) | `curl`, `bash` |
| Windows (tested) | Windows PowerShell 5.1+ (built in) |
| App | Discord desktop and/or Vesktop already installed |

Discord installs are patched with the **official** [Vencord Installer](https://github.com/Vencord/Installer),
which the script downloads automatically on first use.

---

## Install

### Linux

Install into **Discord** (default):

```bash
curl -fsSL https://raw.githubusercontent.com/SirMonteiro/Vencord-golivebypass/main/install-vencord.sh | bash -s -- --discord
```

Install into **Vesktop**:

```bash
curl -fsSL https://raw.githubusercontent.com/SirMonteiro/Vencord-golivebypass/main/install-vencord.sh | bash -s -- --vesktop
```

Install into **both**:

```bash
curl -fsSL https://raw.githubusercontent.com/SirMonteiro/Vencord-golivebypass/main/install-vencord.sh | bash -s -- --both
```

Or download the script and run it directly:

```bash
bash install-vencord.sh --vesktop
```

### Windows

Download and run the script (PowerShell):

```powershell
iwr https://raw.githubusercontent.com/SirMonteiro/Vencord-golivebypass/main/install-vencord.ps1 -OutFile install-vencord.ps1
powershell -ExecutionPolicy Bypass -File .\install-vencord.ps1 -Target Vesktop
```

Or, after downloading the repository, double-click / run:

```bat
install-vencord.bat -Target Vesktop
```

`-Target` accepts `Discord`, `Vesktop` or `Both` (default `Discord`).

### After installing

- **Discord:** the installer closes and patches Discord. Start it again.
  Vencord files live in `~/.config/Vencord/dist` (Linux) /
  `%APPDATA%\Vencord\dist` (Windows).
- **Vesktop:** fully quit and reopen Vesktop. Vencord files are written to
  Vesktop's own Vencord folder (`~/.config/vesktop/sessionData/vencordFiles`,
  `%APPDATA%\vesktop\sessionData\vencordFiles`, or the equivalent Flatpak path).

**Verify it:** open **Settings -> Vencord -> Updater**. The repository link must
point at `https://github.com/SirMonteiro/Vencord-golivebypass`, and the installed
hash must match the release title (`DevBuild <hash>`).

> **Vesktop users:** do **not** use Vesktop's *Repair Vencord* or *Force Update
> Vencord* menu items — those download the official Vencord. Use Vencord's own
> **Settings -> Vencord -> Updater** tab instead, or just let the automatic
> startup update run.

---

## Updating

Updates are automatic:

- CI rebuilds within 6 hours of an upstream Vencord change or a change in this repo.
- On start-up, the installed Vencord checks this repo's latest release and downloads
  the new files when the hash differs. Restart the app (or click the update
  notification) to load them.

To update manually: **Settings -> Vencord -> Updater -> Check for updates**, or
re-run the installer script (it simply re-downloads and re-stages the latest build).

To force CI to build right now: **Actions -> Build DevBuild -> Run workflow**.
Releases are recreated each time, so `/releases/latest` always points at the newest build.

---

## Maintaining your own fork

1. Fork or copy this repository.
2. Change `REPO_OWNER` / `REPO_NAME` in **both** `install-vencord.sh` and
   `install-vencord.ps1` to your own values.
3. Nothing else is required for the build: CI uses `${{ github.repository }}` as
   `VENCORD_REMOTE`, so the built Vencord automatically targets your repo.
4. Add or edit plugins under a top-level folder (e.g. `MyPlugin/`). CI injects
   every top-level folder that contains `.ts`/`.tsx` files into Vencord's
   `src/userplugins`. The build hash changes automatically, so clients update.
5. Push to the default branch, or trigger the workflow manually. The `devbuild`
   release is created/updated for you.

### Verifying a build

```bash
curl -fsSL https://api.github.com/repos/SirMonteiro/Vencord-golivebypass/releases/latest \
  | grep -E '"tag_name"|"name"'
```

The release title must end with the same short hash shown next to the repo in
**Settings -> Vencord -> Updater**.

---

## Troubleshooting

**"Failed to check updates" / "That also failed :(" inside Vencord**
The upstream updater calls GitHub's `compare` API, which returns 404 for a
build-only fork and aborts the check. This repository patches that call in CI
(`.github/workflows/build.yml` -> `.github/scripts/patch-updater.mjs`). If you see
this, the release was likely built before the patch existed: trigger a new build
(Actions -> Build DevBuild -> Run workflow) and reinstall.

**Permission denied while updating (Linux)**
The updater rewrites the Vencord files in place; it fails if they are owned by
root. This happens when the installer was run with `sudo`, or when Vesktop's
Vencord folder was extracted as root. Fix ownership once and reinstall:

```bash
# Discord
sudo chown -R "$USER" "$HOME/.config/Vencord"
# Vesktop
sudo chown -R "$USER" "$HOME/.config/vesktop/sessionData/vencordFiles"
```

Never run the installer with `sudo`. For Flatpak Vesktop the folder is
`~/.var/app/dev.vencord.Vesktop/config/vesktop/sessionData/vencordFiles`.

**Update says it installed but the version is unchanged**
Restart the app. For Vesktop, make sure the whole app (including the tray) is
closed and reopened. Also make sure you did not run Vesktop's *Repair Vencord*.

**Discord not detected**
Snap builds of Discord are not supported by the Vencord Installer. Install the
official `.deb`/`.rpm`/Flatpak build instead.

**Vesktop's "Vencord location" shows the official build**
If you previously used a custom Vencord folder in Vesktop, set it back to the
default, or point it at the folder this script installs into.

---

## Uninstall

Linux:

```bash
bash install-vencord.sh --uninstall --discord
bash install-vencord.sh --uninstall --vesktop
```

Windows:

```powershell
.\install-vencord.ps1 -Target Discord -Uninstall
.\install-vencord.ps1 -Target Vesktop -Uninstall
```

Removing the Vesktop folder makes Vesktop download the official Vencord again on
the next start.

---

## Security note

Automatic updates execute code from the releases of this repository. Only run
this on machines that trust the owner of the repository you configured, and keep
write access to that repository protected — anyone who can publish a release can
push code to every install.
