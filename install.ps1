<#
.SYNOPSIS
    Hardened One-Line Production Installer for QueLes Print Station Agent
.DESCRIPTION
    1. Enforces TLS 1.2+
    2. Fetches latest.json & SHA256SUMS.txt from GitHub
    3. Downloads the release binary with strict failure flags
    4. Verifies SHA256 checksum cryptographically before touching the file
    5. Strips Mark-of-the-Web ONLY after hash is verified
    6. Stops only the exact queles process
    7. Installs silently in currentUser mode (%LOCALAPPDATA%) and launches
#>

$ErrorActionPreference = "Stop"

# 1. Enforce Modern TLS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "       QueLes Print Station Agent - Secure Installer      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$repoOwner = "LikhithSShetty"
$repoName = "python_lab_codes"
$manifestUrl = "https://github.com/$repoOwner/$repoName/releases/latest/download/latest.json"

# 2. Fetch Latest Manifest — Fail loudly on error
Write-Host "[1/5] Fetching latest release manifest from GitHub..." -ForegroundColor Yellow
try {
    $manifest = Invoke-RestMethod -Uri $manifestUrl -Headers @{ "User-Agent" = "QueLes-Installer" }
    $version = $manifest.version
    $downloadUrl = $manifest.platforms.'windows-x86_64'.url
    if (-not $downloadUrl) {
        throw "Manifest does not contain a download URL for windows-x86_64."
    }
} catch {
    Write-Host ""
    Write-Host "❌ Error: Could not retrieve release manifest from GitHub." -ForegroundColor Red
    Write-Host "   Details: $_" -ForegroundColor DarkRed
    Write-Host "   Please verify internet connectivity or check the repository." -ForegroundColor Red
    exit 1
}

Write-Host "   Target Version: v$version" -ForegroundColor Green

# 3. Fetch SHA256 Checksums
Write-Host "[2/5] Fetching release checksums..." -ForegroundColor Yellow
$checksumsUrl = "https://github.com/$repoOwner/$repoName/releases/download/v$version/SHA256SUMS.txt"
$expectedHash = $null
try {
    $checksumsText = Invoke-RestMethod -Uri $checksumsUrl -Headers @{ "User-Agent" = "QueLes-Installer" }
    $fileName = Split-Path -Leaf $downloadUrl
    foreach ($line in ($checksumsText -split "`r?`n")) {
        if ($line -match "^([A-Fa-f0-9]{64})\s+(.+)$") {
            if ($Matches[2].Trim() -eq $fileName) {
                $expectedHash = $Matches[1].ToUpper()
                break
            }
        }
    }
} catch {
    Write-Host "❌ Error: Could not fetch SHA256SUMS.txt. Aborting installation for security." -ForegroundColor Red
    exit 1
}

if (-not $expectedHash) {
    Write-Host "❌ Error: Checksum for '$fileName' not found in release manifest." -ForegroundColor Red
    exit 1
}

# 4. Download Binary with Strict Failures
$tempDir = [System.IO.Path]::GetTempPath()
$installerPath = Join-Path $tempDir $fileName

if (Test-Path $installerPath) {
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
}

Write-Host "[3/5] Downloading installer package ($fileName)..." -ForegroundColor Yellow
if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    # -f fails on HTTP 4xx/5xx errors, -S shows errors, -L follows redirects
    & curl.exe -f -s -S -L -o "$installerPath" "$downloadUrl"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Error: curl download failed with exit code $LASTEXITCODE." -ForegroundColor Red
        exit 1
    }
} else {
    Invoke-WebRequest -Uri "$downloadUrl" -OutFile "$installerPath" -UseBasicParsing
}

# 5. Cryptographic Hash Verification
Write-Host "[4/5] Verifying SHA256 integrity..." -ForegroundColor Yellow
$actualHash = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToUpper()

if ($actualHash -ne $expectedHash) {
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    Write-Host "❌ FATAL: Checksum mismatch! The downloaded binary has been tampered with or corrupted." -ForegroundColor Red
    Write-Host "   Expected: $expectedHash" -ForegroundColor Red
    Write-Host "   Actual:   $actualHash" -ForegroundColor Red
    exit 1
}
Write-Host "   SHA256 Verified: Match confirmed." -ForegroundColor Green

# 6. Unblock ONLY After Hash Verification
Unblock-File -Path "$installerPath" -ErrorAction SilentlyContinue

# 7. Stop only exact process name
Get-Process -Name "queles-agent-rust-alpha-1-0" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# 8. Silent Install
Write-Host "[5/5] Installing QueLes Agent..." -ForegroundColor Yellow
$proc = Start-Process -FilePath "$installerPath" -ArgumentList "/S" -PassThru -Wait
if ($proc.ExitCode -ne 0) {
    Write-Warning "Installer exited with code: $($proc.ExitCode)"
}

Remove-Item -Path "$installerPath" -Force -ErrorAction SilentlyContinue

# 9. Launch Installed Agent
$installedExe = "$env:LOCALAPPDATA\queles-agent-rust-alpha-1.0\queles-agent-rust-alpha-1-0.exe"
if (Test-Path $installedExe) {
    Start-Process -FilePath $installedExe
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "  ✅ QueLes Agent verified, installed, and started!       " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "❌ Installation failed: Executable not found at $installedExe" -ForegroundColor Red
}
