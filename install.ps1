<#
.SYNOPSIS
    QueLes Print Station Agent - Production Installer
.DESCRIPTION
    Fetches the latest release manifest and checksum file from GitHub,
    downloads the installer, verifies its SHA256 hash before removing
    Mark-of-the-Web, then installs silently to %LOCALAPPDATA% and launches.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ProgressPreference    = "Continue"

$RepoOwner   = "LikhithSShetty"
$RepoName    = "python_lab_codes"
$ProcessName = "queles-agent-rust-alpha-1-0"
$TotalSteps  = 6

# --------------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------------

function Write-Banner([string]$Text) {
    $line = "=" * 60
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step([int]$Number, [string]$Text) {
    Write-Host "[$Number/$TotalSteps] $Text" -ForegroundColor Yellow
}

function Write-Ok([string]$Text)   { Write-Host "    OK    $Text" -ForegroundColor Green }
function Write-ErrLine([string]$Text) { Write-Host "    ERROR $Text" -ForegroundColor Red }

function Exit-WithError([string]$Message) {
    Write-Host ""
    Write-ErrLine $Message
    Write-Host ""
    exit 1
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 2
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $Action
        } catch {
            if ($attempt -eq $MaxAttempts) { throw }
            Write-Host "    retrying ($attempt/$MaxAttempts)..." -ForegroundColor DarkYellow
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Get-WebTextUtf8([string]$Uri) {
    $res = Invoke-WebRequest -Uri $Uri -UseBasicParsing -Headers @{ "User-Agent" = "QueLes-Installer" }
    $bytes = $res.Content
    if ($bytes -is [byte[]]) {
        return [System.Text.Encoding]::UTF8.GetString($bytes).Trim().TrimStart([char]0xFEFF)
    }
    return $res.Content.Trim().TrimStart([char]0xFEFF)
}

function Invoke-FileDownload([string]$Url, [string]$OutFile) {
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -f -L --progress-bar -o "$OutFile" "$Url"
        if ($LASTEXITCODE -ne 0) {
            throw "curl exited with code $LASTEXITCODE"
        }
    } else {
        Invoke-WebRequest -Uri "$Url" -OutFile $OutFile -UseBasicParsing
    }
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

Write-Banner "QueLes Print Station Agent - Installer"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$installerPath = $null

try {
    # 1. Manifest
    Write-Step 1 "Fetching latest release manifest"
    try {
        $manifestJson = Invoke-WithRetry { Get-WebTextUtf8 -Uri "https://github.com/$RepoOwner/$RepoName/releases/latest/download/latest.json" }
        $manifest    = $manifestJson | ConvertFrom-Json
        $version     = $manifest.version
        $downloadUrl = $manifest.platforms.'windows-x86_64'.url
        if (-not $downloadUrl) { throw "Manifest missing windows-x86_64 download URL" }
    } catch {
        Exit-WithError "Could not retrieve release manifest. $_"
    }
    Write-Ok "Target version v$version"

    # 2. Checksums
    Write-Step 2 "Fetching release checksums"
    $fileName = Split-Path -Leaf $downloadUrl
    $expectedHash = $null
    try {
        $checksumsText = Invoke-WithRetry { Get-WebTextUtf8 -Uri "https://github.com/$RepoOwner/$RepoName/releases/download/v$version/SHA256SUMS.txt" }
        foreach ($line in ($checksumsText -split "`r?`n")) {
            if ($line -match "^([A-Fa-f0-9]{64})\s+\*?(.+)$" -and $Matches[2].Trim() -eq $fileName) {
                $expectedHash = $Matches[1].ToUpper()
                break
            }
        }
    } catch {
        Exit-WithError "Could not fetch SHA256SUMS.txt. $_"
    }
    if (-not $expectedHash) {
        Exit-WithError "No checksum entry found for '$fileName'."
    }
    Write-Ok "Checksum entry located"

    # 3. Download
    Write-Step 3 "Downloading $fileName"
    $installerPath = Join-Path ([System.IO.Path]::GetTempPath()) $fileName
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    try {
        Invoke-WithRetry { Invoke-FileDownload -Url $downloadUrl -OutFile $installerPath }
    } catch {
        Exit-WithError "Download failed. $_"
    }
    if (-not (Test-Path $installerPath)) {
        Exit-WithError "Installer file missing after download."
    }
    Write-Ok "Download complete"

    # 4. Hash verification
    Write-Step 4 "Verifying file integrity"
    $actualHash = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToUpper()
    if ($actualHash -ne $expectedHash) {
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
        Write-ErrLine "Checksum mismatch - file may be corrupted or tampered with."
        Write-Host "    expected: $expectedHash" -ForegroundColor DarkRed
        Write-Host "    actual:   $actualHash" -ForegroundColor DarkRed
        Exit-WithError "Aborting installation."
    }
    Write-Ok "SHA256 verified"

    # Only now is it safe to drop the download-source marker
    Unblock-File -Path $installerPath -ErrorAction SilentlyContinue

    # 5. Install
    Write-Step 5 "Installing QueLes Agent"
    Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500

    $proc = Start-Process -FilePath $installerPath -ArgumentList "/S" -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        Write-ErrLine "Installer exited with code $($proc.ExitCode)"
    } else {
        Write-Ok "Installer finished"
    }

    # 6. Launch
    Write-Step 6 "Starting agent"
    $installedExe = Join-Path $env:LOCALAPPDATA "queles-agent-rust-alpha-1.0\queles-agent-rust-alpha-1-0.exe"
    if (Test-Path $installedExe) {
        Start-Process -FilePath $installedExe
        Write-Ok "Agent started"
        Write-Banner "Install complete - ready for print orders"
    } else {
        Exit-WithError "Installed executable not found at: $installedExe"
    }

} finally {
    if ($installerPath -and (Test-Path $installerPath)) {
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    }
}
