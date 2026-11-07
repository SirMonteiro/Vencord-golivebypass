# Vencord "GoLiveBypass" installer (Windows).
#
# Installs a prebuilt custom Vencord — the official Vencord plus the
# BroadcastBoxScreenShare userplugin — into Discord and/or Vesktop.
#
# The installed build points its built-in updater at this repository, so it keeps
# itself up to date with no dev tools (no Node, pnpm or git) on the target machine.
#
# Usage:
#   .\install-vencord.ps1 [-Target Discord|Vesktop|Both] [-Uninstall]

[CmdletBinding()]
param(
    [ValidateSet('Discord', 'Vesktop', 'Both')]
    [string]$Target = 'Discord',

    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Configuration — change these two if you forked this repository.
# ---------------------------------------------------------------------------
$RepoOwner = "SirMonteiro"
$RepoName  = "vencord-golivebypass"

$ReleaseTag = "devbuild"
$AssetBase  = "https://github.com/$RepoOwner/$RepoName/releases/download/$ReleaseTag"

# Files consumed by the official Vencord Installer (Discord desktop build).
$DiscordFiles = @('patcher.js', 'preload.js', 'renderer.js', 'renderer.css')
# Files consumed by Vesktop's Vencord loader.
$VesktopFiles = @('vencordDesktopMain.js', 'vencordDesktopPreload.js', 'vencordDesktopRenderer.js', 'vencordDesktopRenderer.css')

$DiscordDataDir = if ($env:VENCORD_DISCORD_DIR) { $env:VENCORD_DISCORD_DIR } else { Join-Path $env:APPDATA 'Vencord' }
$InstallerCache = Join-Path $env:LOCALAPPDATA 'vencord-golivebypass'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Cyan }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }

function Get-VesktopFilesDir {
    if ($env:VENCORD_VESKTOP_DIR) { return $env:VENCORD_VESKTOP_DIR }

    # Electron uses the package name, which is lowercase, but be tolerant of an
    # existing install that used a different casing.
    foreach ($name in @('vesktop', 'Vesktop')) {
        $candidate = Join-Path $env:APPDATA $name
        if (Test-Path $candidate) {
            return Join-Path $candidate 'sessionData\vencordFiles'
        }
    }
    return Join-Path $env:APPDATA 'vesktop\sessionData\vencordFiles'
}

function Get-DiscordInstaller {
    if ($env:VENCORD_INSTALLER -and (Test-Path $env:VENCORD_INSTALLER)) {
        return $env:VENCORD_INSTALLER
    }

    $exe = Join-Path $InstallerCache 'VencordInstallerCli.exe'
    if (-not (Test-Path $exe)) {
        New-Item -ItemType Directory -Force -Path $InstallerCache | Out-Null
        $url = 'https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe'
        Write-Step "Downloading the official Vencord Installer CLI"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $exe
    }
    return $exe
}

function Get-Assets {
    param(
        [string]$DestDir,
        [string[]]$Files
    )

    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    foreach ($file in $Files) {
        Write-Step "Downloading $file"
        $path = Join-Path $DestDir $file
        if (Test-Path $path) {
            $item = Get-Item -Force $path
            if ($item.IsReadOnly) { $item.IsReadOnly = $false }
        }
        $url = "$AssetBase/$file"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $path
    }

    # Prevents Node from walking up the tree and picking up an unrelated package.json.
    Set-Content -Path (Join-Path $DestDir 'package.json') -Value '{}' -NoNewline -Encoding ascii
}

function Install-Discord {
    $dist = Join-Path $DiscordDataDir 'dist'
    Write-Step "Staging the Discord build in $dist"
    Get-Assets -DestDir $dist -Files $DiscordFiles

    $installer = Get-DiscordInstaller

    Write-Step "Patching Discord (the installer closes it automatically)"
    # VENCORD_DEV_INSTALL stops the installer from fetching / overwriting with the
    # official Vencord files; VENCORD_USER_DATA_DIR makes the install dir explicit.
    $env:VENCORD_USER_DATA_DIR = $DiscordDataDir
    $env:VENCORD_DEV_INSTALL = '1'
    & $installer -install -branch auto
    if ($LASTEXITCODE -ne 0) { throw "Vencord installation into Discord failed (exit code $LASTEXITCODE)." }

    Write-Step "Discord done. Start Discord - updates are automatic from now on."
}

function Install-Vesktop {
    $dir = Get-VesktopFilesDir
    Write-Step "Staging the Vesktop build in $dir"
    Get-Assets -DestDir $dir -Files $VesktopFiles

    Write-Step "Vesktop done. Fully restart Vesktop to load the custom build."
    Write-Warn "Do not use Vesktop's 'Repair Vencord' / 'Force Update Vencord' menu items:"
    Write-Warn "they download the official Vencord. Vencord's own updater (Settings -> Vencord -> Updater)"
    Write-Warn "updates from this repository instead."
}

function Uninstall-Discord {
    $installer = Get-DiscordInstaller
    Write-Step "Unpatching Discord"
    & $installer -uninstall -branch auto
    if (Test-Path $DiscordDataDir) {
        Write-Step "Removing $DiscordDataDir"
        Remove-Item -Recurse -Force $DiscordDataDir
    }
    Write-Step "Discord uninstalled."
}

function Uninstall-Vesktop {
    $dir = Get-VesktopFilesDir
    if (Test-Path $dir) {
        Write-Step "Removing $dir"
        Remove-Item -Recurse -Force $dir
    }
    Write-Step "Vesktop uninstalled. Restart Vesktop to let it download the official Vencord again."
}

if (-not (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue)) {
    throw "PowerShell is missing Invoke-WebRequest; run this script with Windows PowerShell 5.1 or newer."
}

if ($Uninstall) {
    switch ($Target) {
        'Discord' { Uninstall-Discord }
        'Vesktop' { Uninstall-Vesktop }
        'Both'    { Uninstall-Discord; Uninstall-Vesktop }
    }
    exit 0
}

switch ($Target) {
    'Discord' { Install-Discord }
    'Vesktop' { Install-Vesktop }
    'Both'    { Install-Discord; Install-Vesktop }
}

Write-Step "All done."
