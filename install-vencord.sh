#!/usr/bin/env bash
#
# Vencord "GoLiveBypass" installer (Linux; macOS is best-effort and untested).
#
# Installs a prebuilt custom Vencord — the official Vencord plus the
# BroadcastBoxScreenShare userplugin — into Discord and/or Vesktop.
#
# The installed build points its built-in updater at this repository, so it keeps
# itself up to date with no dev tools (no Node, pnpm or git) on the target machine.
#
# Usage:
#   ./install-vencord.sh [--discord|--vesktop|--both] [--uninstall]
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — change these two if you forked this repository.
# ---------------------------------------------------------------------------
REPO_OWNER="SirMonteiro"
REPO_NAME="vencord-golivebypass"

RELEASE_TAG="devbuild"
ASSET_BASE="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${RELEASE_TAG}"

# Files consumed by the official Vencord Installer (Discord desktop build).
DISCORD_FILES=(patcher.js preload.js renderer.js renderer.css)
# Files consumed by Vesktop's Vencord loader.
VESKTOP_FILES=(vencordDesktopMain.js vencordDesktopPreload.js vencordDesktopRenderer.js vencordDesktopRenderer.css)

# Overridable locations.
DISCORD_DATA_DIR="${VENCORD_DISCORD_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/Vencord}"
INSTALLER_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/vencord-golivebypass"

TARGET="discord"
UNINSTALL="false"

usage() {
    cat <<EOF
Vencord GoLiveBypass installer

Usage: $0 [options]

Options:
  --discord      Install into the Discord desktop app (default)
  --vesktop      Install into Vesktop's Vencord folder
  --both         Install into both Discord and Vesktop
  --uninstall    Remove the install for the selected target
  -h, --help     Show this help

Environment overrides:
  VENCORD_DISCORD_DIR   Where the Discord build is staged (default: ~/.config/Vencord)
  VENCORD_VESKTOP_DIR   Where the Vesktop build is staged (default: auto-detected)
  VESKTOP_CONFIG_DIR    Vesktop's config dir (default: auto-detected)
  VENCORD_INSTALLER     Path to an existing VencordInstallerCli binary
EOF
}

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[-] %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
download_assets() {
    # download_assets <dest-dir> <file...>
    local dest="$1"; shift
    if [ -d "$dest" ] && [ ! -w "$dest" ]; then
        die "$dest is not writable. If it was created by root, fix it once with: sudo chown -R \"\$USER\" \"$dest\""
    fi
    mkdir -p "$dest"
    for file in "$@"; do
        local target="${dest}/${file}"
        if [ -e "$target" ] && [ ! -w "$target" ]; then
            chmod u+w "$target" 2>/dev/null || die "$target is not writable. Fix ownership with: sudo chown -R \"\$USER\" \"$dest\""
        fi
        log "Downloading $file"
        curl -fsSL --retry 3 "${ASSET_BASE}/${file}" -o "$target"
    done
    # Prevents Node from walking up the tree and picking up an unrelated package.json.
    printf '{}' > "${dest}/package.json"
}

ensure_discord_installer() {
    if [ -n "${VENCORD_INSTALLER:-}" ]; then
        [ -x "$VENCORD_INSTALLER" ] || die "VENCORD_INSTALLER is not executable: $VENCORD_INSTALLER"
        printf '%s' "$VENCORD_INSTALLER"
        return
    fi
    if command -v VencordInstallerCli >/dev/null 2>&1; then
        command -v VencordInstallerCli
        return
    fi
    if command -v VencordInstaller >/dev/null 2>&1; then
        command -v VencordInstaller
        return
    fi

    local bin="${INSTALLER_CACHE}/VencordInstallerCli"
    if [ ! -x "$bin" ]; then
        case "$(uname -s)" in
            Linux)   local asset="VencordInstallerCli-linux" ;;
            Darwin)  local asset="VencordInstallerCli-darwin" ;;
            *)       die "Unsupported platform: $(uname -s). Download the Vencord Installer manually and set VENCORD_INSTALLER." ;;
        esac
        mkdir -p "$INSTALLER_CACHE"
        printf '[+] Downloading the official Vencord Installer CLI\n' >&2
        curl -fsSL --retry 3 "https://github.com/Vencord/Installer/releases/latest/download/${asset}" -o "$bin"
        chmod +x "$bin"
    fi
    printf '%s' "$bin"
}

vesktop_config_dir() {
    if [ -n "${VESKTOP_CONFIG_DIR:-}" ]; then
        printf '%s' "$VESKTOP_CONFIG_DIR"
        return
    fi
    if [ "$(uname -s)" = "Darwin" ]; then
        printf '%s' "${HOME}/Library/Application Support"
        return
    fi
    # Flatpak Vesktop keeps its config inside its own sandbox.
    if [ -d "${HOME}/.var/app/dev.vencord.Vesktop" ]; then
        printf '%s' "${HOME}/.var/app/dev.vencord.Vesktop/config"
        return
    fi
    printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# ---------------------------------------------------------------------------
# Discord
# ---------------------------------------------------------------------------
install_discord() {
    command -v curl >/dev/null 2>&1 || die "'curl' is required but was not found in PATH."

    local dist="${DISCORD_DATA_DIR}/dist"
    log "Staging the Discord build in ${dist}"
    download_assets "$dist" "${DISCORD_FILES[@]}"

    local installer
    installer="$(ensure_discord_installer)"

    log "Patching Discord (the installer closes it automatically)"
    # VENCORD_DEV_INSTALL stops the installer from fetching / overwriting with the
    # official Vencord files; VENCORD_USER_DATA_DIR makes the install dir explicit.
    VENCORD_USER_DATA_DIR="$DISCORD_DATA_DIR" VENCORD_DEV_INSTALL=1 \
        "$installer" -install -branch auto

    log "Discord done. Start Discord — updates are automatic from now on."
}

uninstall_discord() {
    local installer
    installer="$(ensure_discord_installer)" || die "Could not obtain the Vencord Installer."
    log "Unpatching Discord"
    "$installer" -uninstall -branch auto || warn "Unpatch returned an error; Discord may not have been patched."
    if [ -d "$DISCORD_DATA_DIR" ]; then
        log "Removing ${DISCORD_DATA_DIR}"
        rm -rf "$DISCORD_DATA_DIR"
    fi
    log "Discord uninstalled."
}

# ---------------------------------------------------------------------------
# Vesktop
# ---------------------------------------------------------------------------
install_vesktop() {
    command -v curl >/dev/null 2>&1 || die "'curl' is required but was not found in PATH."

    local dir="${VENCORD_VESKTOP_DIR:-$(vesktop_config_dir)/vesktop/sessionData/vencordFiles}"
    log "Staging the Vesktop build in ${dir}"
    download_assets "$dir" "${VESKTOP_FILES[@]}"

    log "Vesktop done. Fully restart Vesktop to load the custom build."
    warn "Do not use Vesktop's 'Repair Vencord' / 'Force Update Vencord' menu items:"
    warn "they download the official Vencord. Vencord's own updater (Settings -> Vencord -> Updater)"
    warn "updates from this repository instead."
}

uninstall_vesktop() {
    local dir="${VENCORD_VESKTOP_DIR:-$(vesktop_config_dir)/vesktop/sessionData/vencordFiles}"
    if [ -d "$dir" ]; then
        log "Removing ${dir}"
        rm -rf "$dir"
    fi
    log "Vesktop uninstalled. Restart Vesktop to let it download the official Vencord again."
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --discord)   TARGET="discord" ;;
        --vesktop)   TARGET="vesktop" ;;
        --both)      TARGET="both" ;;
        --uninstall) UNINSTALL="true" ;;
        -h|--help)   usage; exit 0 ;;
        *)           warn "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

if [ "$UNINSTALL" = "true" ]; then
    case "$TARGET" in
        discord) uninstall_discord ;;
        vesktop) uninstall_vesktop ;;
        both)    uninstall_discord; uninstall_vesktop ;;
    esac
    exit 0
fi

case "$TARGET" in
    discord) install_discord ;;
    vesktop) install_vesktop ;;
    both)    install_discord; install_vesktop ;;
esac

log "All done."
