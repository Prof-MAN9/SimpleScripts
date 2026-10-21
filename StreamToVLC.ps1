<#
.SYNOPSIS
    VLC Advanced Stream Resolver & Player (StreamToVLC)
    Credits: Prof_MAN (pm9.s.gy)
.DESCRIPTION
    Extracts high-resolution video and audio streams from YouTube and 1,000+ supported sites 
    (Twitch, Vimeo, SoundCloud, Twitter/X, etc.) and streams them directly inside VLC Media Player.
    Supports DASH dual-stream synchronization (up to 4K/1080p), single-stream media, audio-only mode,
    clipboard auto-detection, quality presets, and custom buffering.
.AUTHOR
    Prof_MAN (pm9.s.gy)
.PARAMETER Url
    The target video, audio, or playlist link. If omitted, opens the interactive GUI dialog.
.PARAMETER Quality
    Resolution target: 'Best', '2160p', '1440p', '1080p', '720p', '480p', or 'AudioOnly'. Default: '1080p'.
.PARAMETER AudioOnly
    Extracts and plays audio only with video disabled in VLC.
.PARAMETER Fullscreen
    Starts VLC in fullscreen mode.
.PARAMETER Loop
    Repeats playback indefinitely.
.PARAMETER Playlist
    Allows full playlist extraction if a playlist link is provided.
.PARAMETER BufferMs
    Network caching buffer in milliseconds (default: 3000ms for stutter-free streaming).
.PARAMETER Update
    Checks for and installs updates for yt-dlp.
.EXAMPLE
    .\StreamToVLC.ps1
    # Opens interactive GUI with clipboard auto-fill and quality picker
.EXAMPLE
    .\StreamToVLC.ps1 "https://www.youtube.com/watch?v=aqz-KE-bpKQ" -Quality 1080p
.EXAMPLE
    .\StreamToVLC.ps1 "https://soundcloud.com/artist/track" -AudioOnly
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('Link', 'URI')]
    [string]$Url,

    [ValidateSet('Best', '2160p', '1440p', '1080p', '720p', '480p', 'AudioOnly')]
    [string]$Quality = '1080p',

    [switch]$AudioOnly,
    [switch]$Fullscreen,
    [switch]$Loop,
    [switch]$Playlist,
    [int]$BufferMs = 3000,
    [switch]$Update
)

# Ensure required Windows GUI assemblies are loaded
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

# ==============================================================================
# Helper Functions: Dependency Detection & Resolution
# ==============================================================================

function Find-VLC {
    <#
    .SYNOPSIS
        Auto-locates vlc.exe across common paths, registry keys, and PATH.
    #>
    # 1. Custom environment variable override
    if ($env:VLC_PATH -and (Test-Path $env:VLC_PATH)) { 
        return $env:VLC_PATH 
    }

    # 2. Check PATH environment
    $cmd = Get-Command "vlc" -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path $cmd.Source)) { 
        return $cmd.Source 
    }

    # 3. Check Windows Registry
    $regPaths = @(
        "HKLM:\SOFTWARE\VideoLAN\VLC",
        "HKLM:\SOFTWARE\WOW6432Node\VideoLAN\VLC",
        "HKCU:\SOFTWARE\VideoLAN\VLC"
    )
    foreach ($reg in $regPaths) {
        if (Test-Path $reg) {
            $installDir = (Get-ItemProperty -Path $reg -ErrorAction SilentlyContinue).InstallDir
            if ($installDir) {
                $candidate = Join-Path $installDir "vlc.exe"
                if (Test-Path $candidate) { return $candidate }
            }
        }
    }

    # 4. Standard Program Files directories
    $knownLocations = @(
        "${env:ProgramFiles}\VideoLAN\VLC\vlc.exe",
        "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe",
        "${env:LOCALAPPDATA}\Programs\VLC\vlc.exe"
    )
    foreach ($path in $knownLocations) {
        if ($path -and (Test-Path $path)) { return $path }
    }

    return $null
}

function Find-YtDlp {
    <#
    .SYNOPSIS
        Auto-locates yt-dlp.exe in PATH and known portable tool paths.
    #>
    $cmd = Get-Command "yt-dlp" -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path $cmd.Source)) { 
        return $cmd.Source 
    }

    $candidates = @(
        (Join-Path $PSScriptRoot "yt-dlp.exe"),
        (Join-Path $env:LOCALAPPDATA "yt-dlp\yt-dlp.exe"),
        (Join-Path $env:USERPROFILE "yt-dlp.exe"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\yt-dlp.yt-dlp_Microsoft.Winget.Source_8wekyb3d8bbwe\yt-dlp.exe"),
        (Join-Path $env:USERPROFILE "scoop\shims\yt-dlp.exe")
    )
    foreach ($path in $candidates) {
        if ($path -and (Test-Path $path)) { return $path }
    }

    return $null
}

function Show-ModernPrompt {
    <#
    .SYNOPSIS
        Displays a clean, styled dialog box with URL input, clipboard detection,
        and stream preferences if no CLI arguments were supplied.
    #>
    param([string]$InitialUrl)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "VLC Advanced Stream Resolver"
    $form.Size = New-Object System.Drawing.Size(540, 360)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

    # Title Banner
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Stream Directly to VLC"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12.0, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(230, 81, 0)
    $titleLabel.Location = New-Object System.Drawing.Point(20, 15)
    $titleLabel.Size = New-Object System.Drawing.Size(480, 25)
    $form.Controls.Add($titleLabel)

    $subLabel = New-Object System.Windows.Forms.Label
    $subLabel.Text = "Paste any YouTube, Twitch, Vimeo, or media URL to stream without ads or lag."
    $subLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
    $subLabel.Location = New-Object System.Drawing.Point(20, 42)
    $subLabel.Size = New-Object System.Drawing.Size(480, 20)
    $form.Controls.Add($subLabel)

    # URL Label
    $urlLabel = New-Object System.Windows.Forms.Label
    $urlLabel.Text = "Target Media URL:"
    $urlLabel.Location = New-Object System.Drawing.Point(20, 75)
    $urlLabel.Size = New-Object System.Drawing.Size(200, 20)
    $form.Controls.Add($urlLabel)

    # URL Input TextBox
    $txtUrl = New-Object System.Windows.Forms.TextBox
    $txtUrl.Location = New-Object System.Drawing.Point(20, 100)
    $txtUrl.Size = New-Object System.Drawing.Size(380, 26)
    $txtUrl.Text = $InitialUrl
    $form.Controls.Add($txtUrl)

    # Paste Button
    $btnPaste = New-Object System.Windows.Forms.Button
    $btnPaste.Text = "Paste"
    $btnPaste.Location = New-Object System.Drawing.Point(408, 98)
    $btnPaste.Size = New-Object System.Drawing.Size(95, 29)
    $btnPaste.Add_Click({
        $clip = [System.Windows.Forms.Clipboard]::GetText()
        if (-not [string]::IsNullOrWhiteSpace($clip)) {
            $txtUrl.Text = $clip.Trim()
        }
    })
    $form.Controls.Add($btnPaste)

    # Quality Label & ComboBox
    $qualLabel = New-Object System.Windows.Forms.Label
    $qualLabel.Text = "Quality Preset:"
    $qualLabel.Location = New-Object System.Drawing.Point(20, 140)
    $qualLabel.Size = New-Object System.Drawing.Size(120, 20)
    $form.Controls.Add($qualLabel)

    $comboQuality = New-Object System.Windows.Forms.ComboBox
    $comboQuality.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $comboQuality.Location = New-Object System.Drawing.Point(145, 137)
    $comboQuality.Size = New-Object System.Drawing.Size(255, 26)
    $null = $comboQuality.Items.Add("1080p (Full HD - Recommended)")
    $null = $comboQuality.Items.Add("Best Available (4K / 2K UHD)")
    $null = $comboQuality.Items.Add("1440p (2K QHD)")
    $null = $comboQuality.Items.Add("720p (HD - Fast Buffering)")
    $null = $comboQuality.Items.Add("480p (SD - Data Saver)")
    $null = $comboQuality.Items.Add("Audio Only (Music / Podcast)")
    $comboQuality.SelectedIndex = 0
    $form.Controls.Add($comboQuality)

    # Checkboxes: Fullscreen & Loop & AudioOnly
    $chkFullscreen = New-Object System.Windows.Forms.CheckBox
    $chkFullscreen.Text = "Fullscreen"
    $chkFullscreen.Location = New-Object System.Drawing.Point(20, 185)
    $chkFullscreen.Size = New-Object System.Drawing.Size(120, 24)
    $form.Controls.Add($chkFullscreen)

    $chkLoop = New-Object System.Windows.Forms.CheckBox
    $chkLoop.Text = "Loop Playback"
    $chkLoop.Location = New-Object System.Drawing.Point(150, 185)
    $chkLoop.Size = New-Object System.Drawing.Size(130, 24)
    $form.Controls.Add($chkLoop)

    $chkAudioOnly = New-Object System.Windows.Forms.CheckBox
    $chkAudioOnly.Text = "Audio Only"
    $chkAudioOnly.Location = New-Object System.Drawing.Point(290, 185)
    $chkAudioOnly.Size = New-Object System.Drawing.Size(120, 24)
    $chkAudioOnly.Add_CheckedChanged({
        if ($chkAudioOnly.Checked) {
            $comboQuality.SelectedIndex = 5 # Audio Only
        }
    })
    $form.Controls.Add($chkAudioOnly)

    # Action Buttons: Stream & Cancel
    $btnStream = New-Object System.Windows.Forms.Button
    $btnStream.Text = "Stream to VLC"
    $btnStream.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnStream.BackColor = [System.Drawing.Color]::FromArgb(230, 81, 0)
    $btnStream.ForeColor = [System.Drawing.Color]::White
    $btnStream.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnStream.Location = New-Object System.Drawing.Point(260, 245)
    $btnStream.Size = New-Object System.Drawing.Size(130, 36)
    $btnStream.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($btnStream)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = New-Object System.Drawing.Point(400, 245)
    $btnCancel.Size = New-Object System.Drawing.Size(100, 36)
    $form.Controls.Add($btnCancel)

    $form.AcceptButton = $btnStream
    $form.CancelButton = $btnCancel

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    $selectedQuality = switch ($comboQuality.SelectedIndex) {
        0 { '1080p' }
        1 { 'Best' }
        2 { '1440p' }
        3 { '720p' }
        4 { '480p' }
        5 { 'AudioOnly' }
        Default { '1080p' }
    }

    return [PSCustomObject]@{
        Url        = $txtUrl.Text.Trim()
        Quality    = $selectedQuality
        Fullscreen = $chkFullscreen.Checked
        Loop       = $chkLoop.Checked
        AudioOnly  = $chkAudioOnly.Checked -or ($selectedQuality -eq 'AudioOnly')
    }
}

# ==============================================================================
# Main Program Flow
# ==============================================================================

# 1. Self-Update Switch Check
$ytDlpPath = Find-YtDlp
if ($Update) {
    if (-not $ytDlpPath) {
        Write-Warning "yt-dlp is not installed. Cannot update."
    } else {
        Write-Host "Updating yt-dlp engine..." -ForegroundColor Cyan
        & $ytDlpPath -U
    }
    if ([string]::IsNullOrWhiteSpace($Url)) { exit 0 }
}

# 2. Check & Validate VLC Installation
$VlcPath = Find-VLC
if (-not $VlcPath) {
    [System.Windows.Forms.MessageBox]::Show(
        "VLC Media Player was not found on this system.`n`nPlease install VLC from https://www.videolan.org or run:`nwinget install VideoLAN.VLC",
        "VLC Missing",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    Write-Host "[ERROR] VLC executable could not be found." -ForegroundColor Red
    exit 1
}

# 3. Check & Validate yt-dlp Installation
if (-not $ytDlpPath) {
    $installChoice = [System.Windows.Forms.MessageBox]::Show(
        "yt-dlp is required to extract media streams but was not found.`n`nWould you like to open instructions or install it using winget?`n`nRun this command in PowerShell to install:`nwinget install yt-dlp",
        "yt-dlp Dependency Missing",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    Write-Host "[ERROR] 'yt-dlp' was not found. Please run 'winget install yt-dlp' or download it from https://github.com/yt-dlp/yt-dlp/releases" -ForegroundColor Red
    exit 1
}

# 4. Resolve URL & Parameters (CLI vs GUI Input)
if ([string]::IsNullOrWhiteSpace($Url)) {
    # Check clipboard for a video/audio URL candidate
    $initialClipboard = ""
    try {
        $clipText = [System.Windows.Forms.Clipboard]::GetText()
        if ($clipText -match '^https?://[^\s]+$') {
            $initialClipboard = $clipText.Trim()
        }
    } catch {}

    $guiOptions = Show-ModernPrompt -InitialUrl $initialClipboard
    if ($null -eq $guiOptions -or [string]::IsNullOrWhiteSpace($guiOptions.Url)) {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        exit 0
    }

    $Url        = $guiOptions.Url
    $Quality    = $guiOptions.Quality
    $Fullscreen = $guiOptions.Fullscreen
    $Loop       = $guiOptions.Loop
    $AudioOnly  = $guiOptions.AudioOnly
}

# 5. Format Selection Logic
$formatSelector = switch ($Quality) {
    'Best'      { 'bestvideo+bestaudio/best' }
    '2160p'     { 'bestvideo[height<=?2160]+bestaudio/best[height<=?2160]/best' }
    '1440p'     { 'bestvideo[height<=?1440]+bestaudio/best[height<=?1440]/best' }
    '1080p'     { 'bestvideo[height<=?1080]+bestaudio/best[height<=?1080]/best' }
    '720p'      { 'bestvideo[height<=?720]+bestaudio/best[height<=?720]/best' }
    '480p'      { 'bestvideo[height<=?480]+bestaudio/best[height<=?480]/best' }
    'AudioOnly' { 'bestaudio/best' }
    Default     { 'bestvideo[height<=?1080]+bestaudio/best[height<=?1080]/best' }
}

if ($AudioOnly) {
    $formatSelector = 'bestaudio/best'
}

# 6. Console Banner & Progress Display
Clear-Host
Write-Host "===========================================================" -ForegroundColor DarkCyan
Write-Host "            VLC ADVANCED STREAM RESOLVER & PLAYER          " -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor DarkCyan
Write-Host " Target URL : $Url" -ForegroundColor Gray
Write-Host " Quality    : $Quality $(if ($AudioOnly) { '[Audio Only]' })" -ForegroundColor Gray
Write-Host " VLC Binary : $VlcPath" -ForegroundColor DarkGray
Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray

# 7. Asynchronous Extraction Process (Single-pass metadata + streams)
$ytArgs = @(
    '--no-warnings',
    '--no-color',
    '-f', $formatSelector,
    '--print', '%(title)s',
    '--print', '%(uploader,channel,creator)s',
    '--print', '%(duration_string)s',
    '-g'
)

if (-not $Playlist) {
    $ytArgs += '--no-playlist'
}
$ytArgs += $Url

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = $ytDlpPath
$psi.Arguments              = ($ytArgs | ForEach-Object { 
    if ($_ -match '[\s"]') { '"{0}"' -f ($_ -replace '"', '\"') } else { $_ } 
}) -join ' '
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.UseShellExecute        = $false
$psi.CreateNoWindow         = $true

$proc = [System.Diagnostics.Process]::Start($psi)

$animChars = @('|', '/', '-', '\')
$counter = 0
while (-not $proc.HasExited) {
    $char = $animChars[$counter % 4]
    Write-Host "`r[$char] Contacting servers, verifying codecs, and extracting stream payload..." -ForegroundColor Yellow -NoNewLine
    Start-Sleep -Milliseconds 120
    $counter++
}

$rawOutput = $proc.StandardOutput.ReadToEnd()
$rawError  = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

# 8. Result Validation & Error Handling
if ($proc.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($rawOutput)) {
    $errSnippet = if (-not [string]::IsNullOrWhiteSpace($rawError)) { $rawError.Trim() } else { "Unknown extraction error." }
    Write-Host "`r[FAIL] Extraction halted due to an engine error.                         " -ForegroundColor Red
    Write-Host "`nError Details:" -ForegroundColor DarkRed
    Write-Host $errSnippet -ForegroundColor Red

    [System.Windows.Forms.MessageBox]::Show(
        "Could not extract media stream.`n`nReason:`n$errSnippet`n`nTips:`n- Check if the URL is valid and public`n- Update yt-dlp by running: .\StreamToVLC.ps1 -Update",
        "Stream Extraction Failed",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}

# 9. Parse Metadata & Stream URLs
$lines = $rawOutput -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

if ($lines.Count -lt 4) {
    Write-Host "`r[FAIL] Incomplete stream payload returned.                              " -ForegroundColor Red
    [System.Windows.Forms.MessageBox]::Show(
        "yt-dlp returned incomplete stream data. Video may be geo-restricted, private, or unsupported.",
        "Payload Incomplete",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    exit 1
}

$title     = $lines[0]
$uploader  = $lines[1]
$duration  = $lines[2]
$streamUrl = $lines[3]
$audioUrl  = if ($lines.Count -ge 5) { $lines[4] } else { $null }

# 10. Display Stream Metadata Card
Write-Host "`r[SUCCESS] Media streams successfully resolved!                          " -ForegroundColor Green
Write-Host ""
Write-Host " Title    : $title" -ForegroundColor White
Write-Host " Creator  : $uploader" -ForegroundColor Gray
Write-Host " Duration : $duration" -ForegroundColor Gray
if ($audioUrl) {
    Write-Host " Streams  : Dual DASH Sync (Video + High-Bitrate Audio Track)" -ForegroundColor Cyan
} else {
    Write-Host " Stream   : Single Combined Stream" -ForegroundColor Cyan
}
Write-Host " Buffering: ${BufferMs}ms network cache" -ForegroundColor DarkGray
Write-Host ""

# 11. Construct VLC Execution Arguments
$vlcArguments = [System.Collections.Generic.List[string]]::new()

# Primary media stream
$vlcArguments.Add($streamUrl)

# Synchronized secondary audio feed (for separate DASH video+audio)
if ($audioUrl -and -not $AudioOnly) {
    $vlcArguments.Add(":input-slave=$audioUrl")
}

# Ensure single-window playback
$vlcArguments.Add("--embedded-video")
$vlcArguments.Add("--one-instance")

# Metadata title displayed in VLC window & playlist
$vlcArguments.Add("--meta-title=$title")

# Network caching buffer
$vlcArguments.Add("--network-caching=$BufferMs")

# Playback options
if ($AudioOnly) {
    $vlcArguments.Add("--no-video")
}
if ($Fullscreen -and -not $AudioOnly) {
    $vlcArguments.Add("--fullscreen")
}
if ($Loop) {
    $vlcArguments.Add("--loop")
}

# 12. Launch VLC Player
Write-Host "Launching VLC Media Player..." -ForegroundColor Green
Start-Process -FilePath $VlcPath -ArgumentList $vlcArguments

Write-Host "Stream dispatched successfully. Enjoy watching!" -ForegroundColor DarkGreen
Write-Host "Created with assistance for Prof_MAN (pm9.s.gy)" -ForegroundColor DarkCyan

