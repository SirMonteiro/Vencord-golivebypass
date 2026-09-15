#!/usr/bin/env bash
set -euo pipefail

# Configuration
REPO_OWNER="SirMonteiro"
REPO_NAME="vencord-golivebypass"
RELEASE_TAG="devbuild"

WORK_DIR="/tmp/vencord"
DIST_DIR="${WORK_DIR}/dist"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${RELEASE_TAG}"

# 1. Verify required tools
for cmd in VencordInstaller curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[-] Error: Required command '$cmd' is not installed or not in PATH." >&2
        exit 1
    fi
done

# 2. Prepare directories
echo "[+] Preparing directory: ${DIST_DIR}"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# 3. Fetch asset download URLs from GitHub API
echo "[+] Fetching release asset list from ${REPO_OWNER}/${REPO_NAME} (${RELEASE_TAG})..."
RESPONSE=$(curl -fsSL -H "User-Agent: Vencord-Linux-Installer" "${API_URL}")

ASSET_COUNT=$(echo "${RESPONSE}" | jq '.assets | length')
if [ -z "${ASSET_COUNT}" ] || [ "${ASSET_COUNT}" -eq 0 ]; then
    echo "[-] Error: No assets found in the release." >&2
    exit 1
fi

echo "[+] Downloading ${ASSET_COUNT} files to ${DIST_DIR}..."

# 4. Download all assets directly into dist/
INDEX=1
while IFS=$'\t' read -r name url; do
    printf "[%2d/%2d] Downloading %s\n" "$INDEX" "$ASSET_COUNT" "$name"
    curl -fsSL "$url" -o "${DIST_DIR}/${name}"
    INDEX=$((INDEX + 1))
done < <(echo "${RESPONSE}" | jq -r '.assets[] | [.name, .browser_download_url] | @tsv')

# 5. Run VencordInstaller pointing to the directory containing dist/
echo "[+] Injecting Vencord into Discord..."
export VENCORD_USER_DATA_DIR="${WORK_DIR}"
export VENCORD_DEV_INSTALL="1"

if ! VencordInstaller -install; then
    echo "[-] Vencord installation failed." >&2
    exit 1
fi

# 6. Optional OpenAsar installation
echo "[+] Installing OpenAsar..."
VencordInstaller -install-openasar || echo "[!] OpenAsar installation step skipped or failed."

# Clean up environment variables
unset VENCORD_USER_DATA_DIR
unset VENCORD_DEV_INSTALL

echo -e "\n[+] Vencord installation completed successfully. Restart Discord to apply changes."
