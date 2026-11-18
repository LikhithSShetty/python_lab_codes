<#
.SYNOPSIS
    One-Line Installer for QueLes Print Station Agent
.DESCRIPTION
    Downloads the latest signed release directly from GitHub, strips Mark-of-the-Web,
    installs silently into %LOCALAPPDATA% without UAC elevation, and starts the agent.
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "       QueLes Print Station Agent - Quick Installer       " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$repoOwner = "LikhithSShetty"
$repoName = "python_lab_codes"
$manifestUrl = "https://github.com/$repoOwner/$repoName/releases/latest/download/latest.json"

# 1. Fetch Latest Manifest
Write-Host "[1/4] Checking latest release from GitHub..." -ForegroundColor Yellow
$downloadUrl = ""
$version = "1.0.0-alpha.1"

try {
    $manifest = Invoke-RestMethod -Uri $manifestUrl -Headers @{ "User-Agent" = "QueLes-Installer" }
    if ($manifest.platforms.'windows-x86_64'.url) {
        $downloadUrl = $manifest.platforms.'windows-x86_64'.url
        $version = $manifest.version
    }
} catch {
    Write-Host "   Falling back to direct release endpoint..." -ForegroundColor Gray
}

if (-not $downloadUrl) {
    $downloadUrl = "https://github.com/$repoOwner/$repoName/releases/download/v1.0.0-alpha.1/queles-agent-rust-alpha-1.0_1.0.0-alpha.1_x64-setup.exe"
}

Write-Host "   Target Version: v$version" -ForegroundColor Green

# 2. Download Setup Binary to Temp
$tempDir = [System.IO.Path]::GetTempPath()
$installerPath = Join-Path $tempDir "queles-agent-setup.exe"

if (Test-Path $installerPath) {
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
}

Write-Host "[2/4] Downloading QueLes Agent installer..." -ForegroundColor Yellow

if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    & curl.exe -s -L -o "$installerPath" "$downloadUrl"
} else {
    Invoke-WebRequest -Uri "$downloadUrl" -OutFile "$installerPath" -UseBasicParsing
}

if (-not (Test-Path $installerPath) -or (Get-Item $installerPath).Length -lt 1000000) {
    Write-Error "Download failed or file is corrupted. Please check your internet connection."
    exit 1
}

# 3. Strip Mark of the Web & Install Silently
Write-Host "[3/4] Installing QueLes Agent (CurrentUser mode)..." -ForegroundColor Yellow
Unblock-File -Path "$installerPath" -ErrorAction SilentlyContinue

# Stop any running agent instance prior to upgrade
Get-Process | Where-Object { $_.ProcessName -like "*queles-agent*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

$proc = Start-Process -FilePath "$installerPath" -ArgumentList "/S" -PassThru -Wait
if ($proc.ExitCode -ne 0) {
    Write-Warning "Installer exited with code: $($proc.ExitCode)"
}

# Clean up temp setup binary
Remove-Item -Path "$installerPath" -Force -ErrorAction SilentlyContinue

# 4. Launch Installed Agent
Write-Host "[4/4] Starting QueLes Agent..." -ForegroundColor Yellow
$installedExe = "$env:LOCALAPPDATA\queles-agent-rust-alpha-1.0\queles-agent-rust-alpha-1-0.exe"

if (Test-Path $installedExe) {
    Start-Process -FilePath $installedExe
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "  ✅ QueLes Print Station Agent installed and started!    " -ForegroundColor Green
    Write-Host "  Ready to receive print orders from your shop dashboard. " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Warning "Installation completed, but executable was not found at expected path: $installedExe"
}
