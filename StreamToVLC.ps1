param(
    [Parameter(Position = 0, ValueFromPipeline = $true)]
    [string]$RawURL
)

<#
================================================================================
  Script Name   : StreamToVLC.ps1
  Description   : High-Performance YouTube to VLC Asynchronous Stream Pipeline
  Author/Credit : Prof_MAN (pm9.s.gy)
  Capabilities  : Custom URI Protocol (vlcs://), DASH 1080p A/V sync via --input-slave,
                  Hardware-accelerated decoding, anti-stutter buffer tuning.
================================================================================
#>

# Load essential graphical assemblies for native Windows dialogs
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

# ==============================================================================
# SECTION 1: Dependency Verification
# ==============================================================================

# 1.1 Verify yt-dlp in System PATH
if (-not (Get-Command "yt-dlp" -ErrorAction SilentlyContinue)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Critical Dependency Missing: 'yt-dlp' was not found in your system PATH.`n`n" +
        "Please install it using Windows Package Manager in an elevated terminal:`n" +
        "winget install yt-dlp --source winget`n`n" +
        "Or download the binary directly from: https://github.com/yt-dlp/yt-dlp/releases",
        "Dependency Error - yt-dlp Missing",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    Write-Host "[ERROR] 'yt-dlp' executable could not be resolved in system PATH." -ForegroundColor Red
    exit 1
}

# 1.2 Locate and Validate VLC Media Player
$VLC_PATH = "C:\Program Files\VideoLAN\VLC\vlc.exe"

if (-not (Test-Path $VLC_PATH)) {
    # Perform fallback search across alternate standard installation directories
    $fallbackPaths = @(
        "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe",
        "${env:LOCALAPPDATA}\Programs\VLC\vlc.exe"
    )

    $vlcFound = $null
    foreach ($cand in $fallbackPaths) {
        if (Test-Path $cand) {
            $vlcFound = $cand
            break
        }
    }

    if ($vlcFound) {
        $VLC_PATH = $vlcFound
    } else {
        # Check PATH as last resort
        $pathCmd = Get-Command "vlc.exe" -ErrorAction SilentlyContinue
        if ($pathCmd -and (Test-Path $pathCmd.Source)) {
            $VLC_PATH = $pathCmd.Source
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "VLC Media Player was not detected at:`n$VLC_PATH`n`n" +
                "Please verify VLC is installed or edit the `$VLC_PATH variable at the top of this script.`n" +
                "You can install VLC via winget:`nwinget install VideoLAN.VLC --source winget",
                "Dependency Error - VLC Missing",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            Write-Host "[ERROR] VLC Media Player executable not found." -ForegroundColor Red
            exit 1
        }
    }
}

# ==============================================================================
# SECTION 2: Custom URI Protocol Handler Registration (vlcs://)
# ==============================================================================

function Ensure-VlcsProtocolRegistration {
    <#
    .SYNOPSIS
        Detects if vlcs:// protocol is registered in Windows Registry;
        prompts user with native dialog and registers the handler.
    #>
    $hkcrPath = "Registry::HKEY_CLASSES_ROOT\vlcs"
    $hkcuPath = "Registry::HKEY_CURRENT_USER\Software\Classes\vlcs"

    $isRegistered = (Test-Path $hkcrPath) -or (Test-Path $hkcuPath)

    if (-not $isRegistered) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Would you like to register the 'vlcs://' protocol handler?`n`n" +
            "This allows you to open videos directly in VLC from your browser or Tampermonkey user scripts with one click.",
            "Register VLC Stream Protocol",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            # Resolve the absolute canonical path of this executing script
            $thisScript = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Definition }
            if (-not (Test-Path $thisScript)) {
                $thisScript = "C:\StreamToVLC.ps1"
            }

            $commandString = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$thisScript`" `"%1`""

            try {
                # Attempt primary registration in HKCU (effective immediately for user, bypasses UAC restrictions)
                New-Item -Path $hkcuPath -Force | Out-Null
                Set-ItemProperty -Path $hkcuPath -Name "(Default)" -Value "URL:VLC Stream Protocol"
                Set-ItemProperty -Path $hkcuPath -Name "URL Protocol" -Value ""
                
                $iconKey = Join-Path $hkcuPath "DefaultIcon"
                New-Item -Path $iconKey -Force | Out-Null
                Set-ItemProperty -Path $iconKey -Name "(Default)" -Value "$VLC_PATH,0"

                $cmdKey = Join-Path $hkcuPath "shell\open\command"
                New-Item -Path $cmdKey -Force | Out-Null
                Set-ItemProperty -Path $cmdKey -Name "(Default)" -Value $commandString

                # Mirror to HKLM/HKCR if running with elevated permissions
                try {
                    New-Item -Path $hkcrPath -Force -ErrorAction Stop | Out-Null
                    Set-ItemProperty -Path $hkcrPath -Name "(Default)" -Value "URL:VLC Stream Protocol"
                    Set-ItemProperty -Path $hkcrPath -Name "URL Protocol" -Value ""
                    $hkcrCmd = Join-Path $hkcrPath "shell\open\command"
                    New-Item -Path $hkcrCmd -Force | Out-Null
                    Set-ItemProperty -Path $hkcrCmd -Name "(Default)" -Value $commandString
                } catch {
                    # Silently proceed since HKCU registration is active
                }

                [System.Windows.Forms.MessageBox]::Show(
                    "'vlcs://' protocol handler successfully registered!`n`nYou can now launch streams directly from your web browser.",
                    "Protocol Registered",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Access Denied: Could not write protocol handler to the Windows Registry.`n`n" +
                    "To complete setup, please run this script once as Administrator.",
                    "Elevation Required",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
            }
        }
    }
}

Ensure-VlcsProtocolRegistration

# ==============================================================================
# SECTION 3: Dual Input Mode & URL Parameter Sanitization
# ==============================================================================

$targetUrl = ""

if (-not [string]::IsNullOrWhiteSpace($RawURL)) {
    # --- PROTOCOL MODE (Invoked via browser or command line) ---
    $clean = $RawURL.Trim().Trim('"').Trim("'")

    # Strip custom protocol prefixes (vlcs://, vlcs:/, or vlcs:)
    $clean = $clean -replace '^vlcs:/{0,2}', ''

    # Clean URL encoding and trailing whitespace/slashes added by browser handlers
    $clean = [System.Uri]::UnescapeDataString($clean).Trim()

    # Reconstruct pure https protocol if stripped or malformed
    if ($clean -notmatch '^https?://') {
        if ($clean -match '^https?:/') {
            $clean = $clean -replace '^https?:/+', 'https://'
        } else {
            $clean = "https://$clean"
        }
    }

    # Remove trailing slash commonly appended by browsers after query string
    if ($clean -match '\?[^/]+/$') {
        $clean = $clean.TrimEnd('/')
    }

    $targetUrl = $clean
} else {
    # --- MANUAL MODE (Interactive GUI fallback) ---
    $inputPrompt = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Paste YouTube URL or media link below:`n`n(Supports DASH 1080p+, Twitch, Vimeo, etc.)",
        "VLC Advanced Stream Resolver - Prof_MAN",
        ""
    )

    if ([string]::IsNullOrWhiteSpace($inputPrompt)) {
        # User cancelled or provided empty input - exit cleanly
        exit 0
    }

    $targetUrl = $inputPrompt.Trim().Trim('"').Trim("'")
}

# Final sanity check on sanitized URL format
if ($targetUrl -notmatch '^https?://') {
    [System.Windows.Forms.MessageBox]::Show(
        "Invalid URL format specified:`n$targetUrl`n`nPlease ensure the URL begins with http:// or https://",
        "Invalid Input",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit 1
}

# ==============================================================================
# SECTION 4: Asynchronous Loading Animation Engine (PowerShell Job)
# ==============================================================================

Clear-Host
Write-Host "===========================================================" -ForegroundColor DarkCyan
Write-Host "            VLC HIGH-PERFORMANCE STREAM RESOLVER           " -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor DarkCyan
Write-Host " Target URL : $targetUrl" -ForegroundColor Gray
Write-Host " VLC Engine : $VLC_PATH" -ForegroundColor DarkGray
Write-Host " Author     : Prof_MAN (pm9.s.gy)" -ForegroundColor DarkGray
Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray

# Define detached background worker for yt-dlp extraction
$ScriptBlock = {
    param($Url)

    try {
        # Extract 1080p video stream (attempt with Chrome cookies; fallback gracefully if browser locked/absent)
        $videoStream = $null
        try {
            $videoStream = & yt-dlp -f "bestvideo[height<=1080]" --cookies-from-browser chrome --buffer-size 16K -g $Url 2>$null
        } catch {}

        if (-not $videoStream) {
            $videoStream = & yt-dlp -f "bestvideo[height<=1080]" --buffer-size 16K -g $Url 2>$null
        }

        # Extract best audio stream
        $audioStream = $null
        try {
            $audioStream = & yt-dlp -f "bestaudio" --cookies-from-browser chrome --buffer-size 16K -g $Url 2>$null
        } catch {}

        if (-not $audioStream) {
            $audioStream = & yt-dlp -f "bestaudio" --buffer-size 16K -g $Url 2>$null
        }

        # Fallback to combined stream if separated DASH streams unavailable
        if (-not $videoStream -and -not $audioStream) {
            $videoStream = & yt-dlp -f "best[height<=1080]/best" --buffer-size 16K -g $Url 2>$null
        }

        if (-not $videoStream) {
            return "ERROR:No video stream resolved."
        }

        $vUrl = ($videoStream -split "`r?`n")[0].Trim()
        $aUrl = if ($audioStream) { ($audioStream -split "`r?`n")[0].Trim() } else { "" }

        return "$vUrl|||$aUrl"
    } catch {
        return "ERROR:$($_.Exception.Message)"
    }
}

# Launch background task
$Job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $targetUrl

# Indeterminate text-spinner loop
$animChars = @('|', '/', '-', '\')
$counter = 0

while ($Job.State -eq "Running") {
    $char = $animChars[$counter % 4]
    Write-Host "`r[$char] Contacting servers, resolving SSL handshakes, and parsing payload..." -ForegroundColor Yellow -NoNewLine
    Start-Sleep -Milliseconds 120
    $counter++
}

# Harvest extraction payload from background worker
$rawResult = Receive-Job -Job $Job
Remove-Job -Job $Job -Force

# --- Validation and Error Handling ---
if ([string]::IsNullOrWhiteSpace($rawResult) -or $rawResult -like "ERROR:*" -or -not $rawResult.Contains("|||")) {
    $errDetail = if ($rawResult -like "ERROR:*") { $rawResult.Substring(6) } else { "Failed to extract synchronized media feeds." }
    
    Write-Host "`r[FAIL] Stream resolution halted.                                           " -ForegroundColor Red
    Write-Host "`nReason: $errDetail" -ForegroundColor DarkRed

    [System.Windows.Forms.MessageBox]::Show(
        "Could not extract media streams from the requested link.`n`n" +
        "Target: $targetUrl`n`n" +
        "Possible causes:`n" +
        "1. Network timeout or restricted connection`n" +
        "2. Private, age-restricted, or geo-blocked video`n" +
        "3. Outdated extraction core`n`n" +
        "Tip: Open a terminal and run 'yt-dlp -U' to update your extraction engine.",
        "Stream Extraction Failed",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

# Split separated video and audio endpoints
$streams = $rawResult -split '\|\|\|'
$videoEndpoint = $streams[0].Trim()
$audioEndpoint = if ($streams.Length -gt 1) { $streams[1].Trim() } else { "" }

if ([string]::IsNullOrWhiteSpace($videoEndpoint)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Extracted video feed is empty or unplayable.",
        "Stream Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

Write-Host "`r[SUCCESS] High-definition media feeds successfully resolved!               " -ForegroundColor Green
Write-Host " Video Feed : Connected" -ForegroundColor Cyan
Write-Host " Audio Feed : $(if ($audioEndpoint) { 'Connected (Synchronized DASH)' } else { 'Embedded Track' })" -ForegroundColor Cyan

# ==============================================================================
# SECTION 5: High-Performance VLC Execution & Argument Optimization
# ==============================================================================

Write-Host "Launching VLC Media Player in high-performance mode..." -ForegroundColor Green

# Build command-line arguments array to ensure clean escaping
$vlcArguments = [System.Collections.Generic.List[string]]::new()

# Primary video feed
$vlcArguments.Add($videoEndpoint)

# Secondary synchronized audio feed
if (-not [string]::IsNullOrWhiteSpace($audioEndpoint)) {
    $vlcArguments.Add("--input-slave=$audioEndpoint")
}

# High-Performance Buffer, Hardware Acceleration & Window Tuning Flags
$vlcArguments.Add("--network-caching=5000")
$vlcArguments.Add("--file-caching=2000")
$vlcArguments.Add("--avcodec-hw=any")
$vlcArguments.Add("--no-video-title-show")
$vlcArguments.Add("--meta-title=YouTube High-Perf Stream")

# Single-window and single-instance safety flags
$vlcArguments.Add("--embedded-video")
$vlcArguments.Add("--one-instance")

# Execute VLC process exactly once
Start-Process -FilePath $VLC_PATH -ArgumentList $vlcArguments

Write-Host "Playback dispatched successfully. Enjoy your stream!" -ForegroundColor DarkGreen
Write-Host "Pipeline engineered by Prof_MAN (pm9.s.gy)" -ForegroundColor DarkCyan
