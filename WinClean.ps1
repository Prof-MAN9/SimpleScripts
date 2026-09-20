#Requires -Version 5.1
<#
.SYNOPSIS
  WinClean.ps1 v4.0 – BleachBit-class Deep Cleaning & Privacy Tool for Windows

.DESCRIPTION
  Enterprise-grade cleanup tool modelled on BleachBit's philosophy:
    • Per-item size preview before ANY deletion (Analyze mode)
    • Secure file shredding (DoD 5220.22-M / Gutmann patterns)
    • Full privacy sweep (recent docs, jump lists, clipboard, typed URLs, run history,
      shell bags, MUICache, UserAssist, search history, network passwords)
    • Browser cleaning: Chrome, Edge, Firefox, Brave, Opera, Vivaldi, IE
      – per-profile, selectable sub-items (cache / cookies / history / passwords / forms)
    • Application residue: 40+ apps detected and cleaned
    • Windows system cleaning: 25+ system artifact categories
    • Per-user profile support (clean all users or selected users)
    • Live disk-usage progress bar and before/after space delta
    • Scheduled-task installer (-InstallScheduled)
    • Fully non-destructive Analyze/WhatIf modes
    • Structured JSON-compatible log output

.PARAMETER Analyze
  Scan everything, report sizes, make NO changes. Equivalent to BleachBit "Preview".

.PARAMETER WhatIf
  Alias for -Analyze.

.PARAMETER Clean
  Run all selected cleaners (uses -Include / -Exclude to scope).

.PARAMETER RunAll
  Clean everything without prompting (requires -Yes).

.PARAMETER Yes
  Auto-confirm all prompts.

.PARAMETER Include
  Comma-separated cleaner IDs to run (e.g. "system.temp,browser.chrome").
  Use -Analyze to list all IDs.

.PARAMETER Exclude
  Comma-separated cleaner IDs to skip.

.PARAMETER AllUsers
  Also clean other user profiles (requires elevation).

.PARAMETER Shred
  Overwrite file data before deletion (secure erase, slower).

.PARAMETER ShredPasses
  Number of overwrite passes for shredding (default 3, max 35).

.PARAMETER InstallScheduled
  Install a weekly scheduled task to run WinClean silently.

.PARAMETER RemoveScheduled
  Remove the scheduled task.

.PARAMETER LogPath
  Custom log file path.

.PARAMETER JsonLog
  Also emit a machine-readable JSON summary at end.

.PARAMETER Help
  Show help.

.PARAMETER Version
  Print version.

.NOTES
  Version  : 4.0.0
  Requires : PowerShell 5.1+, Windows 10/11
  Elevation: Recommended – required for system-level cleaners.
  Safety   : Always run -Analyze first. Shredding is irreversible.
#>

[CmdletBinding()]
param(
    [switch]$Analyze,
    [switch]$WhatIf,          # alias for -Analyze
    [switch]$Clean,
    [switch]$RunAll,
    [switch]$Yes,
    [string[]]$Include    = @(),
    [string[]]$Exclude    = @(),
    [switch]$AllUsers,
    [switch]$Shred,
    [int]$ShredPasses     = 3,
    [switch]$InstallScheduled,
    [switch]$RemoveScheduled,
    [string]$LogPath      = '',
    [switch]$JsonLog,
    [switch]$Help,
    [switch]$Version
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$script:ScriptVersion  = '4.0.0'
$script:ScriptPath     = $MyInvocation.MyCommand.Path

# Merge -WhatIf into -Analyze
if ($WhatIf) { $Analyze = $true }

if ($Help) {
    Get-Help $script:ScriptPath -Full 2>$null
    if (-not $?) { Get-Content $script:ScriptPath | Select-String '^<#' -Context 0,60 | Select-Object -First 1 | ForEach-Object { $_.Context.PostContext } }
    exit 0
}
if ($Version) { Write-Host "WinClean v$script:ScriptVersion"; exit 0 }

# ─────────────────────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────────────────────
$script:LogDir = Join-Path $env:LOCALAPPDATA 'WinClean'
if (-not (Test-Path $script:LogDir)) { New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null }
$script:LogFile = if ($LogPath) { $LogPath } else {
    Join-Path $script:LogDir ("WinClean_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
}
try { Start-Transcript -Path $script:LogFile -Append -ErrorAction SilentlyContinue } catch {}

$script:LogEntries = [System.Collections.Generic.List[object]]::new()

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO', [string]$Cleaner = '')
    $ts   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "$ts [$Level] $Msg"
    $line | Add-Content -Path $script:LogFile -ErrorAction SilentlyContinue
    $script:LogEntries.Add([pscustomobject]@{ Time=$ts; Level=$Level; Cleaner=$Cleaner; Message=$Msg })
    $color = switch ($Level) {
        'WARN'    { 'Yellow'  }
        'ERROR'   { 'Red'     }
        'OK'      { 'Green'   }
        'SECTION' { 'Cyan'    }
        'SIZE'    { 'Magenta' }
        default   { 'Gray'    }
    }
    Write-Host $line -ForegroundColor $color
}

function Write-Section ([string]$Title) {
    $bar = '═' * 64
    Write-Host "`n$bar" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "$bar" -ForegroundColor Cyan
    Write-Log "=== $Title ===" -Level SECTION
}

# ─────────────────────────────────────────────────────────────
# GLOBAL STATE
# ─────────────────────────────────────────────────────────────
$script:IsAnalyze  = [bool]$Analyze
$script:AutoYes    = [bool]$Yes
$script:DoShred    = [bool]$Shred
$script:ShredN     = [math]::Min([math]::Max($ShredPasses,1),35)
$script:IsAdmin    = $false
$script:InitFree   = 0

$script:Stats = [ordered]@{
    FilesRemoved  = 0
    DirsRemoved   = 0
    BytesFreed    = 0
    BytesAnalyzed = 0
    Errors        = 0
    Skipped       = 0
    StartTime     = Get-Date
}

# Per-cleaner results for JSON output
$script:CleanerResults = [System.Collections.Generic.List[object]]::new()

# ─────────────────────────────────────────────────────────────
# CORE UTILITIES
# ─────────────────────────────────────────────────────────────
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-Bytes ([long]$Bytes) {
    if ($Bytes -ge 1TB)  { return '{0:N2} TB'  -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB)  { return '{0:N2} GB'  -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB)  { return '{0:N2} MB'  -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB)  { return '{0:N2} KB'  -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-FolderSize ([string]$Path) {
    if (-not (Test-Path $Path)) { return 0L }
    try {
        $sum = (Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        return if ($sum) { [long]$sum } else { 0L }
    } catch { return 0L }
}

function Get-ItemSize ([string]$Path) {
    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) { return 0L }
    $i = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $i) { return 0L }
    if ($i.PSIsContainer) { return Get-FolderSize $Path }
    return [long]$i.Length
}

function Confirm-Action ([string]$Message = 'Proceed?') {
    if ($script:IsAnalyze) { return $false }
    if ($script:AutoYes)   { return $true  }
    $r = Read-Host "$Message [y/N]"
    return ($r -match '^(y|yes)$')
}

# Progress bar helper
function Show-Progress ([string]$Activity, [string]$Status, [int]$Pct) {
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $Pct
}

# ─────────────────────────────────────────────────────────────
# SECURE SHRED
# ─────────────────────────────────────────────────────────────
function Invoke-SecureShred ([string]$Path) {
    <#
    Overwrites file content with multiple passes before deleting.
    Patterns: zeros, ones, random (repeated $script:ShredN times).
    #>
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    try {
        $len = (Get-Item -LiteralPath $Path -Force).Length
        if ($len -eq 0) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue; return }
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $passes = @(
            [byte]0x00,   # zeros
            [byte]0xFF,   # ones
            $null         # random (handled below)
        )
        for ($pass = 0; $pass -lt $script:ShredN; $pass++) {
            $stream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
            $buf = New-Object byte[] ([math]::Min($len, 65536))
            $written = 0L
            $pattern = $passes[$pass % $passes.Count]
            while ($written -lt $len) {
                if ($null -eq $pattern) {
                    [System.Security.Cryptography.RNGCryptoServiceProvider]::new().GetBytes($buf)
                } else {
                    for ($i=0; $i -lt $buf.Length; $i++) { $buf[$i] = $pattern }
                }
                $chunk = [math]::Min($buf.Length, $len - $written)
                $stream.Write($buf, 0, $chunk)
                $written += $chunk
            }
            $stream.Flush()
        }
        $stream.Close()
        $stream.Dispose()
        # Rename before delete to obscure filename
        $tempName = Join-Path (Split-Path $Path -Parent) ([System.IO.Path]::GetRandomFileName())
        Rename-Item -LiteralPath $Path -NewName $tempName -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempName -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Shred failed for ${Path}: $_" -Level WARN
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

# ─────────────────────────────────────────────────────────────
# SAFE REMOVE (with optional shred, size tracking, analyze mode)
# ─────────────────────────────────────────────────────────────
function Remove-ItemSafe {
    param(
        [string]$Path,
        [switch]$Recurse,
        [string]$CleanerId = ''
    )
    if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) { return }
    $size = Get-ItemSize $Path
    if ($script:IsAnalyze) {
        Write-Log ("  ANALYZE  {0,-14}  {1}" -f (Format-Bytes $size), $Path) -Level SIZE -Cleaner $CleanerId
        $script:Stats.BytesAnalyzed += $size
        return
    }
    try {
        if ($script:DoShred -and -not (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue).PSIsContainer) {
            Invoke-SecureShred $Path
        } else {
            Remove-Item -LiteralPath $Path -Recurse:$Recurse -Force -ErrorAction Stop
        }
        $isDir = -not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)
        if ($isDir -and -not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
            $script:Stats.DirsRemoved++
        } else {
            $script:Stats.FilesRemoved++
        }
        $script:Stats.BytesFreed += $size
        Write-Log ("  REMOVED  {0,-14}  {1}" -f (Format-Bytes $size), $Path) -Level OK -Cleaner $CleanerId
    } catch {
        $script:Stats.Errors++
        Write-Log "  FAILED   $Path  [$($_.Exception.Message)]" -Level WARN -Cleaner $CleanerId
    }
}

function Remove-FolderContents {
    param(
        [string]$Path,
        [string[]]$Include    = @('*'),
        [string[]]$Exclude    = @(),
        [int]$OlderThanDays   = 0,
        [switch]$FilesOnly,
        [string]$CleanerId    = ''
    )
    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) { return }
    $cutoff = if ($OlderThanDays -gt 0) { (Get-Date).AddDays(-$OlderThanDays) } else { $null }
    $items  = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        if ($Exclude -and ($Exclude | Where-Object { $item.Name -like $_ })) { $script:Stats.Skipped++; continue }
        if ($FilesOnly -and $item.PSIsContainer) { continue }
        if ($cutoff -and $item.LastWriteTime -gt $cutoff) { $script:Stats.Skipped++; continue }
        Remove-ItemSafe -Path $item.FullName -Recurse -CleanerId $CleanerId
    }
}

# ─────────────────────────────────────────────────────────────
# CLEANER FRAMEWORK
# ─────────────────────────────────────────────────────────────
$script:Cleaners = [ordered]@{}   # id → [ordered]@{ Name; Category; Description; Fn; RequiresAdmin; RiskLevel }

function Register-Cleaner {
    param(
        [string]$Id,
        [string]$Name,
        [string]$Category,
        [string]$Description,
        [scriptblock]$Fn,
        [bool]$RequiresAdmin = $false,
        [ValidateSet('Safe','Moderate','Advanced')]
        [string]$Risk = 'Safe'
    )
    $script:Cleaners[$Id] = [ordered]@{
        Id           = $Id
        Name         = $Name
        Category     = $Category
        Description  = $Description
        Fn           = $Fn
        RequiresAdmin= $RequiresAdmin
        Risk         = $Risk
    }
}

function Invoke-Cleaner {
    param([string]$Id)
    $c = $script:Cleaners[$Id]
    if (-not $c) { Write-Log "Unknown cleaner: $Id" -Level WARN; return }
    if ($c.RequiresAdmin -and -not $script:IsAdmin) {
        Write-Log "Skipping '$($c.Name)' – requires elevation" -Level WARN
        $script:Stats.Skipped++
        return
    }
    $beforeBytes = $script:Stats.BytesFreed + $script:Stats.BytesAnalyzed
    $beforeErrors= $script:Stats.Errors
    Write-Log "[$Id] $($c.Name)" -Level INFO -Cleaner $Id
    try {
        & $c.Fn
    } catch {
        $script:Stats.Errors++
        Write-Log "ERROR in ${Id}: $($_.Exception.Message)" -Level ERROR -Cleaner ${Id}
    }
    $afterBytes  = $script:Stats.BytesFreed + $script:Stats.BytesAnalyzed
    $gained      = $afterBytes - $beforeBytes
    $errs        = $script:Stats.Errors - $beforeErrors
    $script:CleanerResults.Add([pscustomobject]@{
        Id=$Id; Name=$c.Name; Category=$c.Category
        BytesCleaned=$gained; Errors=$errs
    })
    if ($gained -gt 0) { Write-Log "  → $(Format-Bytes $gained) identified/freed" -Level SIZE -Cleaner $Id }
}

# ═══════════════════════════════════════════════════════════════
# ███  SYSTEM CLEANERS
# ═══════════════════════════════════════════════════════════════

Register-Cleaner -Id 'system.update_cache' -Name 'Windows Update Cache' -Category 'System' -RequiresAdmin $true -Risk 'Safe' -Description 'Downloaded update packages pending or already installed' -Fn {
    $target = 'C:\Windows\SoftwareDistribution\Download'
    if (-not (Test-Path $target)) { return }
    $sz = Get-FolderSize $target
    Write-Log "  Size: $(Format-Bytes $sz)" -Level SIZE
    if (-not $script:IsAnalyze) {
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        Remove-FolderContents -Path $target -CleanerId 'system.update_cache'
        Start-Service wuauserv -ErrorAction SilentlyContinue
    } else {
        $script:Stats.BytesAnalyzed += $sz
    }
}

Register-Cleaner -Id 'system.delivery_opt' -Name 'Delivery Optimization Cache' -Category 'System' -Risk 'Safe' -Description 'P2P Windows update cache fragments' -Fn {
    $paths = @(
        'C:\Windows\SoftwareDistribution\DeliveryOptimization\Cache',
        "$env:LOCALAPPDATA\Microsoft\Windows\DeliveryOptimization\Cache"
    )
    foreach ($p in $paths) { Remove-FolderContents -Path $p -CleanerId 'system.delivery_opt' }
}

Register-Cleaner -Id 'system.temp' -Name 'Temporary Files' -Category 'System' -Risk 'Safe' -Description '%TEMP%, %TMP%, Windows\Temp, LocalAppData\Temp' -Fn {
    $paths = @(
        $env:TEMP, $env:TMP,
        "$env:windir\Temp",
        "$env:SystemRoot\Temp",
        "$env:LOCALAPPDATA\Temp",
        'C:\Windows\Temp'
    ) | Sort-Object -Unique
    foreach ($p in $paths) {
        Remove-FolderContents -Path $p -OlderThanDays 1 -CleanerId 'system.temp'
    }
}

Register-Cleaner -Id 'system.memory_dumps' -Name 'Memory Dumps' -Category 'System' -RequiresAdmin $true -Risk 'Safe' -Description 'MEMORY.DMP, minidumps, live kernel reports' -Fn {
    $targets = @(
        'C:\Windows\MEMORY.DMP',
        'C:\Windows\Minidump',
        'C:\Windows\LiveKernelReports',
        "$env:LOCALAPPDATA\CrashDumps"
    )
    foreach ($t in $targets) {
        if (-not (Test-Path $t)) { continue }
        $item = Get-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue
        if ($item.PSIsContainer) { Remove-FolderContents -Path $t -CleanerId 'system.memory_dumps' }
        else { Remove-ItemSafe -Path $t -CleanerId 'system.memory_dumps' }
    }
    # Hibernate file
    $hib = 'C:\hiberfil.sys'
    if ($script:IsAdmin -and (Test-Path $hib)) {
        $sz = (Get-Item $hib -Force).Length
        Write-Log "  hiberfil.sys: $(Format-Bytes $sz) – disable hibernation to reclaim" -Level SIZE
        if (-not $script:IsAnalyze) {
            if (Confirm-Action "Disable hibernation and remove hiberfil.sys ($(Format-Bytes $sz))?") {
                powercfg /hibernate off 2>&1 | Out-Null
                Write-Log "  Hibernation disabled" -Level OK
            }
        } else { $script:Stats.BytesAnalyzed += $sz }
    }
}

Register-Cleaner -Id 'system.error_reports' -Name 'Windows Error Reports' -Category 'System' -Risk 'Safe' -Description 'WER report archives, queues, diagnostics' -Fn {
    $paths = @(
        'C:\ProgramData\Microsoft\Windows\WER\ReportArchive',
        'C:\ProgramData\Microsoft\Windows\WER\ReportQueue',
        'C:\ProgramData\Microsoft\Windows\WER\Temp',
        "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",
        "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue",
        "$env:ProgramData\Microsoft\Diagnosis"
    )
    foreach ($p in $paths) { Remove-FolderContents -Path $p -CleanerId 'system.error_reports' }
}

Register-Cleaner -Id 'system.prefetch' -Name 'Prefetch Files' -Category 'System' -RequiresAdmin $true -Risk 'Safe' -Description 'Application launch prefetch; Windows rebuilds automatically' -Fn {
    Remove-FolderContents -Path "$env:windir\Prefetch" -CleanerId 'system.prefetch'
}

Register-Cleaner -Id 'system.font_cache' -Name 'Font Cache' -Category 'System' -RequiresAdmin $true -Risk 'Safe' -Description 'Font rendering cache; rebuilt on next boot' -Fn {
    if (-not $script:IsAnalyze) { Stop-Service FontCache -Force -ErrorAction SilentlyContinue }
    $paths = @(
        "$env:WinDir\ServiceProfiles\LocalService\AppData\Local\FontCache",
        "$env:WinDir\ServiceProfiles\LocalService\AppData\Local\FontCache-System",
        "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    )
    foreach ($p in $paths) { Remove-FolderContents -Path $p -CleanerId 'system.font_cache' }
    if (-not $script:IsAnalyze) { Start-Service FontCache -ErrorAction SilentlyContinue }
}

Register-Cleaner -Id 'system.thumbnail_cache' -Name 'Thumbnail & Icon Cache' -Category 'System' -Risk 'Safe' -Description 'Explorer thumbnail database files' -Fn {
    $path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    if (-not (Test-Path $path)) { return }
    Get-ChildItem -Path $path -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-ItemSafe $_.FullName -CleanerId 'system.thumbnail_cache' }
    Get-ChildItem -Path $path -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-ItemSafe $_.FullName -CleanerId 'system.thumbnail_cache' }
}

Register-Cleaner -Id 'system.inet_cache' -Name 'Internet Explorer / WebView Cache' -Category 'System' -Risk 'Safe' -Description 'Legacy IE and WebView2 cached pages and cookies' -Fn {
    $paths = @(
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCookies",
        "$env:LOCALAPPDATA\Microsoft\Windows\Temporary Internet Files",
        "$env:LOCALAPPDATA\Microsoft\Windows\WebCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\History",
        "$env:LOCALAPPDATA\Microsoft\CryptnetUrlCache"
    )
    foreach ($p in $paths) { Remove-FolderContents -Path $p -CleanerId 'system.inet_cache' }
}

Register-Cleaner -Id 'system.store_cache' -Name 'Microsoft Store Cache' -Category 'System' -Risk 'Safe' -Description 'Windows Store download cache (wsreset)' -Fn {
    $paths = @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache")
    foreach ($p in $paths) { Remove-FolderContents -Path $p -CleanerId 'system.store_cache' }
    if (-not $script:IsAnalyze) {
        Start-Process wsreset.exe -NoNewWindow -Wait -ErrorAction SilentlyContinue
    }
}

Register-Cleaner -Id 'system.update_history' -Name 'Windows Update History / DataStore' -Category 'System' -RequiresAdmin $true -Risk 'Moderate' -Description 'Update history database; view history will be reset' -Fn {
    $target = 'C:\Windows\SoftwareDistribution\DataStore'
    if (-not (Test-Path $target)) { return }
    Write-Log "  Size: $(Format-Bytes (Get-FolderSize $target))" -Level SIZE
    if (-not $script:IsAnalyze) {
        if (Confirm-Action "Clear Windows Update history DataStore?") {
            Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
            Remove-FolderContents -Path $target -CleanerId 'system.update_history'
            Start-Service wuauserv -ErrorAction SilentlyContinue
        }
    } else { $script:Stats.BytesAnalyzed += Get-FolderSize $target }
}

Register-Cleaner -Id 'system.installer_cache' -Name 'Windows Installer Patch Cache' -Category 'System' -RequiresAdmin $true -Risk 'Moderate' -Description 'Redundant MSI patch cache (uninstall/repair may fail for some apps)' -Fn {
    $t = 'C:\Windows\Installer\$PatchCache$'
    if (Test-Path $t) { Remove-FolderContents -Path $t -CleanerId 'system.installer_cache' }
}

Register-Cleaner -Id 'system.component_store' -Name 'Component Store (WinSxS)' -Category 'System' -RequiresAdmin $true -Risk 'Safe' -Description 'DISM StartComponentCleanup + ResetBase' -Fn {
    if ($script:IsAnalyze) {
        Write-Log '  Running DISM /AnalyzeComponentStore...' -Level INFO
        dism.exe /online /cleanup-image /analyzecomponentstore 2>&1 | Where-Object { $_ -match 'Reclaimable|Component Store Size' } | ForEach-Object { Write-Log "  $_" -Level SIZE }
        return
    }
    if (Confirm-Action 'Run DISM StartComponentCleanup /ResetBase? (cannot undo feature rollback after this)') {
        Write-Log '  Running DISM (may take several minutes)...'
        dism.exe /online /cleanup-image /startcomponentcleanup /resetbase /quiet 2>&1 | ForEach-Object { Write-Log "  $_" }
    }
}

Register-Cleaner -Id 'system.cleanmgr' -Name 'Windows Built-in Disk Cleanup' -Category 'System' -RequiresAdmin $true -Risk 'Safe' -Description 'Runs cleanmgr with all categories enabled' -Fn {
    if ($script:IsAnalyze) { Write-Log '  Would run cleanmgr /sagerun:64'; return }
    # Pre-enable all cleanmgr categories
    $rp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    Get-ChildItem $rp -ErrorAction SilentlyContinue | ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name StateFlags0064 -Value 2 -ErrorAction SilentlyContinue
    }
    Start-Process cleanmgr.exe -ArgumentList '/sagerun:64' -Wait -NoNewWindow -ErrorAction SilentlyContinue
}

Register-Cleaner -Id 'system.search_index' -Name 'Windows Search Index' -Category 'System' -RequiresAdmin $true -Risk 'Moderate' -Description 'Deletes and rebuilds the search index database' -Fn {
    $dbPath = 'C:\ProgramData\Microsoft\Search\Data\Applications\Windows'
    $sz = Get-FolderSize $dbPath
    Write-Log "  Index size: $(Format-Bytes $sz)" -Level SIZE
    if ($script:IsAnalyze) { $script:Stats.BytesAnalyzed += $sz; return }
    if (Confirm-Action "Delete Windows Search index ($(Format-Bytes $sz))? Rebuilds automatically.") {
        Stop-Service WSearch -Force -ErrorAction SilentlyContinue
        Start-Sleep 2
        Remove-FolderContents -Path $dbPath -CleanerId 'system.search_index'
        Start-Service WSearch -ErrorAction SilentlyContinue
    }
}

Register-Cleaner -Id 'system.event_logs' -Name 'Event Logs' -Category 'System' -RequiresAdmin $true -Risk 'Moderate' -Description 'Clears all Windows event logs' -Fn {
    $logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.RecordCount -gt 0 }
    $total = ($logs | Measure-Object FileSize -Sum).Sum
    Write-Log "  Total event log data: $(Format-Bytes $total)  ($($logs.Count) logs with records)" -Level SIZE
    if ($script:IsAnalyze) { $script:Stats.BytesAnalyzed += $total; return }
    if (Confirm-Action "Clear all $($logs.Count) event logs?") {
        foreach ($log in $logs) {
            try { wevtutil cl "$($log.LogName)" 2>$null }
            catch { Write-Log "  Could not clear $($log.LogName)" -Level WARN }
        }
    }
}

Register-Cleaner -Id 'system.iis_logs' -Name 'IIS Logs (>30 days)' -Category 'System' -Risk 'Safe' -Description 'Internet Information Services log files older than 30 days' -Fn {
    $iisRoot = 'C:\inetpub\logs\LogFiles'
    if (-not (Test-Path $iisRoot)) { return }
    Get-ChildItem -Path $iisRoot -Filter '*.log' -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        ForEach-Object { Remove-ItemSafe $_.FullName -CleanerId 'system.iis_logs' }
}

Register-Cleaner -Id 'system.etl_traces' -Name 'ETW/ETL Trace Files' -Category 'System' -Risk 'Safe' -Description 'Event Trace Log files older than 7 days' -Fn {
    $roots = @('C:\Windows\System32\LogFiles','C:\Windows\Logs',"$env:ProgramData\Microsoft\Diagnosis\ETLLogs")
    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { continue }
        Get-ChildItem -Path $r -Filter '*.etl' -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
            ForEach-Object { Remove-ItemSafe $_.FullName -CleanerId 'system.etl_traces' }
    }
}

Register-Cleaner -Id 'system.cbs_logs' -Name 'CBS / DISM / Setup Logs' -Category 'System' -RequiresAdmin $true -Risk 'Safe' -Description 'Component Based Servicing and setup logs' -Fn {
    $paths = @(
        'C:\Windows\Logs\CBS',
        'C:\Windows\Logs\DISM',
        'C:\Windows\Logs\MoSetup',
        'C:\Windows\SoftwareDistribution\DataStore\Logs',
        'C:\Windows\Panther'
    )
    foreach ($p in $paths) {
        Get-ChildItem -Path $p -Include '*.log','*.etl' -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
            ForEach-Object { Remove-ItemSafe $_.FullName -CleanerId 'system.cbs_logs' }
    }
}

# ═══════════════════════════════════════════════════════════════
# ███  PRIVACY CLEANERS  (BleachBit's signature feature)
# ═══════════════════════════════════════════════════════════════

Register-Cleaner -Id 'privacy.recent_docs' -Name 'Recent Documents' -Category 'Privacy' -Risk 'Safe' -Description 'Recent files list in Explorer and Office MRU' -Fn {
    $paths = @(
        "$env:APPDATA\Microsoft\Windows\Recent",
        "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations",
        "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations"
    )
    foreach ($p in $paths) { Remove-FolderContents -Path $p -CleanerId 'privacy.recent_docs' }
    # Office MRU (Word, Excel, PowerPoint)
    $officeMRU = @(
        'HKCU:\SOFTWARE\Microsoft\Office\16.0\Word\File MRU',
        'HKCU:\SOFTWARE\Microsoft\Office\16.0\Excel\File MRU',
        'HKCU:\SOFTWARE\Microsoft\Office\16.0\PowerPoint\File MRU',
        'HKCU:\SOFTWARE\Microsoft\Office\15.0\Word\File MRU',
        'HKCU:\SOFTWARE\Microsoft\Office\15.0\Excel\File MRU'
    )
    foreach ($rp in $officeMRU) {
        if (Test-Path $rp) {
            if (-not $script:IsAnalyze) {
                Remove-Item -Path $rp -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "  Cleared Office MRU: $rp" -Level OK
            } else { Write-Log "  ANALYZE: Office MRU $rp" -Level SIZE }
        }
    }
}

Register-Cleaner -Id 'privacy.jump_lists' -Name 'Jump Lists' -Category 'Privacy' -Risk 'Safe' -Description 'Taskbar and Start Menu jump list history' -Fn {
    $paths = @(
        "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations",
        "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations"
    )
    foreach ($p in $paths) { Remove-FolderContents -Path $p -CleanerId 'privacy.jump_lists' }
}

Register-Cleaner -Id 'privacy.clipboard' -Name 'Clipboard' -Category 'Privacy' -Risk 'Safe' -Description 'Current clipboard contents and clipboard history' -Fn {
    if ($script:IsAnalyze) { Write-Log '  ANALYZE: Would clear clipboard and clipboard history'; return }
    # Clear current clipboard
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.Clipboard]::Clear()
    # Clear clipboard history (Win10+)
    $histPath = "$env:LOCALAPPDATA\Microsoft\Windows\Clipboard"
    if (Test-Path $histPath) { Remove-FolderContents -Path $histPath -CleanerId 'privacy.clipboard' }
    Write-Log '  Clipboard cleared' -Level OK
}

Register-Cleaner -Id 'privacy.run_history' -Name 'Run Dialog History' -Category 'Privacy' -Risk 'Safe' -Description 'Commands typed into the Win+R Run dialog' -Fn {
    $rp = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'
    if (Test-Path $rp) {
        if ($script:IsAnalyze) {
            $entries = (Get-ItemProperty $rp -ErrorAction SilentlyContinue).PSObject.Properties |
                Where-Object { $_.Name -match '^[a-z]$' }
            Write-Log "  Run history entries: $($entries.Count)" -Level SIZE
        } else {
            Get-ItemProperty $rp -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSObject |
                ForEach-Object { $_.Properties } |
                Where-Object { $_.Name -match '^[a-z]$' -or $_.Name -eq 'MRUList' } |
                ForEach-Object { Remove-ItemProperty -Path $rp -Name $_.Name -ErrorAction SilentlyContinue }
            Write-Log '  Run history cleared' -Level OK
        }
    }
}

Register-Cleaner -Id 'privacy.search_history' -Name 'Windows Search & Cortana History' -Category 'Privacy' -Risk 'Safe' -Description 'Start menu search terms and Cortana query history' -Fn {
    $paths = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Search_cw5n1h2txyewy\LocalState\AppIconCache",
        "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Cortana_cw5n1h2txyewy\LocalState",
        "$env:LOCALAPPDATA\Microsoft\Windows\ConnectedSearch\History"
    )
    foreach ($p in $paths) { Remove-FolderContents -Path $p -CleanerId 'privacy.search_history' }
    # Registry search history
    $regPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery'
    if (Test-Path $regPath) {
        if (-not $script:IsAnalyze) { Remove-Item $regPath -Recurse -Force -ErrorAction SilentlyContinue }
        else { Write-Log '  ANALYZE: WordWheelQuery (Explorer search history)' -Level SIZE }
    }
}

Register-Cleaner -Id 'privacy.typed_urls' -Name 'Typed URLs (Address Bar History)' -Category 'Privacy' -Risk 'Safe' -Description 'URLs typed in IE/Edge address bars' -Fn {
    $rp = 'HKCU:\SOFTWARE\Microsoft\Internet Explorer\TypedURLs'
    if (Test-Path $rp) {
        if (-not $script:IsAnalyze) { Remove-Item $rp -Recurse -Force -ErrorAction SilentlyContinue }
        else { Write-Log '  ANALYZE: IE TypedURLs' -Level SIZE }
    }
}

Register-Cleaner -Id 'privacy.shell_bags' -Name 'Shell Bags (Folder View History)' -Category 'Privacy' -Risk 'Safe' -Description 'Records of folders ever opened in Explorer' -Fn {
    $paths = @(
        'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags',
        'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU',
        'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Bags',
        'HKCU:\SOFTWARE\Microsoft\Windows\Shell\BagMRU'
    )
    foreach ($rp in $paths) {
        if (Test-Path $rp) {
            if (-not $script:IsAnalyze) { Remove-Item $rp -Recurse -Force -ErrorAction SilentlyContinue; Write-Log "  Cleared $rp" -Level OK }
            else { Write-Log "  ANALYZE: $rp" -Level SIZE }
        }
    }
}

Register-Cleaner -Id 'privacy.mui_cache' -Name 'MUICache (App Name History)' -Category 'Privacy' -Risk 'Safe' -Description 'Registry record of every executable ever run' -Fn {
    $rp = 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
    if (-not (Test-Path $rp)) { return }
    $props = Get-ItemProperty $rp -ErrorAction SilentlyContinue
    $stale = $props.PSObject.Properties | Where-Object {
        $_.Name -notin ('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider') -and
        -not (Test-Path ($_.Name -replace '\.FriendlyAppName$','') -ErrorAction SilentlyContinue)
    }
    Write-Log "  Stale MUICache entries: $($stale.Count)" -Level SIZE
    if (-not $script:IsAnalyze) {
        foreach ($s in $stale) {
            Remove-ItemProperty -Path $rp -Name $s.Name -ErrorAction SilentlyContinue
        }
        Write-Log "  Removed $($stale.Count) stale MUICache entries" -Level OK
    }
}

Register-Cleaner -Id 'privacy.user_assist' -Name 'UserAssist (Program Usage Tracking)' -Category 'Privacy' -Risk 'Safe' -Description 'Tracks how often and when you launch programs' -Fn {
    $rp = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
    if (-not (Test-Path $rp)) { return }
    if (-not $script:IsAnalyze) {
        if (Confirm-Action 'Clear UserAssist program tracking data?') {
            Get-ChildItem "$rp\*\Count" -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue }
            Write-Log '  UserAssist cleared' -Level OK
        }
    } else { Write-Log '  ANALYZE: UserAssist registry hive' -Level SIZE }
}

Register-Cleaner -Id 'privacy.network_passwords' -Name 'Saved Network Passwords' -Category 'Privacy' -Risk 'Moderate' -Description 'Wi-Fi and network credentials stored by Windows' -Fn {
    if ($script:IsAnalyze) {
        $creds = cmdkey /list 2>$null | Where-Object { $_ -match 'Target' }
        Write-Log "  Stored credentials: $($creds.Count)" -Level SIZE
        return
    }
    if (Confirm-Action 'Delete all saved Windows credentials? (Wi-Fi passwords, mapped drives, etc.)') {
        cmdkey /list 2>$null | Where-Object { $_ -match 'Target:\s+(.+)' } | ForEach-Object {
            $target = ($_ -replace '.*Target:\s+','').Trim()
            cmdkey /delete:$target 2>$null | Out-Null
        }
        Write-Log '  Saved credentials cleared' -Level OK
    }
}

Register-Cleaner -Id 'privacy.lnk_files' -Name 'Desktop / Recent Shortcuts (.lnk)' -Category 'Privacy' -Risk 'Safe' -Description 'Recently opened file shortcuts generated by Windows' -Fn {
    $paths = @("$env:APPDATA\Microsoft\Windows\Recent")
    foreach ($p in $paths) {
        Get-ChildItem $p -Filter '*.lnk' -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-ItemSafe $_.FullName -CleanerId 'privacy.lnk_files' }
    }
}

Register-Cleaner -Id 'privacy.notifications' -Name 'Action Center / Toast Notification History' -Category 'Privacy' -Risk 'Safe' -Description 'Notification history stored in the Action Center' -Fn {
    $pkgPath = "$env:LOCALAPPDATA\Microsoft\Windows\ActionCenterCache"
    Remove-FolderContents -Path $pkgPath -CleanerId 'privacy.notifications'
    # wpndatabase
    $wpn = "$env:LOCALAPPDATA\Microsoft\Windows\Notifications"
    Remove-FolderContents -Path $wpn -CleanerId 'privacy.notifications'
}

Register-Cleaner -Id 'privacy.activity_history' -Name 'Timeline / Activity History' -Category 'Privacy' -Risk 'Safe' -Description 'Windows Timeline activity database' -Fn {
    $db = "$env:LOCALAPPDATA\ConnectedDevicesPlatform"
    Remove-FolderContents -Path $db -CleanerId 'privacy.activity_history'
    # Registry
    $rp = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ActivityDataModel'
    if (Test-Path $rp) {
        if (-not $script:IsAnalyze) { Remove-Item $rp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Register-Cleaner -Id 'privacy.location_history' -Name 'Location History' -Category 'Privacy' -Risk 'Safe' -Description 'GPS/location query history' -Fn {
    $rp = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
    if (Test-Path $rp) {
        if (-not $script:IsAnalyze) { Remove-Item "$rp\NonPackaged" -Recurse -Force -ErrorAction SilentlyContinue }
        else { Write-Log '  ANALYZE: Location history registry entries' -Level SIZE }
    }
}

Register-Cleaner -Id 'privacy.diagnostic_data' -Name 'Diagnostic & Telemetry Data' -Category 'Privacy' -Risk 'Safe' -Description 'Collected diagnostics pending upload to Microsoft' -Fn {
    $paths = @(
        "$env:ProgramData\Microsoft\Diagnosis",
        "$env:LOCALAPPDATA\Microsoft\Windows\DiagnosticLog",
        'C:\Windows\System32\sru',
        "$env:ProgramData\Microsoft\Windows\SystemData"
    )
    foreach ($p in $paths) { Remove-FolderContents -Path $p -CleanerId 'privacy.diagnostic_data' }
}

# ═══════════════════════════════════════════════════════════════
# ███  BROWSER CLEANERS
# ═══════════════════════════════════════════════════════════════

function Clear-ChromiumProfile {
    param([string]$Browser, [string]$ProfilePath, [string]$CleanerId)
    if (-not (Test-Path $ProfilePath)) { return }
    $items = [ordered]@{
        'Cache'                           = $true
        'Cache2'                          = $true
        'Code Cache'                      = $true
        'GPUCache'                        = $true
        'ShaderCache'                     = $true
        'Media Cache'                     = $true
        'Application Cache'               = $true
        'Service Worker\CacheStorage'     = $true
        'Service Worker\ScriptCache'      = $true
        'IndexedDB'                       = $true
        'databases'                       = $true
        'Local Storage\leveldb'           = $true
        'Session Storage'                 = $true
        'Sessions'                        = $true
        'Network Action Predictor'        = $false  # history-adjacent
        'Visited Links'                   = $false
        'History'                         = $false
        'History-journal'                 = $false
        'Cookies'                         = $false
        'Cookies-journal'                 = $false
        'Login Data'                      = $false  # passwords
        'Login Data For Account'          = $false
        'Web Data'                        = $false  # form data / autofill
        'Current Session'                 = $true
        'Current Tabs'                    = $true
        'Last Session'                    = $true
        'Last Tabs'                       = $true
        'Extension State'                 = $false
    }
    $profileName = Split-Path $ProfilePath -Leaf
    foreach ($sub in $items.Keys) {
        $fp = Join-Path $ProfilePath $sub
        if (-not (Test-Path $fp -ErrorAction SilentlyContinue)) { continue }
        $isSafe = $items[$sub]
        if ($isSafe) {
            if ((Get-Item $fp -Force -ErrorAction SilentlyContinue).PSIsContainer) {
                Remove-FolderContents -Path $fp -CleanerId $CleanerId
            } else { Remove-ItemSafe $fp -CleanerId $CleanerId }
        } else {
            $sz = Get-ItemSize $fp
            if ($script:IsAnalyze) {
                Write-Log "  ANALYZE [$profileName] ${sub}: $(Format-Bytes $sz)" -Level SIZE
                $script:Stats.BytesAnalyzed += $sz
            } elseif (Confirm-Action "Delete [$Browser/$profileName] $sub ($(Format-Bytes $sz))?") {
                Remove-ItemSafe $fp -CleanerId $CleanerId
            }
        }
    }
}

function Get-ChromiumProfiles ([string]$BasePath) {
    $profiles = @()
    foreach ($name in @('Default','Guest Profile')) {
        $p = Join-Path $BasePath $name
        if (Test-Path $p) { $profiles += $p }
    }
    if (Test-Path $BasePath) {
        $profiles += Get-ChildItem $BasePath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^Profile \d+$' } | ForEach-Object { $_.FullName }
    }
    return $profiles
}

$chromiumBrowsers = @(
    @{ Id='browser.chrome';   Name='Google Chrome';    Path="$env:LOCALAPPDATA\Google\Chrome\User Data" },
    @{ Id='browser.edge';     Name='Microsoft Edge';   Path="$env:LOCALAPPDATA\Microsoft\Edge\User Data" },
    @{ Id='browser.brave';    Name='Brave';            Path="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" },
    @{ Id='browser.opera';    Name='Opera';            Path="$env:APPDATA\Opera Software\Opera Stable" },
    @{ Id='browser.vivaldi';  Name='Vivaldi';          Path="$env:LOCALAPPDATA\Vivaldi\User Data" },
    @{ Id='browser.chromium'; Name='Chromium';         Path="$env:LOCALAPPDATA\Chromium\User Data" },
    @{ Id='browser.operagx';  Name='Opera GX';         Path="$env:APPDATA\Opera Software\Opera GX Stable" },
    @{ Id='browser.arc';      Name='Arc';              Path="$env:LOCALAPPDATA\Arc\User Data" }
)

foreach ($b in $chromiumBrowsers) {
    $bId   = $b.Id
    $bName = $b.Name
    $bPath = $b.Path
    Register-Cleaner -Id $bId -Name "$bName Cache & Residue" -Category 'Browser' -Risk 'Safe' -Description "Cache, sessions, IndexedDB for $bName (all profiles)" -Fn ([scriptblock]::Create(@"
    `$basePath = '$bPath'
    if (-not (Test-Path `$basePath)) { Write-Log '  $bName not installed'; return }
    foreach (`$profile in (Get-ChromiumProfiles `$basePath)) {
        Clear-ChromiumProfile -Browser '$bName' -ProfilePath `$profile -CleanerId '$bId'
    }
    # GPU/Shader cache outside profiles
    foreach (`$sub in @('GrShaderCache','ShaderCache')) {
        `$p = Join-Path `$basePath `$sub
        if (Test-Path `$p) { Remove-FolderContents -Path `$p -CleanerId '$bId' }
    }
"@))
}

Register-Cleaner -Id 'browser.firefox' -Name 'Firefox Cache & Residue' -Category 'Browser' -Risk 'Safe' -Description 'Firefox cache, session files, thumbnails, crash reports (all profiles)' -Fn {
    $ffRoot = "$env:APPDATA\Mozilla\Firefox\Profiles"
    $ffCache= "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    foreach ($root in @($ffRoot,$ffCache)) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $p = $_.FullName
            foreach ($sub in @('cache2','startupCache','thumbnails','crashes\submitted',
                               'crashes\pending','datareporting','healthreport',
                               'storage\permanent\chrome\idb','storage\temporary')) {
                $fp = Join-Path $p $sub
                if (Test-Path $fp) { Remove-FolderContents -Path $fp -CleanerId 'browser.firefox' }
            }
            # sessionstore backups
            Get-ChildItem $p -Filter 'sessionstore-backups' -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-FolderContents $_.FullName -CleanerId 'browser.firefox' }
        }
    }
}

Register-Cleaner -Id 'browser.tor' -Name 'Tor Browser Cache' -Category 'Browser' -Risk 'Safe' -Description 'Tor Browser cached data' -Fn {
    $torPaths = @(
        "$env:APPDATA\tor project\tor browser",
        "$env:LOCALAPPDATA\tor project\tor browser",
        "$env:USERPROFILE\Desktop\Tor Browser\Browser\TorBrowser\Data"
    )
    foreach ($p in $torPaths) {
        if (-not (Test-Path $p)) { continue }
        Get-ChildItem $p -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*profile*' } |
            ForEach-Object {
                foreach ($sub in @('cache2','startupCache','thumbnails')) {
                    $fp = Join-Path $_.FullName $sub
                    if (Test-Path $fp) { Remove-FolderContents $fp -CleanerId 'browser.tor' }
                }
            }
    }
}

# ═══════════════════════════════════════════════════════════════
# ███  APPLICATION CLEANERS
# ═══════════════════════════════════════════════════════════════

# ─── Communication ───────────────────────────────────────────
Register-Cleaner -Id 'app.teams' -Name 'Microsoft Teams Cache' -Category 'Applications' -Risk 'Safe' -Description 'Teams classic and new Teams cached data' -Fn {
    $bases = @(
        "$env:APPDATA\Microsoft\Teams",
        "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"
    )
    foreach ($base in $bases) {
        if (-not (Test-Path $base)) { continue }
        foreach ($sub in @('Cache','blob_storage','databases','GPUCache','IndexedDB',
                           'Local Storage','Service Worker','tmp','logs')) {
            $fp = Join-Path $base $sub
            if (Test-Path $fp) { Remove-FolderContents $fp -CleanerId 'app.teams' }
        }
    }
}

Register-Cleaner -Id 'app.slack' -Name 'Slack Cache' -Category 'Applications' -Risk 'Safe' -Description 'Slack Electron cache and logs' -Fn {
    $base = "$env:APPDATA\Slack"
    if (-not (Test-Path $base)) { return }
    foreach ($sub in @('Cache','Code Cache','GPUCache','Service Worker\CacheStorage','logs')) {
        $fp = Join-Path $base $sub
        if (Test-Path $fp) { Remove-FolderContents $fp -CleanerId 'app.slack' }
    }
}

Register-Cleaner -Id 'app.discord' -Name 'Discord Cache' -Category 'Applications' -Risk 'Safe' -Description 'Discord Electron cache' -Fn {
    $base = "$env:APPDATA\discord"
    if (-not (Test-Path $base)) { return }
    foreach ($sub in @('Cache','Code Cache','GPUCache','blob_storage','Local Storage\leveldb')) {
        $fp = Join-Path $base $sub
        if (Test-Path $fp) { Remove-FolderContents $fp -CleanerId 'app.discord' }
    }
    # Also check for discord Canary / PTB
    foreach ($variant in @('discordcanary','discordptb')) {
        $vb = "$env:APPDATA\$variant"
        if (Test-Path $vb) {
            foreach ($sub in @('Cache','Code Cache','GPUCache')) {
                $fp = Join-Path $vb $sub
                if (Test-Path $fp) { Remove-FolderContents $fp -CleanerId 'app.discord' }
            }
        }
    }
}

Register-Cleaner -Id 'app.zoom' -Name 'Zoom Cache & Logs' -Category 'Applications' -Risk 'Safe' -Description 'Zoom temporary files, logs, recordings cache' -Fn {
    $paths = @("$env:APPDATA\Zoom\data","$env:APPDATA\Zoom\logs","$env:LOCALAPPDATA\Zoom\Logs")
    foreach ($p in $paths) { Remove-FolderContents -Path $p -CleanerId 'app.zoom' }
}

Register-Cleaner -Id 'app.skype' -Name 'Skype Cache' -Category 'Applications' -Risk 'Safe' -Description 'Skype for Desktop cache' -Fn {
    $paths = @(
        "$env:APPDATA\Microsoft\Skype",
        "$env:LOCALAPPDATA\Packages\Microsoft.SkypeApp_kzf8qxf38zg5c\LocalCache"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            foreach ($sub in @('Cache','media_messaging')) {
                $fp = Join-Path $p $sub
                if (Test-Path $fp) { Remove-FolderContents $fp -CleanerId 'app.skype' }
            }
        }
    }
}

Register-Cleaner -Id 'app.telegram' -Name 'Telegram Cache' -Category 'Applications' -Risk 'Safe' -Description 'Telegram Desktop media cache' -Fn {
    $paths = @(
        "$env:APPDATA\Telegram Desktop\tdata\user_data",
        "$env:APPDATA\Telegram Desktop\tdata\temp"
    )
    foreach ($p in $paths) { Remove-FolderContents $p -CleanerId 'app.telegram' }
}

Register-Cleaner -Id 'app.whatsapp' -Name 'WhatsApp Cache' -Category 'Applications' -Risk 'Safe' -Description 'WhatsApp Desktop cache' -Fn {
    $base = "$env:APPDATA\WhatsApp"
    if (-not (Test-Path $base)) { return }
    foreach ($sub in @('Cache','Code Cache','GPUCache','logs')) {
        $fp = Join-Path $base $sub
        if (Test-Path $fp) { Remove-FolderContents $fp -CleanerId 'app.whatsapp' }
    }
}

# ─── Media & Entertainment ───────────────────────────────────
Register-Cleaner -Id 'app.spotify' -Name 'Spotify Cache' -Category 'Applications' -Risk 'Safe' -Description 'Spotify audio cache (downloaded streams)' -Fn {
    $paths = @(
        "$env:LOCALAPPDATA\Spotify\Storage",
        "$env:LOCALAPPDATA\Packages\SpotifyAB.SpotifyMusic_zpdnekdrzrea0\LocalCache\Spotify\Data"
    )
    foreach ($p in $paths) { Remove-FolderContents $p -CleanerId 'app.spotify' }
}

Register-Cleaner -Id 'app.steam' -Name 'Steam Cache & Residue' -Category 'Applications' -Risk 'Safe' -Description 'Steam HTML cache, appcache, and incomplete downloads' -Fn {
    $steamRoot = 'C:\Program Files (x86)\Steam'
    if (-not (Test-Path $steamRoot)) {
        # Try to find Steam from registry
        $steamPath = Get-ItemProperty 'HKCU:\SOFTWARE\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue
        if ($steamPath) { $steamRoot = $steamPath.SteamPath }
    }
    if (-not (Test-Path $steamRoot)) { Write-Log '  Steam not found'; return }
    $safePaths = @(
        "$steamRoot\appcache\httpcache",
        "$steamRoot\appcache\stats",
        "$env:LOCALAPPDATA\Steam\htmlcache"
    )
    foreach ($p in $safePaths) { Remove-FolderContents $p -CleanerId 'app.steam' }
    # Incomplete downloads (0-byte chunks)
    $dlPath = "$steamRoot\steamapps\downloading"
    if (Test-Path $dlPath) {
        $sz = Get-FolderSize $dlPath
        Write-Log "  Incomplete downloads: $(Format-Bytes $sz)" -Level SIZE
        if (-not $script:IsAnalyze) {
            if (Confirm-Action "Delete incomplete Steam downloads ($(Format-Bytes $sz))?") {
                Remove-FolderContents $dlPath -CleanerId 'app.steam'
            }
        } else { $script:Stats.BytesAnalyzed += $sz }
    }
    # Shader cache
    $shaderPath = "$steamRoot\steamapps\shadercache"
    if (Test-Path $shaderPath) {
        $sz = Get-FolderSize $shaderPath
        Write-Log "  Shader cache: $(Format-Bytes $sz) (games will re-compile shaders)" -Level SIZE
        if (-not $script:IsAnalyze) {
            if (Confirm-Action "Clear Steam shader cache ($(Format-Bytes $sz))?") {
                Remove-FolderContents $shaderPath -CleanerId 'app.steam'
            }
        } else { $script:Stats.BytesAnalyzed += $sz }
    }
}

Register-Cleaner -Id 'app.epicgames' -Name 'Epic Games Launcher Cache' -Category 'Applications' -Risk 'Safe' -Description 'Epic Games Launcher web cache and logs' -Fn {
    $paths = @(
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Logs"
    )
    foreach ($p in $paths) { Remove-FolderContents $p -CleanerId 'app.epicgames' }
}

Register-Cleaner -Id 'app.battlenet' -Name 'Battle.net Cache' -Category 'Applications' -Risk 'Safe' -Description 'Battle.net launcher cache' -Fn {
    $paths = @(
        "$env:LOCALAPPDATA\Battle.net\Cache",
        "$env:LOCALAPPDATA\Battle.net\Logs"
    )
    foreach ($p in $paths) { Remove-FolderContents $p -CleanerId 'app.battlenet' }
}

Register-Cleaner -Id 'app.vlc' -Name 'VLC Cache' -Category 'Applications' -Risk 'Safe' -Description 'VLC media player cache and thumbnail files' -Fn {
    $paths = @(
        "$env:APPDATA\vlc\cache",
        "$env:APPDATA\vlc\art"
    )
    foreach ($p in $paths) { Remove-FolderContents $p -CleanerId 'app.vlc' }
}

Register-Cleaner -Id 'app.obs' -Name 'OBS Studio Logs' -Category 'Applications' -Risk 'Safe' -Description 'OBS log files older than 14 days' -Fn {
    $logPath = "$env:APPDATA\obs-studio\logs"
    if (-not (Test-Path $logPath)) { return }
    Get-ChildItem $logPath -Filter '*.txt' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
        ForEach-Object { Remove-ItemSafe $_.FullName -CleanerId 'app.obs' }
}

# ─── Productivity ─────────────────────────────────────────────
Register-Cleaner -Id 'app.outlook' -Name 'Outlook Cache & Temp Attachments' -Category 'Applications' -Risk 'Safe' -Description 'Outlook secure temp folder and RoamCache' -Fn {
    $reg = Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Security' -Name OutlookSecureTempFolder -ErrorAction SilentlyContinue
    if ($reg) {
        Remove-FolderContents $reg.OutlookSecureTempFolder -CleanerId 'app.outlook'
    }
    $paths = @("$env:LOCALAPPDATA\Microsoft\Outlook","$env:TEMP\Outlook Temp")
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { continue }
        Get-ChildItem $p -Include '*.tmp','~*' -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-ItemSafe $_.FullName -CleanerId 'app.outlook' }
    }
}

Register-Cleaner -Id 'app.onedrive' -Name 'OneDrive Logs & Cache' -Category 'Applications' -Risk 'Safe' -Description 'OneDrive sync logs and update cache' -Fn {
    $paths = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive\logs",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\Setup\Logs",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\Update"
    )
    foreach ($p in $paths) { Remove-FolderContents $p -CleanerId 'app.onedrive' }
}

Register-Cleaner -Id 'app.notion' -Name 'Notion Cache' -Category 'Applications' -Risk 'Safe' -Description 'Notion desktop Electron cache' -Fn {
    $base = "$env:APPDATA\Notion"
    if (-not (Test-Path $base)) { return }
    foreach ($sub in @('Cache','Code Cache','GPUCache')) {
        $fp = Join-Path $base $sub
        if (Test-Path $fp) { Remove-FolderContents $fp -CleanerId 'app.notion' }
    }
}

Register-Cleaner -Id 'app.figma' -Name 'Figma Cache' -Category 'Applications' -Risk 'Safe' -Description 'Figma desktop cache' -Fn {
    $base = "$env:APPDATA\Figma"
    if (-not (Test-Path $base)) { return }
    foreach ($sub in @('Cache','Code Cache','GPUCache')) {
        $fp = Join-Path $base $sub
        if (Test-Path $fp) { Remove-FolderContents $fp -CleanerId 'app.figma' }
    }
}

# ─── Dev Tools ────────────────────────────────────────────────
Register-Cleaner -Id 'dev.npm' -Name 'npm / yarn / pnpm Cache' -Category 'DevTools' -Risk 'Safe' -Description 'Node package manager caches' -Fn {
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        $npmCache = npm config get cache 2>$null
        if ($npmCache -and (Test-Path $npmCache)) {
            Write-Log "  npm cache: $(Format-Bytes (Get-FolderSize $npmCache))" -Level SIZE
            if (-not $script:IsAnalyze) { npm cache clean --force 2>&1 | Out-Null }
            else { $script:Stats.BytesAnalyzed += Get-FolderSize $npmCache }
        }
    }
    foreach ($p in @("$env:LOCALAPPDATA\Yarn\Cache","$env:LOCALAPPDATA\node-gyp")) {
        Remove-FolderContents $p -CleanerId 'dev.npm'
    }
    if (Get-Command pnpm -ErrorAction SilentlyContinue) {
        if (-not $script:IsAnalyze) { pnpm store prune 2>&1 | Out-Null }
    }
}

Register-Cleaner -Id 'dev.pip' -Name 'Python pip Cache' -Category 'DevTools' -Risk 'Safe' -Description 'pip wheel and HTTP cache' -Fn {
    foreach ($p in @("$env:LOCALAPPDATA\pip\Cache","$env:APPDATA\pip\Cache","$env:USERPROFILE\.cache\pip")) {
        Remove-FolderContents $p -CleanerId 'dev.pip'
    }
    if (Get-Command pip -ErrorAction SilentlyContinue) {
        if (-not $script:IsAnalyze) { pip cache purge 2>&1 | Out-Null }
    }
}

Register-Cleaner -Id 'dev.nuget' -Name 'NuGet / .NET Cache' -Category 'DevTools' -Risk 'Safe' -Description 'NuGet package cache and dotnet tools' -Fn {
    $paths = @("$env:USERPROFILE\.nuget\packages","$env:LOCALAPPDATA\NuGet\Cache","$env:TEMP\NuGetScratch")
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $sz = Get-FolderSize $p
            Write-Log "  $p : $(Format-Bytes $sz)" -Level SIZE
            if (-not $script:IsAnalyze -and $sz -gt 100MB) { Remove-FolderContents $p -CleanerId 'dev.nuget' }
            else { $script:Stats.BytesAnalyzed += $sz }
        }
    }
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        if (-not $script:IsAnalyze) { dotnet nuget locals all --clear 2>&1 | Out-Null }
    }
}

Register-Cleaner -Id 'dev.gradle' -Name 'Gradle / Maven Cache' -Category 'DevTools' -Risk 'Safe' -Description 'Java build tool caches' -Fn {
    $paths = @(
        "$env:USERPROFILE\.gradle\caches",
        "$env:USERPROFILE\.gradle\wrapper\dists",
        "$env:USERPROFILE\.m2\repository"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $sz = Get-FolderSize $p
            Write-Log "  $p : $(Format-Bytes $sz)" -Level SIZE
            if ($script:IsAnalyze) { $script:Stats.BytesAnalyzed += $sz }
            elseif ($sz -gt 200MB) {
                if (Confirm-Action "Clear $p ($(Format-Bytes $sz))?") {
                    Remove-FolderContents $p -CleanerId 'dev.gradle'
                }
            }
        }
    }
}

Register-Cleaner -Id 'dev.vscode' -Name 'VS Code Cache' -Category 'DevTools' -Risk 'Safe' -Description 'VS Code extensions, logs, cached data' -Fn {
    $paths = @(
        "$env:APPDATA\Code\CachedData",
        "$env:APPDATA\Code\Cache",
        "$env:APPDATA\Code\CachedExtensionVSIXs",
        "$env:APPDATA\Code\Code Cache",
        "$env:APPDATA\Code\logs",
        "$env:APPDATA\Code - Insiders\Cache",
        "$env:APPDATA\Code - Insiders\logs"
    )
    foreach ($p in $paths) { Remove-FolderContents $p -CleanerId 'dev.vscode' }
}

Register-Cleaner -Id 'dev.visualstudio' -Name 'Visual Studio Cache' -Category 'DevTools' -Risk 'Safe' -Description 'Visual Studio component model cache, temp, activity logs' -Fn {
    $bases = @("$env:LOCALAPPDATA\Microsoft\VisualStudio","$env:APPDATA\Microsoft\VisualStudio")
    foreach ($base in $bases) {
        if (-not (Test-Path $base)) { continue }
        Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                foreach ($sub in @('ComponentModelCache','ActivityLog*','temp','log')) {
                    $fp = Join-Path $_.FullName $sub
                    if (Test-Path $fp) {
                        if ((Get-Item $fp).PSIsContainer) { Remove-FolderContents $fp -CleanerId 'dev.visualstudio' }
                        else { Remove-ItemSafe $fp -CleanerId 'dev.visualstudio' }
                    }
                }
            }
    }
}

Register-Cleaner -Id 'dev.jetbrains' -Name 'JetBrains IDE Caches' -Category 'DevTools' -Risk 'Safe' -Description 'IntelliJ, Rider, PyCharm, WebStorm, GoLand caches' -Fn {
    $base = "$env:APPDATA\JetBrains"
    if (-not (Test-Path $base)) { return }
    Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($sub in @('caches','system\caches','system\tmp','log','system\log')) {
            $fp = Join-Path $_.FullName $sub
            if (Test-Path $fp) { Remove-FolderContents $fp -CleanerId 'dev.jetbrains' }
        }
    }
    # LocalAppData JetBrains
    $lbBase = "$env:LOCALAPPDATA\JetBrains"
    if (Test-Path $lbBase) {
        Get-ChildItem $lbBase -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $fp = Join-Path $_.FullName 'caches'
            if (Test-Path $fp) { Remove-FolderContents $fp -CleanerId 'dev.jetbrains' }
        }
    }
}

Register-Cleaner -Id 'dev.docker' -Name 'Docker Cleanup' -Category 'DevTools' -Risk 'Moderate' -Description 'Dangling images, stopped containers, builder cache, unused volumes/networks' -Fn {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Log '  Docker CLI not found'; return }
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Log '  Docker daemon not running'; return }
    $dfOut = docker system df 2>&1
    $dfOut | ForEach-Object { Write-Log "  $_" -Level SIZE }
    if ($script:IsAnalyze) { return }
    if (Confirm-Action 'Prune dangling images?')     { docker image prune -f 2>&1 | ForEach-Object { Write-Log "  $_" } }
    if (Confirm-Action 'Prune stopped containers?')  { docker container prune -f 2>&1 | ForEach-Object { Write-Log "  $_" } }
    if (Confirm-Action 'Prune builder cache (all)?') { docker builder prune -a -f 2>&1 | ForEach-Object { Write-Log "  $_" } }
    if (Confirm-Action 'Prune unused volumes?')      { docker volume prune -f 2>&1 | ForEach-Object { Write-Log "  $_" } }
    if (Confirm-Action 'Prune unused networks?')     { docker network prune -f 2>&1 | ForEach-Object { Write-Log "  $_" } }
}

Register-Cleaner -Id 'dev.git_gc' -Name 'Git Repository GC' -Category 'DevTools' -Risk 'Safe' -Description 'Runs git gc --prune on detected local repositories' -Fn {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Log '  git not found'; return }
    $roots = @("$env:USERPROFILE\source","$env:USERPROFILE\repos","$env:USERPROFILE\projects",
               "$env:USERPROFILE\Documents","$env:USERPROFILE\Desktop","$env:USERPROFILE\code")
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem -Path $root -Filter '.git' -Hidden -Recurse -Directory -Depth 4 -ErrorAction SilentlyContinue |
            ForEach-Object {
                $repo = $_.Parent.FullName
                Write-Log "  git gc: $repo"
                if (-not $script:IsAnalyze) {
                    Push-Location $repo -ErrorAction SilentlyContinue
                    git gc --prune=now --quiet 2>&1 | ForEach-Object { Write-Log "    $_" }
                    Pop-Location
                }
            }
    }
}

Register-Cleaner -Id 'dev.choco' -Name 'Chocolatey Cache' -Category 'DevTools' -Risk 'Safe' -Description 'Chocolatey package download cache' -Fn {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { Write-Log '  Chocolatey not installed'; return }
    foreach ($p in @("$env:ChocolateyInstall\lib-bad","$env:TEMP\chocolatey")) {
        Remove-FolderContents $p -CleanerId 'dev.choco'
    }
    if (-not $script:IsAnalyze) { choco clean all --yes 2>&1 | Out-Null }
}

Register-Cleaner -Id 'dev.wsl' -Name 'WSL Distributions' -Category 'DevTools' -Risk 'Advanced' -Description 'Unregister unused WSL distros and compact VHDs' -Fn {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) { Write-Log '  WSL not found'; return }
    $dists = wsl --list --quiet 2>$null | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }
    Write-Log "  Installed WSL distros: $($dists -join ', ')"
    if (-not $script:IsAnalyze) {
        foreach ($d in $dists) {
            if (Confirm-Action "Unregister WSL distro '$d'? (permanent)") {
                wsl --unregister $d 2>&1 | Write-Log
            }
        }
        # Compact remaining VHDs
        Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter 'ext4.vhdx' -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object {
                Write-Log "  VHD: $($_.FullName) ($(Format-Bytes $_.Length))"
                if (Confirm-Action "Optimize-VHD $($_.Name)?") {
                    try { Optimize-VHD -Path $_.FullName -Mode Full -ErrorAction Stop; Write-Log '  Compacted' -Level OK }
                    catch { Write-Log '  Optimize-VHD failed (needs Hyper-V feature)' -Level WARN }
                }
            }
    } else {
        $vhdSize = (Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter 'ext4.vhdx' -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        if ($vhdSize) { Write-Log "  WSL VHD total: $(Format-Bytes $vhdSize)" -Level SIZE }
    }
}

Register-Cleaner -Id 'dev.ps_old_modules' -Name 'Duplicate PowerShell Module Versions' -Category 'DevTools' -Risk 'Safe' -Description 'Removes older versions when multiple versions of the same module are installed' -Fn {
    $paths = $env:PSModulePath -split ';'
    $groups = @{}
    foreach ($mp in $paths) {
        if (-not (Test-Path $mp)) { continue }
        Get-ChildItem $mp -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $n = $_.Name.ToLower()
            if (-not $groups[$n]) { $groups[$n] = @() }
            $groups[$n] += $_
        }
    }
    foreach ($n in $groups.Keys) {
        $mods = $groups[$n]
        if ($mods.Count -le 1) { continue }
        $sorted = $mods | Sort-Object { try{[version]($_.Name -replace '[^\d.]','')}catch{[version]'0.0'} } -Descending
        $oldest = $sorted | Select-Object -Skip 1
        foreach ($old in $oldest) {
            Write-Log "  Old module: $($old.FullName)"
            if (-not $script:IsAnalyze) {
                if (Confirm-Action "Remove old version $($old.FullName)?") { Remove-ItemSafe $old.FullName -Recurse -CleanerId 'dev.ps_old_modules' }
            } else { $script:Stats.BytesAnalyzed += Get-FolderSize $old.FullName }
        }
    }
}

# ─── Orphan Detection ─────────────────────────────────────────
Register-Cleaner -Id 'app.orphans' -Name 'Orphaned AppData (App Corpses)' -Category 'Applications' -Risk 'Moderate' -Description 'AppData folders for apps no longer installed' -Fn {
    # Build installed-app name set
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $installed = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($rp in $regPaths) {
        Get-ItemProperty $rp -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.DisplayName) { $null = $installed.Add($_.DisplayName.ToLower()) }
        }
    }
    $appDirs = @("$env:APPDATA","$env:LOCALAPPDATA")
    $orphans = @()
    foreach ($dir in $appDirs) {
        if (-not (Test-Path $dir)) { continue }
        Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $name = $_.Name.ToLower()
            # Exclude common non-app dirs
            if ($name -in ('microsoft','packages','temp','low','assembly','roaming','local')) { return }
            $match = $installed | Where-Object { $_ -like "*$name*" -or $name -like "*$_*" }
            if (-not $match) {
                $sz = Get-FolderSize $_.FullName
                if ($sz -gt 20MB) { $orphans += [pscustomobject]@{ Path=$_.FullName; Size=$sz } }
            }
        }
    }
    $totalOrphan = ($orphans | Measure-Object Size -Sum).Sum
    Write-Log "  Potential orphaned app folders: $($orphans.Count) ($(Format-Bytes $totalOrphan))" -Level SIZE
    $orphans | Sort-Object Size -Descending | ForEach-Object { Write-Log ("  {0,-14}  {1}" -f (Format-Bytes $_.Size), $_.Path) -Level SIZE }
    if ($script:IsAnalyze) { $script:Stats.BytesAnalyzed += $totalOrphan; return }
    if ($orphans.Count -gt 0 -and (Confirm-Action "Interactively review and delete $($orphans.Count) orphaned folders?")) {
        foreach ($o in ($orphans | Sort-Object Size -Descending)) {
            if (Confirm-Action "Delete $($o.Path) ($(Format-Bytes $o.Size))?") {
                Remove-ItemSafe $o.Path -Recurse -CleanerId 'app.orphans'
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════
# ███  DISK / REGISTRY / NETWORK
# ═══════════════════════════════════════════════════════════════

Register-Cleaner -Id 'disk.recycle_bin' -Name 'Recycle Bin' -Category 'Disk' -Risk 'Safe' -Description 'Empty the Recycle Bin for the current user' -Fn {
    if ($script:IsAnalyze) {
        try {
            $shell = New-Object -ComObject Shell.Application
            $rb = $shell.Namespace(10)
            $sz = ($rb.Items() | Measure-Object -Property Size -Sum).Sum
            Write-Log "  Recycle Bin: $(Format-Bytes $sz)" -Level SIZE
            $script:Stats.BytesAnalyzed += $sz
        } catch { Write-Log '  Could not measure Recycle Bin' -Level WARN }
        return
    }
    try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Log '  Recycle Bin emptied' -Level OK }
    catch { Write-Log "  Clear-RecycleBin failed: $_" -Level WARN }
}

Register-Cleaner -Id 'disk.large_files' -Name 'Large Files Report' -Category 'Disk' -Risk 'Safe' -Description 'Find top 100 files over 50 MB and export a CSV' -Fn {
    Write-Log '  Scanning for large files on C:\...'
    $report = Join-Path $script:LogDir ("large_files_$(Get-Date -Format yyyyMMdd_HHmmss).csv")
    $results = Get-ChildItem -Path 'C:\' -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 50MB } |
        Sort-Object Length -Descending | Select-Object -First 100 |
        Select-Object FullName,
            @{N='SizeMB';   E={[math]::Round($_.Length/1MB,2)}},
            @{N='Modified'; E={$_.LastWriteTime}},
            @{N='Ext';      E={$_.Extension.ToLower()}}
    $results | Export-Csv -Path $report -NoTypeInformation -Force
    $totalSz = ($results | Measure-Object SizeMB -Sum).Sum
    Write-Log "  $($results.Count) files over 50 MB  → total $(Format-Bytes ($totalSz*1MB))" -Level SIZE
    Write-Log "  Report: $report" -Level OK
    $results | Select-Object -First 15 | ForEach-Object { Write-Log ("  {0,9} MB  {1}" -f $_.SizeMB,$_.FullName) -Level SIZE }
    if (-not $script:IsAnalyze) { Invoke-Item $report -ErrorAction SilentlyContinue }
}

Register-Cleaner -Id 'disk.duplicates' -Name 'Duplicate Files (Downloads)' -Category 'Disk' -Risk 'Moderate' -Description 'MD5-based duplicate detection in Downloads folder' -Fn {
    $searchRoot = "$env:USERPROFILE\Downloads"
    Write-Log "  Scanning $searchRoot..."
    $files = Get-ChildItem $searchRoot -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 1MB }
    $sameSize = $files | Group-Object Length | Where-Object { $_.Count -gt 1 }
    $dupes = [System.Collections.Generic.List[object]]::new()
    foreach ($g in $sameSize) {
        $hashes = $g.Group | ForEach-Object {
            $h = (Get-FileHash $_.FullName -Algorithm MD5 -ErrorAction SilentlyContinue).Hash
            if ($h) { [pscustomobject]@{ F=$_.FullName; Size=$_.Length; Hash=$h } }
        }
        $hg = $hashes | Group-Object Hash | Where-Object { $_.Count -gt 1 -and $_.Name }
        foreach ($dg in $hg) { $dg.Group | Select-Object -Skip 1 | ForEach-Object { $dupes.Add($_) } }
    }
    $wasted = ($dupes | Measure-Object Size -Sum).Sum
    Write-Log "  Duplicate files found: $($dupes.Count) ($(Format-Bytes $wasted) wasted)" -Level SIZE
    if ($script:IsAnalyze) { $script:Stats.BytesAnalyzed += $wasted; return }
    if ($dupes.Count -gt 0 -and (Confirm-Action "Delete $($dupes.Count) duplicate files ($(Format-Bytes $wasted))?")) {
        foreach ($d in $dupes) { Remove-ItemSafe $d.F -CleanerId 'disk.duplicates' }
    }
}

Register-Cleaner -Id 'disk.empty_folders' -Name 'Empty Folders (AppData & Temp)' -Category 'Disk' -Risk 'Safe' -Description 'Recursively remove empty folders left behind by uninstallers' -Fn {
    $roots = @($env:APPDATA,$env:LOCALAPPDATA,"$env:windir\Temp")
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $empties = Get-ChildItem $root -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0 }
        Write-Log "  Empty folders in ${root}: $($empties.Count)" -Level SIZE
        if (-not $script:IsAnalyze) {
            foreach ($e in $empties) { Remove-ItemSafe $e.FullName -Recurse -CleanerId 'disk.empty_folders' }
        }
    }
}

Register-Cleaner -Id 'disk.trim_ssd' -Name 'SSD TRIM / HDD Defrag' -Category 'Disk' -RequiresAdmin $true -Risk 'Safe' -Description 'Optimizes drives: TRIM on SSDs, analyze/defrag on HDDs' -Fn {
    if ($script:IsAnalyze) { Write-Log '  Would optimize all NTFS drives'; return }
    $vols = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.FileSystem -eq 'NTFS' }
    foreach ($vol in $vols) {
        $dl = $vol.DriveLetter
        $disk = Get-PhysicalDisk -ErrorAction SilentlyContinue |
            Where-Object { $_ | Get-Disk -ErrorAction SilentlyContinue |
                Get-Partition -ErrorAction SilentlyContinue |
                Where-Object { $_.DriveLetter -eq $dl } }
        $isSSD = $disk -and ($disk.MediaType -in ('SSD','Unspecified') -or $disk.BusType -eq 'NVMe')
        if ($isSSD) {
            Write-Log "  TRIM $($dl): (SSD/NVMe)"
            Optimize-Volume -DriveLetter $dl -ReTrim 4>&1 | Out-Null
            Write-Log "  TRIM complete on $($dl):" -Level OK
        } else {
            Optimize-Volume -DriveLetter $dl -Analyze 4>&1 | Out-Null
            if (Confirm-Action "Defragment drive $($dl):?") {
                Optimize-Volume -DriveLetter $dl -Defrag 4>&1 | Out-Null
            }
        }
    }
}

Register-Cleaner -Id 'disk.vss' -Name 'VSS Shadow Copies' -Category 'Disk' -RequiresAdmin $true -Risk 'Advanced' -Description 'Remove volume shadow copies to reclaim disk space' -Fn {
    vssadmin list shadows 2>&1 | ForEach-Object { Write-Log "  $_" -Level SIZE }
    if ($script:IsAnalyze) { return }
    if (Confirm-Action 'Delete ALL shadow copies for C:?') {
        vssadmin delete shadows /For=C: /All /Quiet 2>&1 | Write-Log
    } elseif (Confirm-Action 'Delete only the OLDEST shadow copy for C:?') {
        vssadmin delete shadows /For=C: /Oldest /Quiet 2>&1 | Write-Log
    }
}

Register-Cleaner -Id 'disk.compact_os' -Name 'CompactOS' -Category 'Disk' -RequiresAdmin $true -Risk 'Moderate' -Description 'Apply WIMBoot-style OS compression (saves 1-3 GB, slight IO cost)' -Fn {
    $q = compact.exe /compactOS:query 2>&1
    Write-Log "  $($q -join ' ')" -Level SIZE
    if ($script:IsAnalyze) { return }
    if ($q -match 'Compact state') { Write-Log '  CompactOS already active'; return }
    if (Confirm-Action 'Enable CompactOS? (recommended only on low-disk devices)') {
        compact.exe /compactOS:always 2>&1 | ForEach-Object { Write-Log "  $_" }
    }
}

Register-Cleaner -Id 'disk.ntfs_compress' -Name 'NTFS Compress Old Files' -Category 'Disk' -RequiresAdmin $true -Risk 'Moderate' -Description 'Apply NTFS transparent compression to files not touched in 365+ days' -Fn {
    $root = "$env:USERPROFILE\Documents"
    $cutoff = (Get-Date).AddDays(-365)
    $files = Get-ChildItem $root -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff -and $_.Length -gt 100KB }
    $totalSz = if ($files) { ($files | Measure-Object Length -Sum).Sum } else { 0L }
    Write-Log "  Eligible files: $($files.Count) ($(Format-Bytes $totalSz))" -Level SIZE
    if ($script:IsAnalyze) { $script:Stats.BytesAnalyzed += 0; return }  # compression doesn't "free" in the classic sense
    if ($files.Count -gt 0 -and (Confirm-Action "NTFS-compress $($files.Count) old files?")) {
        foreach ($f in $files) { compact.exe /c /i /q "`"$($f.FullName)`"" | Out-Null }
        Write-Log '  Compression complete' -Level OK
    }
}

Register-Cleaner -Id 'registry.orphans' -Name 'Registry Orphaned Uninstall Keys' -Category 'Registry' -Risk 'Moderate' -Description 'Registry uninstall entries whose target EXE no longer exists' -Fn {
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $orphanCount = 0
    foreach ($rp in $regPaths) {
        if (-not (Test-Path $rp)) { continue }
        Get-ChildItem $rp -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            $icon  = if ($props.PSObject.Properties['DisplayIcon']) { ($props.DisplayIcon -replace '"','' -split ',')[0] } else { $null }
            if ($icon -and $icon -match '\.(exe|dll)$' -and -not (Test-Path $icon.Trim() -ErrorAction SilentlyContinue)) {
                Write-Log "  Orphan: $($props.DisplayName) → $icon" -Level SIZE
                $orphanCount++
                if (-not $script:IsAnalyze) {
                    if (Confirm-Action "Remove orphaned registry key '$($props.DisplayName)'?") {
                        Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Log "  Removed: $($props.DisplayName)" -Level OK
                    }
                }
            }
        }
    }
    Write-Log "  Total orphaned uninstall keys: $orphanCount" -Level SIZE
}

Register-Cleaner -Id 'registry.broken_shortcuts' -Name 'Broken Start Menu / Taskbar Shortcuts' -Category 'Registry' -Risk 'Safe' -Description 'Removes .lnk shortcuts pointing to non-existent targets' -Fn {
    $lnkRoots = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu",
        "$env:PROGRAMDATA\Microsoft\Windows\Start Menu",
        "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    )
    $broken = 0
    foreach ($root in $lnkRoots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem -Path $root -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $sh  = New-Object -ComObject WScript.Shell
                $lnk = $sh.CreateShortcut($_.FullName)
                $tgt = $lnk.TargetPath
                if ($tgt -and -not (Test-Path $tgt -ErrorAction SilentlyContinue)) {
                    Write-Log "  Broken: $($_.FullName) → $tgt" -Level SIZE
                    $broken++
                    if (-not $script:IsAnalyze) { Remove-ItemSafe $_.FullName -CleanerId 'registry.broken_shortcuts' }
                }
            } catch {}
        }
    }
    Write-Log "  Broken shortcuts found: $broken" -Level SIZE
}

Register-Cleaner -Id 'network.dns_cache' -Name 'DNS / ARP / NetBIOS Cache' -Category 'Network' -RequiresAdmin $true -Risk 'Safe' -Description 'Flush DNS, ARP, and NetBIOS resolver caches' -Fn {
    if ($script:IsAnalyze) { Write-Log '  Would flush DNS, ARP, NetBIOS, IP destination cache'; return }
    ipconfig /flushdns 2>&1 | Out-Null;  Write-Log '  DNS flushed' -Level OK
    ipconfig /registerdns 2>&1 | Out-Null
    arp -d * 2>&1 | Out-Null;            Write-Log '  ARP cache cleared' -Level OK
    nbtstat -R  2>&1 | Out-Null;         Write-Log '  NetBIOS cache purged' -Level OK
    netsh int ip delete destinationcache 2>&1 | Out-Null
}

Register-Cleaner -Id 'network.winsock' -Name 'Winsock Catalog Reset' -Category 'Network' -RequiresAdmin $true -Risk 'Moderate' -Description 'Resets the Winsock LSP catalog (requires reboot)' -Fn {
    if ($script:IsAnalyze) { Write-Log '  Would: netsh winsock reset'; return }
    if (Confirm-Action 'Reset Winsock? (requires reboot)') {
        netsh winsock reset 2>&1 | ForEach-Object { Write-Log "  $_" }
        Write-Log '  Winsock reset queued – reboot required' -Level WARN
    }
}

Register-Cleaner -Id 'network.ssl_cache' -Name 'SSL / CRL Cache' -Category 'Network' -Risk 'Safe' -Description 'Certificate revocation and CryptNet URL cache' -Fn {
    $paths = @("$env:APPDATA\Microsoft\SystemCertificates\My\Crls","$env:LOCALAPPDATA\Microsoft\CryptnetUrlCache")
    foreach ($p in $paths) { Remove-FolderContents $p -CleanerId 'network.ssl_cache' }
}

# ═══════════════════════════════════════════════════════════════
# ███  DRIVERS
# ═══════════════════════════════════════════════════════════════

Register-Cleaner -Id 'drivers.old' -Name 'Outdated OEM Driver Packages' -Category 'Drivers' -RequiresAdmin $true -Risk 'Advanced' -Description 'Removes older driver versions when multiple exist in the driver store' -Fn {
    $raw = pnputil /enum-drivers 2>$null
    if (-not $raw) { Write-Log '  pnputil unavailable'; return }
    $blocks   = ($raw -join "`n") -split '(?=Published Name\s+:)'
    $parsed   = foreach ($block in $blocks) {
        if ($block -notmatch 'Published Name') { continue }
        [pscustomobject]@{
            Published = if ($block -match 'Published Name\s+:\s+(.+)') { $Matches[1].Trim() } else { '' }
            Original  = if ($block -match 'Original Name\s+:\s+(.+)') { $Matches[1].Trim() } else { '' }
            Provider  = if ($block -match 'Provider Name\s+:\s+(.+)') { $Matches[1].Trim() } else { '' }
            Date      = if ($block -match 'Driver Date\s+:\s+(.+)') { $Matches[1].Trim() } else { '' }
            Version   = if ($block -match 'Driver Version\s+:\s+(.+)') { $Matches[1].Trim() } else { '' }
        }
    }
    $groups = @($parsed | Group-Object Original | Where-Object { $_.Count -gt 1 })
    Write-Log "  Driver families with multiple versions: $($groups.Count)"
    foreach ($g in $groups) {
        $sorted = $g.Group | Sort-Object Date -Descending
        $newest = $sorted | Select-Object -First 1
        foreach ($old in ($sorted | Select-Object -Skip 1)) {
            Write-Log "  Old: $($old.Published) ($($old.Original) v$($old.Version) / keep v$($newest.Version))" -Level SIZE
            if (-not $script:IsAnalyze) {
                if (Confirm-Action "Remove driver $($old.Published)?") {
                    pnputil /delete-driver $old.Published /uninstall 2>&1 | ForEach-Object { Write-Log "  $_" }
                }
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════
# ███  SCHEDULED TASK INSTALLER
# ═══════════════════════════════════════════════════════════════

function Install-ScheduledTask {
    if (-not $script:IsAdmin) { Write-Host 'Requires elevation to install scheduled task.' -ForegroundColor Red; return }
    $taskName  = 'WinClean Weekly'
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script:ScriptPath`" -RunAll -Yes -ExcludeCategories Registry,Drivers,DevTools"
    $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
    $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -RunOnlyIfIdle $false
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal -Force | Out-Null
    Write-Host "Scheduled task '$taskName' installed (runs Sundays at 3:00 AM as SYSTEM)." -ForegroundColor Green
}

function Remove-ScheduledTask-WinClean {
    Unregister-ScheduledTask -TaskName 'WinClean Weekly' -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Scheduled task removed." -ForegroundColor Yellow
}

if ($InstallScheduled) { Install-ScheduledTask; try { Stop-Transcript 2>$null } catch {}; exit 0 }
if ($RemoveScheduled)  { Remove-ScheduledTask-WinClean; try { Stop-Transcript 2>$null } catch {}; exit 0 }

# ═══════════════════════════════════════════════════════════════
# ███  ALL-USERS SUPPORT
# ═══════════════════════════════════════════════════════════════

function Get-TargetUsers {
    if (-not $AllUsers -or -not $script:IsAdmin) {
        return @([pscustomobject]@{ Name=$env:USERNAME; ProfilePath=$env:USERPROFILE })
    }
    Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.Enabled } | ForEach-Object {
        $sid = $_.SID.Value
        $profilePath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction SilentlyContinue).ProfileImagePath
        if ($profilePath -and (Test-Path $profilePath)) {
            [pscustomobject]@{ Name=$_.Name; ProfilePath=$profilePath }
        }
    }
}

# ═══════════════════════════════════════════════════════════════
# ███  RUNNER LOGIC
# ═══════════════════════════════════════════════════════════════

$script:IsAdmin  = Test-IsAdmin
try { $script:InitFree = (Get-PSDrive C).Free } catch {}

Write-Log "WinClean v$script:ScriptVersion | Admin=$($script:IsAdmin) | Analyze=$($script:IsAnalyze) | Shred=$($script:DoShred) | ShredPasses=$($script:ShredN)"

# Build effective cleaner list
function Get-EffectiveCleaners {
    $ids = if ($Include.Count -gt 0) {
        $Include
    } else {
        $script:Cleaners.Keys
    }
    if ($Exclude.Count -gt 0) {
        $ids = $ids | Where-Object { $_ -notin $Exclude }
    }
    return $ids
}

function Invoke-AllCleaners {
    $ids = Get-EffectiveCleaners
    $total = $ids.Count
    $i = 0
    foreach ($id in $ids) {
        $i++
        $pct = [int]($i / $total * 100)
        $c = $script:Cleaners[$id]
        if ($c) {
            Show-Progress 'WinClean' "$id – $($c.Name)" $pct
            Write-Section "$id – $($c.Name)"
            Invoke-Cleaner $id
        }
    }
    Write-Progress -Activity 'WinClean' -Completed
}

function Show-Summary {
    $elapsed  = (Get-Date) - $script:Stats.StartTime
    $finalFree= try { (Get-PSDrive C).Free } catch { $script:InitFree }
    $netFreed = $finalFree - $script:InitFree

    Write-Section 'WinClean Summary'
    $mode = if ($script:IsAnalyze) { 'ANALYZE (no files deleted)' } else { 'CLEAN' }
    Write-Host "  Mode           : $mode" -ForegroundColor Cyan
    Write-Host "  Files removed  : $($script:Stats.FilesRemoved)" -ForegroundColor White
    Write-Host "  Dirs removed   : $($script:Stats.DirsRemoved)"  -ForegroundColor White
    if ($script:IsAnalyze) {
        Write-Host "  Space recoverable: $(Format-Bytes $script:Stats.BytesAnalyzed)" -ForegroundColor Magenta
    } else {
        Write-Host "  Bytes freed    : $(Format-Bytes $script:Stats.BytesFreed)" -ForegroundColor Green
        Write-Host "  C: free before : $(Format-Bytes $script:InitFree)" -ForegroundColor White
        Write-Host "  C: free after  : $(Format-Bytes $finalFree)"       -ForegroundColor White
        if ($netFreed -gt 0) {
            Write-Host "  Net gain       : $(Format-Bytes $netFreed)" -ForegroundColor Green
        }
    }
    Write-Host "  Errors         : $($script:Stats.Errors)"   -ForegroundColor $(if($script:Stats.Errors -gt 0){'Red'}else{'White'})
    Write-Host "  Skipped items  : $($script:Stats.Skipped)"  -ForegroundColor White
    Write-Host "  Elapsed        : $($elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor White
    Write-Host "  Log file       : $script:LogFile" -ForegroundColor DarkGray

    # Top cleaners by impact
    $topCleaners = $script:CleanerResults | Sort-Object BytesCleaned -Descending | Select-Object -First 10
    if ($topCleaners) {
        Write-Host "`n  Top cleaners by space:" -ForegroundColor Cyan
        foreach ($c in $topCleaners) {
            if ($c.BytesCleaned -gt 0) {
                Write-Host ("  {0,-40} {1}" -f "[$($c.Id)] $($c.Name)", (Format-Bytes $c.BytesCleaned)) -ForegroundColor $(if($c.Errors -gt 0){'Yellow'}else{'White'})
            }
        }
    }

    if ($JsonLog) {
        $summary = [ordered]@{
            version     = $script:ScriptVersion
            mode        = $mode
            timestamp   = (Get-Date).ToString('o')
            files_removed = $script:Stats.FilesRemoved
            bytes_freed = $script:Stats.BytesFreed
            bytes_analyzed = $script:Stats.BytesAnalyzed
            errors      = $script:Stats.Errors
            skipped     = $script:Stats.Skipped
            elapsed_sec = $elapsed.TotalSeconds
            cleaners    = $script:CleanerResults
        }
        $jsonPath = Join-Path $script:LogDir ("WinClean_$(Get-Date -Format yyyyMMdd_HHmmss).json")
        $summary | ConvertTo-Json -Depth 5 | Set-Content $jsonPath -Force
        Write-Host "  JSON log       : $jsonPath" -ForegroundColor DarkGray
    }
}

# ─────────────────────────────────────────────────────────────
# NON-INTERACTIVE MODES
# ─────────────────────────────────────────────────────────────
if ($Analyze) {
    Write-Host "`n[ANALYZE MODE]  No files will be deleted." -ForegroundColor Magenta
    Invoke-AllCleaners
    Show-Summary
    try { Stop-Transcript 2>$null } catch {}
    exit 0
}

if ($RunAll) {
    Write-Host "`n[RUN ALL MODE]" -ForegroundColor Green
    Invoke-AllCleaners
    Show-Summary
    try { Stop-Transcript 2>$null } catch {}
    exit 0
}

if ($Clean -and $Include.Count -gt 0) {
    Write-Host "`n[CLEAN MODE]  Cleaners: $($Include -join ', ')" -ForegroundColor Green
    foreach ($id in $Include) { Write-Section $id; Invoke-Cleaner $id }
    Show-Summary
    try { Stop-Transcript 2>$null } catch {}
    exit 0
}

# ─────────────────────────────────────────────────────────────
# INTERACTIVE MENU
# ─────────────────────────────────────────────────────────────
function Show-InteractiveMenu {
    Clear-Host
    Write-Host ''
    Write-Host '  ╔══════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
    Write-Host '  ║         W I N C L E A N   v4.0                         ║' -ForegroundColor Cyan
    Write-Host '  ║   BleachBit-class cleaner for Windows  ·  PowerShell   ║' -ForegroundColor Cyan
    Write-Host '  ╚══════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
    Write-Host ''

    # Drive bar
    try {
        $drv  = Get-PSDrive C
        $free = $drv.Free; $used = $drv.Used; $total = $free + $used
        $pct  = [int]($used / $total * 100)
        $barW = 50; $fill = [int]($pct / 100 * $barW)
        $bar  = ('█' * $fill) + ('░' * ($barW - $fill))
        $col  = if ($pct -gt 90) { 'Red' } elseif ($pct -gt 75) { 'Yellow' } else { 'Green' }
        Write-Host ("  C:\  [{0}] {1}%  {2} used / {3} free" -f $bar, $pct, (Format-Bytes $used), (Format-Bytes $free)) -ForegroundColor $col
    } catch {}
    Write-Host "  Admin: $($script:IsAdmin)  |  Shred: $($script:DoShred)  |  Log: $script:LogFile" -ForegroundColor DarkGray
    Write-Host ''

    $categories = $script:Cleaners.Values | Group-Object Category | Sort-Object Name
    $allIds = @()
    foreach ($cat in $categories) {
        Write-Host "  ┌─ $($cat.Name) " -NoNewline -ForegroundColor DarkYellow
        Write-Host ('─' * (55 - $cat.Name.Length)) -ForegroundColor DarkGray
        foreach ($c in ($cat.Group | Sort-Object Id)) {
            $riskColor = switch ($c.Risk) { 'Safe' { 'White' } 'Moderate' { 'Yellow' } 'Advanced' { 'Red' } }
            $adminTag  = if ($c.RequiresAdmin -and -not $script:IsAdmin) { ' [needs admin]' } else { '' }
            Write-Host ("  │  {0,-18}  {1}{2}" -f $c.Id, $c.Name, $adminTag) -ForegroundColor $riskColor
            $allIds += $c.Id
        }
        Write-Host ''
    }
    Write-Host '  ─────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host '  analyze    Preview all – show sizes, no deletion' -ForegroundColor Magenta
    Write-Host '  all        Run every cleaner (prompts on destructive)'
    Write-Host '  all -y     Run every cleaner, auto-confirm ALL prompts' -ForegroundColor Yellow
    Write-Host '  <id>       Run single cleaner (e.g. system.temp)'
    Write-Host '  list       Print all cleaner IDs'
    Write-Host '  shred      Toggle secure shred (current: ' -NoNewline
    Write-Host "$($script:DoShred))" -ForegroundColor $(if($script:DoShred){'Green'}else{'Gray'})
    Write-Host '  q          Quit'
    Write-Host ''
    return $allIds
}

while ($true) {
    $allIds = Show-InteractiveMenu
    $raw    = (Read-Host '  > ').Trim().ToLower()

    if ($raw -eq 'q' -or $raw -eq 'quit' -or $raw -eq 'exit') {
        Show-Summary; break
    }
    if ($raw -eq 'list') {
        $script:Cleaners.Keys | Sort-Object | ForEach-Object {
            $c = $script:Cleaners[$_]
            Write-Host ("  {0,-30} [{1,-8}] {2}" -f $_, $c.Risk, $c.Description)
        }
        Read-Host "`n  Press Enter to continue" | Out-Null
        continue
    }
    if ($raw -eq 'shred') {
        $script:DoShred = -not $script:DoShred
        Write-Host "  Secure shred: $($script:DoShred)" -ForegroundColor $(if($script:DoShred){'Green'}else{'Yellow'})
        Start-Sleep 1; continue
    }
    if ($raw -eq 'analyze') {
        $script:IsAnalyze = $true
        Invoke-AllCleaners
        $script:IsAnalyze = $false
        Show-Summary
        Read-Host "`n  Press Enter" | Out-Null
        continue
    }
    if ($raw -in ('all -y','all-y','all --yes')) {
        $script:AutoYes = $true
        Invoke-AllCleaners
        $script:AutoYes = $false
        Show-Summary
        Read-Host "`n  Press Enter" | Out-Null
        continue
    }
    if ($raw -eq 'all') {
        Invoke-AllCleaners
        Show-Summary
        Read-Host "`n  Press Enter" | Out-Null
        continue
    }
    # Single cleaner by ID
    $c = $script:Cleaners[$raw]
    if ($c) {
        Write-Section "$($c.Id) – $($c.Name)"
        Write-Host "  Risk: $($c.Risk)  |  $($c.Description)" -ForegroundColor DarkGray
        Invoke-Cleaner $raw
        Show-Summary
        Read-Host "`n  Press Enter" | Out-Null
        continue
    }
    # Partial match
    $matches = $script:Cleaners.Keys | Where-Object { $_ -like "*$raw*" }
    if ($matches.Count -eq 1) {
        Write-Section $matches[0]; Invoke-Cleaner $matches[0]
        Show-Summary; Read-Host "`n  Press Enter" | Out-Null
        continue
    } elseif ($matches.Count -gt 1) {
        Write-Host "  Matches: $($matches -join ', ')" -ForegroundColor Yellow
        Read-Host '  Press Enter' | Out-Null
        continue
    }
    Write-Host "  Unknown command or cleaner ID: '$raw'" -ForegroundColor Red
    Start-Sleep 1
}

try { Stop-Transcript 2>$null } catch {}
