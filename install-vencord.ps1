# Vencord Installer CLI setup script
# Run this script from the directory you want to use as VENCORD_USER_DATA_DIR.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RepoOwner = "SirMonteiro"
$RepoName  = "vencord-golivebypass"

$workDir       = (Get-Location).Path
$distDir       = Join-Path -Path $workDir -ChildPath 'dist'
$installerPath = Join-Path -Path $workDir -ChildPath 'VencordInstallerCli.exe'

$apiUrl       = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/tags/devbuild"
$installerUrl = 'https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1. Fetch asset metadata from GitHub API
Write-Host "Querying release assets for $RepoOwner/$RepoName (devbuild)..." -ForegroundColor Cyan
$headers = @{ "User-Agent" = "Vencord-Installer" }
$release = Invoke-RestMethod -Uri $apiUrl -Headers $headers

if (-not $release.assets -or $release.assets.Count -eq 0) {
    throw "No assets found in the devbuild release for $RepoOwner/$RepoName."
}

# 2. Recreate local dist directory
if (Test-Path $distDir) {
    Remove-Item -Path $distDir -Recurse -Force
}
New-Item -ItemType Directory -Path $distDir | Out-Null

# 3. Download all loose distribution assets directly into dist/
$total = $release.assets.Count
Write-Host "Downloading $total build assets to $distDir..." -ForegroundColor Cyan

$count = 0
foreach ($asset in $release.assets) {
    $count++
    $fileName = $asset.name
    $destPath = Join-Path -Path $distDir -ChildPath $fileName

    Write-Host "[$count/$total] Downloading $fileName"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $destPath
}

# 4. Download official installer CLI
Write-Host "`nDownloading VencordInstallerCli.exe..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
Unblock-File -Path $installerPath -ErrorAction SilentlyContinue
Write-Host "Downloaded to $installerPath"

# 5. Run install pointing to the local dist folder
Write-Host "Running: VencordInstallerCli.exe -install with VENCORD_USER_DATA_DIR=$workDir and VENCORD_DEV_INSTALL=1" -ForegroundColor Cyan
$env:VENCORD_USER_DATA_DIR = $workDir
$env:VENCORD_DEV_INSTALL = '1'
try {
    & $installerPath '-install'
    if ($LASTEXITCODE -ne 0) {
        throw "Vencord installation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Remove-Item Env:\VENCORD_USER_DATA_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:\VENCORD_DEV_INSTALL -ErrorAction SilentlyContinue
}

# 6. Install OpenAsar
Write-Host "Running: VencordInstallerCli.exe -install-openasar" -ForegroundColor Cyan
& $installerPath '-install-openasar'
if ($LASTEXITCODE -ne 0) {
    Write-Host "OpenAsar installation failed with exit code $LASTEXITCODE"
}

Write-Host "`nVencord installation completed successfully." -ForegroundColor Green
