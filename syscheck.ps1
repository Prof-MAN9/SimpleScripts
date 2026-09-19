<#
.SYNOPSIS
    SysCheck.ps1 v2.1.0 — Comprehensive Windows System Health & Diagnostic Report

.DESCRIPTION
    Produces a detailed health report covering: System Overview, CPU, Memory,
    Disk, GPU, Temperatures, SMART, Network, USB/Peripherals, Audio, Display,
    Battery, Drivers, Startup Programs, Reliability, Services, Processes,
    Security, and Pending Updates.

    Generates a unified Health Score (0-100) and a prioritized Issues Summary
    at the end of each run.

.PARAMETER Json
    Output machine-readable JSON instead of the formatted report.

.PARAMETER Watch
    Refresh every N seconds (Ctrl-C to stop). E.g. -Watch 10

.PARAMETER NoColor
    Disable colour output (useful for log files / CI).

.PARAMETER Output
    Save report to a plain-text file in addition to console output.

.PARAMETER HtmlOutput
    Save report as a self-contained HTML file. E.g. -HtmlOutput C:\health.html

.PARAMETER Sections
    Comma-separated list of sections to run.
    Available: overview,cpu,memory,disk,gpu,temps,smart,network,usb,audio,
               display,battery,drivers,startup,reliability,services,
               processes,security,updates,eventlog,networking,
               pcie,virtualization,time,shares,certificates

.PARAMETER Baseline
    Path to a JSON baseline file produced by a previous -Json run.
    When supplied, the report highlights regressions vs the baseline.

.PARAMETER ExportBaseline
    Save current readings as a baseline JSON for future comparisons.

.PARAMETER Diagnose
    Only show warnings and critical issues (suppresses informational output).

.PARAMETER Version
    Show version and exit.

.PARAMETER Help
    Show this help.

.NOTES
    Run as Administrator for full data (SMART, firewall, event logs, GPU WMI,
    driver details, scheduled tasks, security log).
    PowerShell 5.1+ required. Compatible with PowerShell 7+.

.EXAMPLE
    .\SysCheck.ps1
    .\SysCheck.ps1 -Sections cpu,memory,disk,gpu,pcie,virtualization
    .\SysCheck.ps1 -Watch 10
    .\SysCheck.ps1 -Json -Output C:\health.json -ExportBaseline
    .\SysCheck.ps1 -Json -Baseline C:\health_baseline.json
    .\SysCheck.ps1 -HtmlOutput C:\health.html
    .\SysCheck.ps1 -Diagnose
    .\SysCheck.ps1 -NoColor -Output C:\health.txt
    .\SysCheck.ps1 -Sections eventlog,networking,time,shares,certificates
#>

[CmdletBinding()]
param(
    [switch]$Json,
    [int]$Watch              = 0,
    [switch]$NoColor,
    [string]$Output          = '',
    [string]$HtmlOutput      = '',
    [string]$Sections        = '',
    [switch]$Diagnose,
    [string]$Baseline        = '',
    [switch]$ExportBaseline,
    [switch]$Version,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ─────────────────────────────────────────────────────────────────────────────
# VERSION / HELP
# ─────────────────────────────────────────────────────────────────────────────
$SCRIPT_VERSION = '2.1.0'
$SCRIPT_NAME    = $MyInvocation.MyCommand.Name

if ($Version) { Write-Host "$SCRIPT_NAME v$SCRIPT_VERSION"; exit 0 }
if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# GLOBAL STATE
# ─────────────────────────────────────────────────────────────────────────────
$script:ReportLines  = [System.Collections.Generic.List[string]]::new()
$script:HtmlRows     = [System.Collections.Generic.List[string]]::new()
$script:JsonData     = [ordered]@{}
$script:Issues       = [System.Collections.Generic.List[hashtable]]::new()
$script:HealthScore  = 100   # decremented as issues are found

# ─────────────────────────────────────────────────────────────────────────────
# ISSUE TRACKER
# ─────────────────────────────────────────────────────────────────────────────
function Add-Issue {
    param(
        [ValidateSet('warn','crit','info')]
        [string]$Level,
        [string]$Category,
        [string]$Message,
        [int]$ScorePenalty = 0
    )
    $script:Issues.Add(@{ Level=$Level; Category=$Category; Message=$Message })
    $script:HealthScore = [Math]::Max(0, $script:HealthScore - $ScorePenalty)
}

# ─────────────────────────────────────────────────────────────────────────────
# COLOUR HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function Write-Line {
    param([string]$Text = '', [ConsoleColor]$Fg = [ConsoleColor]::Gray, [switch]$Plain)
    $script:ReportLines.Add($Text)
    $script:HtmlRows.Add("<div class='line'>$([System.Web.HttpUtility]::HtmlEncode($Text))</div>")
    if ($Json) { return }
    if ($Diagnose) { return }   # suppress all normal output in Diagnose mode
    if ($NoColor -or $Plain) { Write-Host $Text }
    else { Write-Host $Text -ForegroundColor $Fg }
}

function Get-LevelColor([string]$Level) {
    switch ($Level) {
        'ok'   { return [ConsoleColor]::Green    }
        'warn' { return [ConsoleColor]::Yellow   }
        'crit' { return [ConsoleColor]::Red      }
        'info' { return [ConsoleColor]::Cyan     }
        'dim'  { return [ConsoleColor]::DarkGray }
        default{ return [ConsoleColor]::Gray     }
    }
}

function Write-SectionHeader([string]$Title, [string]$Icon = '●') {
    $line = '─' * 62
    Write-Line ''
    Write-Line $line                     -Fg ([ConsoleColor]::DarkBlue)
    Write-Line "  $Icon  $Title"         -Fg ([ConsoleColor]::White)
    Write-Line $line                     -Fg ([ConsoleColor]::DarkBlue)
}

function Write-KV([string]$Key, [string]$Value, [string]$Level = '') {
    $keyPad = $Key.PadRight(32)
    $plain  = "  $keyPad $Value"
    $script:ReportLines.Add($plain)
    $htmlClass = if ($Level) { " class='$Level'" } else { '' }
    $script:HtmlRows.Add("<div class='kv$htmlClass'><span class='key'>$([System.Web.HttpUtility]::HtmlEncode($Key))</span><span class='val'>$([System.Web.HttpUtility]::HtmlEncode($Value))</span></div>")
    if ($Json -or $Diagnose) { return }
    if ($NoColor) { Write-Host $plain; return }
    Write-Host "  " -NoNewline
    Write-Host $keyPad -ForegroundColor Cyan -NoNewline
    Write-Host " " -NoNewline
    if ($Level) { Write-Host $Value -ForegroundColor (Get-LevelColor $Level) }
    else { Write-Host $Value }
}

function Get-Bar([int]$Pct, [int]$Width = 30, [string]$Level = 'ok') {
    $Pct    = [Math]::Max(0, [Math]::Min(100, $Pct))
    $filled = [Math]::Round($Pct * $Width / 100)
    $empty  = $Width - $filled
    return @{ Bar = ('█' * $filled) + ('░' * $empty); Pct = "$($Pct.ToString().PadLeft(3))%"; Level = $Level }
}

function Write-Bar([string]$Key, [int]$Pct, [int]$Width = 30, [string]$Level = '') {
    if (-not $Level) { $Level = Get-Threshold $Pct 75 90 }
    $b      = Get-Bar $Pct $Width $Level
    $keyPad = $Key.PadRight(32)
    $plain  = "  $keyPad $($b.Bar) $($b.Pct)"
    $script:ReportLines.Add($plain)
    $script:HtmlRows.Add("<div class='bar $Level'><span class='key'>$([System.Web.HttpUtility]::HtmlEncode($Key))</span><span class='barfill' style='width:$Pct%'></span><span class='barpct'>$($b.Pct)</span></div>")
    if ($Json -or $Diagnose) { return }
    if ($NoColor) { Write-Host $plain; return }
    Write-Host "  " -NoNewline
    Write-Host $keyPad -ForegroundColor Cyan -NoNewline
    Write-Host " " -NoNewline
    Write-Host $b.Bar -ForegroundColor (Get-LevelColor $Level) -NoNewline
    Write-Host " $($b.Pct)" -ForegroundColor DarkGray
}

function Get-Threshold([int]$Val, [int]$Warn, [int]$Crit) {
    if ($Val -ge $Crit) { return 'crit' }
    if ($Val -ge $Warn) { return 'warn' }
    return 'ok'
}

function Format-Bytes([long]$Bytes) {
    if ($Bytes -ge 1TB) { return '{0:N2} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Format-MemoryType([int]$Type) {
    switch ($Type) {
        20 {'DDR'} 21 {'DDR2'} 22 {'DDR2 FB-DIMM'} 24 {'DDR3'}
        26 {'DDR4'} 34 {'DDR5'} default { "Type $Type" }
    }
}

function Test-SectionEnabled([string]$Name) {
    if (-not $Sections) { return $true }
    return ($Sections -split ',') -contains $Name
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [Security.Principal.WindowsPrincipal]$id
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Add-JsonKey([string]$Key, $Value) { $script:JsonData[$Key] = $Value }

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
function Write-Banner {
    if ($Json -or $Diagnose) { return }
    $banner = @'
  ███████╗██╗   ██╗███████╗ ██████╗██╗  ██╗███████╗ ██████╗██╗  ██╗
  ██╔════╝╚██╗ ██╔╝██╔════╝██╔════╝██║  ██║██╔════╝██╔════╝██║ ██╔╝
  ███████╗ ╚████╔╝ ███████╗██║     ███████║█████╗  ██║     █████╔╝
  ╚════██║  ╚██╔╝  ╚════██║██║     ██╔══██║██╔══╝  ██║     ██╔═██╗
  ███████║   ██║   ███████║╚██████╗██║  ██║███████╗╚██████╗██║  ██╗
  ╚══════╝   ╚═╝   ╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝
'@
    Write-Host $banner -ForegroundColor DarkBlue
    Write-Host ("  System Health Check  v{0}   |   {1}" -f $SCRIPT_VERSION, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
    Write-Host ''
    $script:ReportLines.Add("SysCheck.ps1 v$SCRIPT_VERSION  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: System Overview
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionOverview {
    Write-SectionHeader 'System Overview' ([char]0x1F5A5)

    $cs   = Get-CimInstance Win32_ComputerSystem  -ErrorAction SilentlyContinue
    $os   = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS            -ErrorAction SilentlyContinue
    $mb   = Get-CimInstance Win32_BaseBoard       -ErrorAction SilentlyContinue

    $hostname  = $env:COMPUTERNAME
    $osName    = $os.Caption
    $osVer     = $os.Version
    $osBuild   = $os.BuildNumber
    $arch      = $env:PROCESSOR_ARCHITECTURE
    $domain    = if ($cs.PartOfDomain) { $cs.Domain } else { 'WORKGROUP' }
    $totalRam  = if ($cs) { Format-Bytes ($cs.TotalPhysicalMemory) } else { 'N/A' }

    $bootTime  = $os.LastBootUpTime
    $uptime    = (Get-Date) - $bootTime
    $uptimeStr = '{0}d {1}h {2}m' -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes

    # Flag very long uptimes
    if ($uptime.TotalDays -gt 30) {
        Add-Issue -Level 'warn' -Category 'System' -Message "System uptime is $([int]$uptime.TotalDays) days — consider rebooting to apply patches." -ScorePenalty 5
    }

    $tz = (Get-TimeZone).DisplayName

    Write-KV 'Hostname'           $hostname
    Write-KV 'OS'                 "$osName (Build $osBuild)"
    Write-KV 'Version'            $osVer
    Write-KV 'Architecture'       $arch
    Write-KV 'Domain/Workgroup'   $domain
    Write-KV 'RAM (total)'        $totalRam
    Write-KV 'Last boot'          ($bootTime.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-KV 'Uptime'             $uptimeStr
    Write-KV 'Timezone'           $tz
    Write-KV 'Report time'        (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Write-KV 'BIOS version'       "$($bios.Manufacturer) / $($bios.SMBIOSBIOSVersion)"
    Write-KV 'BIOS date'          ($bios.ReleaseDate.ToString('yyyy-MM-dd'))
    Write-KV 'Motherboard'        "$($mb.Manufacturer) $($mb.Product)"
    Write-KV 'System manufacturer'"$($cs.Manufacturer) / $($cs.Model)"

    # BIOS age warning
    if ($bios.ReleaseDate) {
        $biosAge = ((Get-Date) - $bios.ReleaseDate).Days
        if ($biosAge -gt 1095) {  # 3 years
            Add-Issue -Level 'info' -Category 'BIOS' -Message "BIOS is $([int]($biosAge/365)) years old — check manufacturer for firmware updates." -ScorePenalty 2
        }
    }

    if (-not (Test-IsAdmin)) {
        Write-Line ''
        Write-Line '  ⚠  Not running as Administrator — some data may be unavailable.' -Fg Yellow
        Add-Issue -Level 'warn' -Category 'System' -Message 'Script not running as Administrator. SMART, Security log, GPU WMI, and driver data may be missing.'
    }

    Add-JsonKey 'hostname'   $hostname
    Add-JsonKey 'os'         $osName
    Add-JsonKey 'os_build'   $osBuild
    Add-JsonKey 'uptime_min' [int]$uptime.TotalMinutes
    Add-JsonKey 'last_boot'  $bootTime.ToString('o')
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: CPU
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionCPU {
    if (-not (Test-SectionEnabled 'cpu')) { return }
    Write-SectionHeader 'CPU' ([char]0x2699)

    $procs = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue

    foreach ($proc in $procs) {
        Write-KV 'Model'              $proc.Name.Trim()
        Write-KV 'Socket'             $proc.SocketDesignation
        Write-KV 'Cores (physical)'   $proc.NumberOfCores
        Write-KV 'Threads (logical)'  $proc.NumberOfLogicalProcessors
        Write-KV 'Base speed'         "$($proc.MaxClockSpeed) MHz"
        Write-KV 'L2 cache'           (Format-Bytes ($proc.L2CacheSize * 1KB))
        Write-KV 'L3 cache'           (Format-Bytes ($proc.L3CacheSize * 1KB))
        Write-KV 'Architecture'       $(switch ($proc.Architecture) {
            0 {'x86'} 1 {'MIPS'} 2 {'Alpha'} 3 {'PowerPC'}
            5 {'ARM'} 6 {'ia64'} 9 {'x64'} default {'Unknown'}
        })
        Write-KV 'Virtualization'     $(if ($proc.VirtualizationFirmwareEnabled) { 'Enabled' } else { 'Disabled/Unknown' })

        # CPU status flags
        $statusStr = switch ($proc.CpuStatus) {
            1 { 'OK' } 2 { 'Unknown' } 3 { 'Enabled' }
            4 { 'Disabled (user)' } 5 { 'Disabled (BIOS)' } 6 { 'Idle' }
            default { "Status $($proc.CpuStatus)" }
        }
        $cpuStatusLvl = if ($proc.CpuStatus -eq 1) { 'ok' } else { 'warn' }
        Write-KV 'CPU status'         $statusStr $cpuStatusLvl
        if ($proc.CpuStatus -notin @(1,3)) {
            Add-Issue -Level 'warn' -Category 'CPU' -Message "CPU $($proc.DeviceID) reports status: $statusStr" -ScorePenalty 10
        }
    }

    # Live CPU usage
    try {
        $cpuLoad = (Get-CimInstance Win32_Processor).LoadPercentage
        if ($null -eq $cpuLoad) {
            $cpuLoad = [int](Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1).CounterSamples[0].CookedValue
        }
        $cpuLoad  = [int]$cpuLoad
        $cpuLevel = Get-Threshold $cpuLoad 70 90
        Write-Bar 'Usage (live)' $cpuLoad 30 $cpuLevel
        if ($cpuLoad -ge 90) {
            Add-Issue -Level 'crit' -Category 'CPU' -Message "CPU usage is critically high at $cpuLoad%." -ScorePenalty 15
        } elseif ($cpuLoad -ge 70) {
            Add-Issue -Level 'warn' -Category 'CPU' -Message "CPU usage is elevated at $cpuLoad%." -ScorePenalty 5
        }
        Add-JsonKey 'cpu_load_pct' $cpuLoad
    } catch {
        Write-KV 'Usage (live)' 'unavailable (needs elevation)'
    }

    # Per-core usage
    try {
        $coreCounters = Get-Counter '\Processor(*)\% Processor Time' -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop
        Write-Line ''
        Write-Line '  Per-core load:' -Fg DarkGray
        foreach ($s in $coreCounters.CounterSamples | Where-Object { $_.InstanceName -ne '_total' } | Sort-Object InstanceName) {
            $cPct   = [int]$s.CookedValue
            $cLevel = Get-Threshold $cPct 70 90
            Write-Bar "  Core $($s.InstanceName)" $cPct 20 $cLevel
        }
    } catch { <# optional #> }

    # Power throttling detection (Event 37)
    try {
        $throttle = Get-WinEvent -LogName 'System' -MaxEvents 100 -ErrorAction Stop |
                    Where-Object { $_.Id -eq 37 -and $_.TimeCreated -ge (Get-Date).AddHours(-1) }
        if ($throttle) {
            Write-Line ''
            Write-Line "  ⚠  CPU throttling events detected in last hour ($($throttle.Count) events)." -Fg Yellow
            Add-Issue -Level 'warn' -Category 'CPU' -Message "CPU thermal throttling detected ($($throttle.Count) events in last hour). Check cooling." -ScorePenalty 10
        }
    } catch { <# optional #> }

    # Hypervisor
    $hv = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
    if ($hv) {
        Write-Line ''
        Write-KV 'Hypervisor detected' 'Yes (running inside VM or Hyper-V host)' 'warn'
    }

    Add-JsonKey 'cpu_model' ($procs | Select-Object -First 1 -ExpandProperty Name)
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Memory
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionMemory {
    if (-not (Test-SectionEnabled 'memory')) { return }
    Write-SectionHeader 'Memory' ([char]0x1F4BE)

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem  -ErrorAction SilentlyContinue

    $total   = $cs.TotalPhysicalMemory
    $free    = $os.FreePhysicalMemory * 1KB
    $used    = $total - $free
    $usedPct = [int]($used / $total * 100)
    $level   = Get-Threshold $usedPct 75 90

    Write-KV 'Total'   (Format-Bytes $total)
    Write-KV 'Used'    (Format-Bytes $used)
    Write-KV 'Free'    (Format-Bytes $free) 'ok'
    Write-Bar 'Usage'  $usedPct 30 $level

    if ($usedPct -ge 90) {
        Add-Issue -Level 'crit' -Category 'Memory' -Message "RAM usage critical at $usedPct%." -ScorePenalty 15
    } elseif ($usedPct -ge 75) {
        Add-Issue -Level 'warn' -Category 'Memory' -Message "RAM usage elevated at $usedPct%." -ScorePenalty 5
    }

    # Page file
    $pfTotal = $os.TotalVirtualMemorySize * 1KB
    $pfFree  = $os.FreeVirtualMemory      * 1KB
    $pfUsed  = $pfTotal - $pfFree
    $pfPct   = if ($pfTotal -gt 0) { [int]($pfUsed / $pfTotal * 100) } else { 0 }
    $pfLevel = Get-Threshold $pfPct 60 80

    Write-Line ''
    Write-KV 'Page file total'   (Format-Bytes $pfTotal)
    Write-KV 'Page file free'    (Format-Bytes $pfFree)
    Write-Bar 'Page file usage'  $pfPct 30 $pfLevel
    if ($pfPct -ge 60) {
        Write-Line '  ⚠  Elevated page file usage may indicate memory pressure.' -Fg Yellow
        Add-Issue -Level 'warn' -Category 'Memory' -Message "Page file usage at $pfPct% — possible memory pressure." -ScorePenalty 5
    }

    # Physical DIMMs
    $dimms = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    if ($dimms) {
        Write-Line ''
        Write-Line '  Physical DIMMs:' -Fg DarkGray
        foreach ($d in $dimms) {
            $spd  = if ($d.Speed)    { "$($d.Speed) MHz" } else { 'N/A' }
            $type = Format-MemoryType $d.MemoryType
            $ff   = switch ($d.FormFactor) { 8 {'DIMM'} 12 {'SO-DIMM'} default { "FF$($d.FormFactor)" } }
            $mfr  = if ($d.Manufacturer -and $d.Manufacturer -notmatch 'To Be') { " | $($d.Manufacturer)" } else { '' }
            $sn   = if ($d.SerialNumber -and $d.SerialNumber -notmatch '^\s*$') { " | S/N: $($d.SerialNumber.Trim())" } else { '' }
            Write-KV "  Slot $($d.DeviceLocator)" "$(Format-Bytes $d.Capacity)  $type  $ff  $spd$mfr$sn"
        }

        # Check for mismatched speeds (could cause instability)
        $speeds = $dimms | Select-Object -ExpandProperty Speed | Sort-Object -Unique
        if ($speeds.Count -gt 1) {
            Write-Line "  ⚠  DIMM speed mismatch detected: $($speeds -join ', ') MHz" -Fg Yellow
            Add-Issue -Level 'warn' -Category 'Memory' -Message "DIMMs have mismatched speeds ($($speeds -join ', ') MHz). System runs at lowest speed." -ScorePenalty 5
        }

        # Slot population check
        $csSlots = (Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue).MemoryDevices
        if ($csSlots) {
            Write-KV '  Slots used/total' "$($dimms.Count) / $csSlots"
        }
    }

    # Memory diagnostic check
    try {
        $memDiag = Get-WinEvent -LogName 'Microsoft-Windows-MemoryDiagnostics-Results/Debug' `
                   -MaxEvents 5 -ErrorAction Stop
        foreach ($ev in $memDiag) {
            $msg = $ev.Message -replace '\s+', ' '
            if ($msg -match 'error|failure|problem' -and $msg -notmatch 'no error') {
                Write-Line "  ⚠  Windows Memory Diagnostic reported: $($msg.Substring(0,[Math]::Min(100,$msg.Length)))" -Fg Red
                Add-Issue -Level 'crit' -Category 'Memory' -Message "Windows Memory Diagnostic reported hardware errors." -ScorePenalty 25
            }
        }
    } catch { <# diagnostic log may not exist #> }

    Add-JsonKey 'mem_total_bytes' $total
    Add-JsonKey 'mem_used_pct'    $usedPct
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Disk
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionDisk {
    if (-not (Test-SectionEnabled 'disk')) { return }
    Write-SectionHeader 'Disk Usage' ([char]0x1F4BF)

    $drives     = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                  Where-Object { $_.Used -ne $null }
    $jsonDrives = @()

    foreach ($d in $drives) {
        $total   = $d.Used + $d.Free
        if ($total -le 0) { continue }
        $usedPct = [int]($d.Used / $total * 100)
        $level   = Get-Threshold $usedPct 75 90

        $label   = try { (Get-Volume -DriveLetter ($d.Name.TrimEnd(':')) -ErrorAction Stop).FileSystemLabel } catch { '' }
        $fs      = try { (Get-Volume -DriveLetter ($d.Name.TrimEnd(':')) -ErrorAction Stop).FileSystem      } catch { 'N/A' }
        $display = if ($label) { "$($d.Name):  [$label]  [$fs]" } else { "$($d.Name):  [$fs]" }

        Write-Bar $display $usedPct 22 $level
        Write-KV "  $($d.Name) Used"  (Format-Bytes $d.Used)
        Write-KV "  $($d.Name) Free"  (Format-Bytes $d.Free) $(if ($usedPct -ge 90) {'crit'} elseif ($usedPct -ge 75) {'warn'} else {'ok'})
        Write-KV "  $($d.Name) Total" (Format-Bytes $total)
        Write-Line ''

        if ($usedPct -ge 90) {
            Add-Issue -Level 'crit' -Category 'Disk' -Message "Drive $($d.Name) is $usedPct% full ($(Format-Bytes $d.Free) free)." -ScorePenalty 20
        } elseif ($usedPct -ge 75) {
            Add-Issue -Level 'warn' -Category 'Disk' -Message "Drive $($d.Name) is $usedPct% full." -ScorePenalty 5
        }

        $jsonDrives += [ordered]@{ drive=$d.Name; used_pct=$usedPct; free_bytes=$d.Free; total_bytes=$total }
    }

    # Physical disks
    $physDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($physDisks) {
        Write-Line '  Physical disks:' -Fg DarkGray
        foreach ($pd in $physDisks) {
            Write-KV "  $($pd.FriendlyName)" "$(Format-Bytes $pd.Size)  [$($pd.MediaType)]  Bus: $($pd.BusType)  [$($pd.HealthStatus)]"
            if ($pd.HealthStatus -ne 'Healthy') {
                Add-Issue -Level 'crit' -Category 'Disk' -Message "Physical disk '$($pd.FriendlyName)' health: $($pd.HealthStatus)" -ScorePenalty 25
            }
        }
    }

    # Recycle Bin size
    Write-Line ''
    Write-Line '  Recycle Bin:' -Fg DarkGray
    try {
        $rbSize = (Get-ChildItem 'C:\$Recycle.Bin' -Recurse -Force -ErrorAction SilentlyContinue |
                   Measure-Object -Property Length -Sum).Sum
        Write-KV '  Recycle Bin size' (Format-Bytes $rbSize)
        if ($rbSize -gt 5GB) {
            Add-Issue -Level 'info' -Category 'Disk' -Message "Recycle Bin contains $(Format-Bytes $rbSize) — consider emptying it." -ScorePenalty 0
        }
    } catch {}

    Add-JsonKey 'drives' $jsonDrives
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: GPU
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionGPU {
    if (-not (Test-SectionEnabled 'gpu')) { return }
    Write-SectionHeader 'GPU / Display Adapters' ([char]0x1F5B5)

    $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    if (-not $gpus) {
        Write-Line '  No GPU data available.' -Fg DarkGray
        return
    }

    $jsonGPUs = @()
    foreach ($g in $gpus) {
        Write-Line ''
        Write-Line "  $($g.Name)" -Fg White

        $vram     = if ($g.AdapterRAM -and $g.AdapterRAM -gt 0) { Format-Bytes $g.AdapterRAM } else { 'N/A' }
        $res      = "$($g.CurrentHorizontalResolution) x $($g.CurrentVerticalResolution) @ $($g.CurrentRefreshRate) Hz"
        $drvDate  = if ($g.DriverDate) { $g.DriverDate.ToString('yyyy-MM-dd') } else { 'N/A' }
        $drvVer   = $g.DriverVersion

        Write-KV '  VRAM'            $vram
        Write-KV '  Current res'     $res
        Write-KV '  Driver version'  $drvVer
        Write-KV '  Driver date'     $drvDate
        Write-KV '  Video mode'      $g.VideoModeDescription
        Write-KV '  Status'          $g.Status $(if ($g.Status -eq 'OK') {'ok'} else {'crit'})

        if ($g.Status -ne 'OK') {
            Add-Issue -Level 'crit' -Category 'GPU' -Message "GPU '$($g.Name)' status: $($g.Status)" -ScorePenalty 20
        }

        # Driver age warning
        if ($g.DriverDate) {
            $driverAge = ((Get-Date) - $g.DriverDate).Days
            if ($driverAge -gt 365) {
                Write-KV '  Driver age' "$([int]($driverAge/365)) year(s) old" 'warn'
                Add-Issue -Level 'warn' -Category 'GPU' -Message "GPU driver for '$($g.Name)' is $([int]($driverAge/365)) year(s) old." -ScorePenalty 5
            }
        }

        # Check for error codes in device manager via WMI
        $devErr = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
                  Where-Object { $_.Caption -like "*$($g.Caption)*" -and $_.ConfigManagerErrorCode -ne 0 }
        if ($devErr) {
            foreach ($de in $devErr) {
                Write-KV '  Device Manager error' "Code $($de.ConfigManagerErrorCode)" 'crit'
                Add-Issue -Level 'crit' -Category 'GPU' -Message "GPU Device Manager error code $($de.ConfigManagerErrorCode) on '$($g.Name)'." -ScorePenalty 20
            }
        }

        $jsonGPUs += [ordered]@{
            name       = $g.Name
            vram       = $g.AdapterRAM
            driver_ver = $drvVer
            status     = $g.Status
        }
    }

    Add-JsonKey 'gpus' $jsonGPUs
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Temperatures
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionTemps {
    if (-not (Test-SectionEnabled 'temps')) { return }
    Write-SectionHeader 'Temperatures' ([char]0x1F321)

    $found = $false

    foreach ($ns in @('root/OpenHardwareMonitor', 'root/LibreHardwareMonitor')) {
        try {
            $sensors = Get-CimInstance -Namespace $ns -ClassName Sensor `
                       -Filter "SensorType='Temperature'" -ErrorAction Stop
            if ($sensors) {
                $found = $true
                $src   = if ($ns -like '*Libre*') { 'LibreHardwareMonitor' } else { 'OpenHardwareMonitor' }
                Write-Line "  (via $src)" -Fg DarkGray
                foreach ($s in $sensors | Sort-Object Parent, Name) {
                    $tempC = [int]$s.Value
                    $level = Get-Threshold $tempC 70 85
                    Write-KV "  $($s.Parent.Split('/')[-1]) / $($s.Name)" "${tempC}°C" $level
                    if ($tempC -ge 85) {
                        Add-Issue -Level 'crit' -Category 'Temperature' -Message "$($s.Name) is critically hot at ${tempC}°C." -ScorePenalty 20
                    } elseif ($tempC -ge 70) {
                        Add-Issue -Level 'warn' -Category 'Temperature' -Message "$($s.Name) is running warm at ${tempC}°C." -ScorePenalty 8
                    }
                }
                break
            }
        } catch { }
    }

    if (-not $found) {
        try {
            $tzs = Get-CimInstance -Namespace 'root/wmi' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
            if ($tzs) {
                $found = $true
                Write-Line '  (via ACPI thermal zones — limited resolution)' -Fg DarkGray
                foreach ($tz in $tzs) {
                    $tempC = [int](($tz.CurrentTemperature / 10.0) - 273.15)
                    $level = Get-Threshold $tempC 70 85
                    Write-KV "  $($tz.InstanceName)" "${tempC}°C" $level
                    if ($tempC -ge 85) {
                        Add-Issue -Level 'crit' -Category 'Temperature' -Message "Thermal zone running at ${tempC}°C." -ScorePenalty 20
                    }
                }
            }
        } catch { }
    }

    if (-not $found) {
        Write-Line ''
        Write-Line '  No temperature sensors accessible via WMI.' -Fg DarkGray
        Write-Line '  Install LibreHardwareMonitor with WMI enabled for full sensor data.' -Fg DarkGray
        Write-Line '  https://github.com/LibreHardwareMonitor/LibreHardwareMonitor' -Fg DarkGray
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: SMART Disk Health
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionSmart {
    if (-not (Test-SectionEnabled 'smart')) { return }
    Write-SectionHeader 'Disk Health (SMART)' ([char]0x1F50D)

    try {
        $disks = Get-PhysicalDisk -ErrorAction Stop
        foreach ($disk in $disks) {
            Write-Line ''
            Write-Line "  $($disk.FriendlyName)  [$($disk.MediaType)]" -Fg White

            $hs    = $disk.HealthStatus
            $opSt  = $disk.OperationalStatus
            $hsLvl = switch ($hs) { 'Healthy' {'ok'} 'Warning' {'warn'} 'Unhealthy' {'crit'} default {'warn'} }
            Write-KV '  Health status'      $hs       $hsLvl
            Write-KV '  Operational status' $opSt

            if ($hs -ne 'Healthy') {
                Add-Issue -Level 'crit' -Category 'SMART' -Message "Disk '$($disk.FriendlyName)' is reporting: $hs. Back up data immediately." -ScorePenalty 30
            }

            try {
                $rel = $disk | Get-StorageReliabilityCounter -ErrorAction Stop
                Write-KV '  Read errors total'  $rel.ReadErrorsTotal
                Write-KV '  Write errors total' $rel.WriteErrorsTotal

                if ($rel.ReadErrorsTotal -gt 0) {
                    Add-Issue -Level 'warn' -Category 'SMART' -Message "Disk '$($disk.FriendlyName)' has $($rel.ReadErrorsTotal) read error(s)." -ScorePenalty 15
                }
                if ($rel.WriteErrorsTotal -gt 0) {
                    Add-Issue -Level 'warn' -Category 'SMART' -Message "Disk '$($disk.FriendlyName)' has $($rel.WriteErrorsTotal) write error(s)." -ScorePenalty 15
                }

                $tempC = $rel.Temperature
                if ($tempC -and $tempC -gt 0) {
                    $tLvl = Get-Threshold $tempC 50 65
                    Write-KV '  Temperature'  "${tempC}°C" $tLvl
                    if ($tempC -ge 65) {
                        Add-Issue -Level 'crit' -Category 'SMART' -Message "Disk '$($disk.FriendlyName)' temperature ${tempC}°C — overheating." -ScorePenalty 20
                    }
                }

                if ($rel.PowerOnHours) { Write-KV '  Power-on hours' $rel.PowerOnHours }

                # Power-on hours warning for HDDs (>35,000 hrs ≈ 4 years of 24/7)
                if ($disk.MediaType -eq 'HDD' -and $rel.PowerOnHours -gt 35000) {
                    Add-Issue -Level 'warn' -Category 'SMART' -Message "HDD '$($disk.FriendlyName)' has $($rel.PowerOnHours) power-on hours — nearing end of life." -ScorePenalty 10
                }

                $wear = $rel.Wear
                if ($null -ne $wear -and $wear -ge 0) {
                    $wearLvl = Get-Threshold $wear 80 95
                    Write-KV '  Wear (SSD %)' "$wear %" $wearLvl
                    Write-Bar '  Wear level'  $wear 20 $wearLvl
                    if ($wear -ge 95) {
                        Add-Issue -Level 'crit' -Category 'SMART' -Message "SSD '$($disk.FriendlyName)' wear at $wear% — replace soon." -ScorePenalty 25
                    }
                }
            } catch {
                Write-KV '  SMART detail' 'unavailable (requires Administrator)'
            }

            # smartctl if installed
            $smartctl = Get-Command smartctl -ErrorAction SilentlyContinue
            if ($smartctl) {
                try {
                    $num    = $disk.DeviceId
                    $sOut   = & smartctl -H -A "/dev/pd$num" 2>$null
                    $health = ($sOut | Select-String 'SMART overall-health').Line
                    if ($health) {
                        Write-KV '  smartctl health' $health.Trim()
                        if ($health -notmatch 'PASSED') {
                            Add-Issue -Level 'crit' -Category 'SMART' -Message "smartctl reports: $($health.Trim())" -ScorePenalty 30
                        }
                    }
                    # Reallocated sectors
                    $reallocLine = $sOut | Select-String 'Reallocated_Sector'
                    if ($reallocLine) {
                        $reallocVal = ($reallocLine -split '\s+')[-1]
                        Write-KV '  Reallocated sectors' $reallocVal $(if ([int]$reallocVal -gt 0) {'crit'} else {'ok'})
                        if ([int]$reallocVal -gt 0) {
                            Add-Issue -Level 'crit' -Category 'SMART' -Message "Disk '$($disk.FriendlyName)' has $reallocVal reallocated sectors — hardware failure imminent." -ScorePenalty 30
                        }
                    }
                } catch { }
            }
        }
    } catch {
        Write-Line '  SMART data requires Administrator and Windows Storage subsystem.' -Fg DarkGray
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Network
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionNetwork {
    if (-not (Test-SectionEnabled 'network')) { return }
    Write-SectionHeader 'Network' ([char]0x1F310)

    Write-Line ('  {0,-22} {1,-12} {2,-20} {3,-28} {4,-10} {5,-10}' -f 'Adapter','State','IPv4','IPv6','Sent','Recv') -Fg DarkGray

    $adapters   = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Not Present' }
    $jsonIfaces = @()

    foreach ($a in $adapters | Sort-Object Status, Name) {
        $ipv4 = (Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -notlike '169.*' } | Select-Object -First 1).IPAddress
        $ipv6 = (Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue |
                 Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress

        $stats    = Get-NetAdapterStatistics -Name $a.Name -ErrorAction SilentlyContinue
        $sent     = if ($stats) { Format-Bytes $stats.SentBytes     } else { 'N/A' }
        $recv     = if ($stats) { Format-Bytes $stats.ReceivedBytes } else { 'N/A' }
        $stateLevel = switch ($a.Status) {
            'Up' {'ok'} 'Disconnected' {'warn'} default {'dim'}
        }

        $line = '  {0,-22} {1,-12} {2,-20} {3,-28} {4,-10} {5,-10}' -f `
            ($a.Name.Substring(0, [Math]::Min(21, $a.Name.Length))),
            $a.Status,
            ($ipv4 ?? '-'), ($ipv6 ?? '-'), $sent, $recv

        $script:ReportLines.Add($line)
        if (-not $Json -and -not $Diagnose) {
            if ($NoColor) { Write-Host $line }
            else {
                Write-Host ('  {0,-22} ' -f $a.Name.Substring(0, [Math]::Min(21, $a.Name.Length))) -NoNewline
                Write-Host ('{0,-12} ' -f $a.Status) -ForegroundColor (Get-LevelColor $stateLevel) -NoNewline
                Write-Host ('{0,-20} {1,-28} {2,-10} {3,-10}' -f ($ipv4 ?? '-'), ($ipv6 ?? '-'), $sent, $recv)
            }
        }

        $jsonIfaces += [ordered]@{ name=$a.Name; status=$a.Status; ipv4=$ipv4; sent=$stats.SentBytes; recv=$stats.ReceivedBytes }
    }

    # DNS & Gateway
    Write-Line ''
    $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                  Where-Object { $_.ServerAddresses } |
                  Select-Object -ExpandProperty ServerAddresses -Unique |
                  Select-Object -First 4
    Write-KV 'DNS servers'     ($dnsServers -join ', ')
    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
           Sort-Object RouteMetric | Select-Object -First 1).NextHop
    Write-KV 'Default gateway' ($gw ?? '(none)')

    # APIPA detection
    $apipaAddresses = Get-NetIPAddress -ErrorAction SilentlyContinue |
                      Where-Object { $_.IPAddress -like '169.254.*' }
    if ($apipaAddresses) {
        Write-Line '  ⚠  APIPA address detected (169.254.x.x) — DHCP failure on one or more adapters.' -Fg Yellow
        Add-Issue -Level 'warn' -Category 'Network' -Message "APIPA address detected — DHCP may have failed on one or more network adapters." -ScorePenalty 10
    }

    # Connectivity probes
    Write-Line ''
    Write-Line '  Connectivity:' -Fg DarkGray
    $probeTargets = [ordered]@{
        '8.8.8.8'       = 'Google DNS'
        '1.1.1.1'       = 'Cloudflare DNS'
        'www.google.com'= 'Internet (HTTP)'
    }
    $anyFailed = $false
    foreach ($target in $probeTargets.Keys) {
        $ok    = Test-Connection $target -Count 1 -Quiet -ErrorAction SilentlyContinue
        $ll    = if ($ok) { 'ok' } else { 'warn' }
        Write-KV "  $target ($($probeTargets[$target]))" $(if ($ok) { 'reachable' } else { 'UNREACHABLE' }) $ll
        if (-not $ok) { $anyFailed = $true }
    }
    if ($anyFailed) {
        Add-Issue -Level 'warn' -Category 'Network' -Message 'One or more network probes failed — check connectivity or DNS.' -ScorePenalty 10
    }

    # Listening ports
    Write-Line ''
    Write-Line '  Listening ports (top 20):' -Fg DarkGray
    try {
        $listeners = Get-NetTCPConnection -State Listen -ErrorAction Stop |
                     Sort-Object LocalPort | Select-Object -First 20
        Write-Line ('  {0,-30} {1}' -f 'Local endpoint', 'Process') -Fg DarkGray
        foreach ($l in $listeners) {
            $procName = try { (Get-Process -Id $l.OwningProcess -ErrorAction Stop).ProcessName } catch { "PID $($l.OwningProcess)" }
            Write-Line ('  {0,-30} {1}' -f "$($l.LocalAddress):$($l.LocalPort)", $procName)
        }
    } catch { Write-Line '  (requires elevation for process names)' -Fg DarkGray }

    $estCount = (Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Line ''
    Write-KV 'Established connections' $estCount

    Add-JsonKey 'interfaces' $jsonIfaces
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: USB / Peripherals
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionUSB {
    if (-not (Test-SectionEnabled 'usb')) { return }
    Write-SectionHeader 'USB & Peripheral Devices' ([char]0x1F50C)

    # USB hubs and devices
    $usbDevices = Get-CimInstance Win32_USBControllerDevice -ErrorAction SilentlyContinue
    $usbPnP     = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
                  Where-Object { $_.PNPClass -in @('USB','HIDClass','Keyboard','Mouse','Printer','Image','Media') }

    Write-Line '  Connected USB/HID devices:' -Fg DarkGray
    $problemDevices = 0
    foreach ($dev in $usbPnP | Sort-Object PNPClass, Caption) {
        $errCode = $dev.ConfigManagerErrorCode
        $level   = if ($errCode -eq 0) { 'ok' } else { 'crit' }
        $errStr  = if ($errCode -ne 0) { "  [ERROR $errCode]" } else { '' }
        Write-KV "  [$($dev.PNPClass)] $($dev.Caption)" $errStr $level
        if ($errCode -ne 0) {
            $problemDevices++
            Add-Issue -Level 'crit' -Category 'USB/Peripheral' -Message "Device '$($dev.Caption)' has Device Manager error code $errCode." -ScorePenalty 10
        }
    }

    if ($usbPnP.Count -eq 0) {
        Write-Line '  No USB/HID devices found.' -Fg DarkGray
    }

    # Check for devices with error codes across ALL device classes
    Write-Line ''
    Write-Line '  All devices with errors (Device Manager):' -Fg DarkGray
    $allErrDevs = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
                  Where-Object { $_.ConfigManagerErrorCode -ne 0 }
    if ($allErrDevs) {
        foreach ($d in $allErrDevs | Sort-Object ConfigManagerErrorCode) {
            $errMsg = switch ($d.ConfigManagerErrorCode) {
                1  { 'Not configured correctly' }
                3  { 'Driver damaged or missing' }
                10 { 'Cannot start (Code 10)' }
                28 { 'Driver not installed' }
                43 { 'USB device stopped — Code 43' }
                45 { 'Not connected (Code 45)' }
                default { "Error code $($d.ConfigManagerErrorCode)" }
            }
            Write-KV "  $($d.Caption)" $errMsg 'crit'
            Add-Issue -Level 'crit' -Category 'Device' -Message "$($d.Caption): $errMsg" -ScorePenalty 10
        }
    } else {
        Write-Line '  No device errors found ✓' -Fg Green
    }

    # Printers
    Write-Line ''
    Write-Line '  Printers:' -Fg DarkGray
    $printers = Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue
    if ($printers) {
        foreach ($p in $printers) {
            $status   = switch ($p.PrinterStatus) {
                3 {'Idle'} 4 {'Printing'} 5 {'Warming Up'} 6 {'Stopped'}
                7 {'Offline'} default {"Status $($p.PrinterStatus)"}
            }
            $pLevel = if ($p.PrinterStatus -in @(3,4)) { 'ok' } else { 'warn' }
            $default = if ($p.Default) { ' [DEFAULT]' } else { '' }
            Write-KV "  $($p.Name)$default" $status $pLevel
            if ($p.PrinterStatus -eq 7) {
                Add-Issue -Level 'warn' -Category 'Printer' -Message "Printer '$($p.Name)' is offline." -ScorePenalty 5
            }
        }
    } else {
        Write-Line '  No printers installed.' -Fg DarkGray
    }

    Add-JsonKey 'device_errors' $problemDevices
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Audio
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionAudio {
    if (-not (Test-SectionEnabled 'audio')) { return }
    Write-SectionHeader 'Audio Devices' ([char]0x1F508)

    $audioDevices = Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue
    if (-not $audioDevices) {
        Write-Line '  No audio devices found.' -Fg DarkGray
        Add-Issue -Level 'warn' -Category 'Audio' -Message 'No audio devices detected.' -ScorePenalty 5
        return
    }

    foreach ($a in $audioDevices) {
        $statusOk = $a.Status -eq 'OK'
        $level    = if ($statusOk) { 'ok' } else { 'crit' }
        Write-KV "  $($a.Caption)" $a.Status $level
        Write-KV "    Manufacturer" $a.Manufacturer
        if (-not $statusOk) {
            Add-Issue -Level 'crit' -Category 'Audio' -Message "Audio device '$($a.Caption)' status: $($a.Status)." -ScorePenalty 10
        }
    }

    # Audio service status
    $audiosvc = Get-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
    if ($audiosvc) {
        $level = if ($audiosvc.Status -eq 'Running') { 'ok' } else { 'crit' }
        Write-KV '  Windows Audio service' $audiosvc.Status $level
        if ($audiosvc.Status -ne 'Running') {
            Add-Issue -Level 'crit' -Category 'Audio' -Message 'Windows Audio service is not running.' -ScorePenalty 15
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Display / Monitors
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionDisplay {
    if (-not (Test-SectionEnabled 'display')) { return }
    Write-SectionHeader 'Display / Monitors' ([char]0x1F4BB)

    # Connected monitors via WMI
    $monitors = Get-CimInstance -Namespace 'root/wmi' -ClassName WmiMonitorID -ErrorAction SilentlyContinue
    if ($monitors) {
        Write-Line '  Connected monitors:' -Fg DarkGray
        foreach ($m in $monitors) {
            $mfr    = ([char[]]($m.ManufacturerName  | Where-Object { $_ -ne 0 }) -join '')
            $pname  = ([char[]]($m.ProductCodeID     | Where-Object { $_ -ne 0 }) -join '')
            $serial = ([char[]]($m.SerialNumberID    | Where-Object { $_ -ne 0 }) -join '')
            $year   = $m.YearOfManufacture
            Write-KV "  $mfr $pname" "S/N: $serial  Year: $year"
        }
    } else {
        Write-Line '  No monitor EDID data available (may need admin).' -Fg DarkGray
    }

    # Current resolution per GPU
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    Write-Line ''
    Write-Line '  Current display modes:' -Fg DarkGray
    foreach ($g in $gpus) {
        if ($g.CurrentHorizontalResolution -gt 0) {
            Write-KV "  $($g.Name)" "$($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution) @ $($g.CurrentRefreshRate) Hz  [$($g.CurrentBitsPerPixel) bpp]"
        }
    }

    # Check refresh rate — very low refresh rate could indicate driver/monitor issue
    foreach ($g in $gpus) {
        if ($g.CurrentRefreshRate -gt 0 -and $g.CurrentRefreshRate -lt 30) {
            Add-Issue -Level 'warn' -Category 'Display' -Message "GPU '$($g.Name)' running at unusually low refresh rate ($($g.CurrentRefreshRate) Hz) — possible driver issue." -ScorePenalty 5
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Battery / Power
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionBattery {
    if (-not (Test-SectionEnabled 'battery')) { return }
    Write-SectionHeader 'Battery / Power' ([char]0x1F50B)

    $batteries = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    if (-not $batteries) {
        Write-Line '  No battery detected (desktop or battery not reporting).' -Fg DarkGray
        return
    }

    foreach ($b in $batteries) {
        Write-KV '  Name'           $b.Name
        Write-KV '  Status'         $b.Status
        $chargePct = $b.EstimatedChargeRemaining
        $chargeLevel = Get-Threshold (100 - $chargePct) 50 80   # invert so low charge = warn
        Write-Bar '  Charge'        $chargePct 30 $(if ($chargePct -ge 50) {'ok'} elseif ($chargePct -ge 20) {'warn'} else {'crit'})
        Write-KV '  Est. runtime'   "$($b.EstimatedRunTime) minutes"
        Write-KV '  Voltage'        "$($b.DesignVoltage) mV"

        $chgStatus = switch ($b.BatteryStatus) {
            1 {'Discharging'} 2 {'AC connected'} 3 {'Fully charged'}
            4 {'Low'} 5 {'Critical'} 6 {'Charging'}
            7 {'Charging & High'} 8 {'Charging & Low'} 9 {'Charging & Critical'}
            10 {'Undefined'} 11 {'Partially Charged'} default {"$($b.BatteryStatus)"}
        }
        Write-KV '  Battery state'  $chgStatus

        if ($b.BatteryStatus -eq 5) {
            Add-Issue -Level 'crit' -Category 'Battery' -Message "Battery is at CRITICAL level ($chargePct%)." -ScorePenalty 20
        } elseif ($b.BatteryStatus -eq 4 -or $chargePct -le 20) {
            Add-Issue -Level 'warn' -Category 'Battery' -Message "Battery charge low ($chargePct%)." -ScorePenalty 10
        }
    }

    # Power plan
    try {
        $powerPlan = powercfg /getactivescheme 2>$null
        Write-Line ''
        Write-KV '  Active power plan' ($powerPlan -replace 'Power Scheme GUID.*GUID:\s*\S+\s*','')
        if ($powerPlan -match 'Power saver') {
            Add-Issue -Level 'info' -Category 'Battery' -Message 'Power Saver plan active — may limit performance.' -ScorePenalty 0
        }
    } catch { }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Driver Health
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionDrivers {
    if (-not (Test-SectionEnabled 'drivers')) { return }
    Write-SectionHeader 'Driver Health' ([char]0x1F527)

    # Unsigned drivers
    Write-Line '  Unsigned / problem drivers:' -Fg DarkGray
    try {
        $drivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
                   Where-Object { $_.DeviceName }

        # Unsigned drivers
        $unsigned = $drivers | Where-Object { $_.IsSigned -eq $false }
        if ($unsigned) {
            foreach ($d in $unsigned | Sort-Object DeviceName | Select-Object -First 10) {
                Write-KV "  [UNSIGNED] $($d.DeviceName)" $d.DriverVersion 'warn'
                Add-Issue -Level 'warn' -Category 'Drivers' -Message "Unsigned driver: $($d.DeviceName) v$($d.DriverVersion)" -ScorePenalty 5
            }
        } else {
            Write-Line '  All enumerated drivers are signed ✓' -Fg Green
        }

        # Very old drivers (> 3 years)
        Write-Line ''
        Write-Line '  Drivers older than 3 years:' -Fg DarkGray
        $oldDrivers = $drivers | Where-Object {
            $_.DriverDate -and $_.DriverDate -lt (Get-Date).AddYears(-3)
        } | Sort-Object DriverDate | Select-Object -First 10

        if ($oldDrivers) {
            foreach ($d in $oldDrivers) {
                Write-KV "  $($d.DeviceName)" "$($d.DriverVersion) ($($d.DriverDate.ToString('yyyy-MM-dd')))" 'warn'
            }
        } else {
            Write-Line '  No drivers older than 3 years found ✓' -Fg Green
        }

    } catch {
        Write-Line '  (Driver enumeration requires elevation)' -Fg DarkGray
    }

    # driverquery for missing drivers
    Write-Line ''
    Write-Line '  Checking for missing drivers via Device Manager:' -Fg DarkGray
    $missingDrivers = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
                      Where-Object { $_.ConfigManagerErrorCode -in @(1, 3, 28) }
    if ($missingDrivers) {
        foreach ($d in $missingDrivers) {
            $reason = switch ($d.ConfigManagerErrorCode) {
                1  { 'Not configured' }
                3  { 'Driver corrupted/missing' }
                28 { 'Driver not installed' }
            }
            Write-KV "  $($d.Caption)" $reason 'crit'
            Add-Issue -Level 'crit' -Category 'Drivers' -Message "$($d.Caption): $reason" -ScorePenalty 15
        }
    } else {
        Write-Line '  No missing driver entries found ✓' -Fg Green
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Startup Programs
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionStartup {
    if (-not (Test-SectionEnabled 'startup')) { return }
    Write-SectionHeader 'Startup Programs' ([char]0x1F680)

    $startupItems = @()

    # Registry run keys
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )
    foreach ($rp in $regPaths) {
        try {
            $entries = Get-ItemProperty -Path $rp -ErrorAction Stop
            $entries.PSObject.Properties |
            Where-Object { $_.Name -notin @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider') } |
            ForEach-Object {
                $startupItems += [pscustomobject]@{
                    Name     = $_.Name
                    Command  = $_.Value
                    Location = ($rp -replace 'HKLM:|HKCU:', '')
                }
            }
        } catch { }
    }

    # Startup folder
    @($env:APPDATA + '\Microsoft\Windows\Start Menu\Programs\Startup',
      $env:PROGRAMDATA + '\Microsoft\Windows\Start Menu\Programs\Startup') |
    ForEach-Object {
        if (Test-Path $_) {
            Get-ChildItem $_ -ErrorAction SilentlyContinue | ForEach-Object {
                $startupItems += [pscustomobject]@{
                    Name     = $_.Name
                    Command  = $_.FullName
                    Location = 'Startup Folder'
                }
            }
        }
    }

    Write-KV 'Total startup items' $startupItems.Count $(if ($startupItems.Count -gt 20) {'warn'} else {'ok'})

    if ($startupItems.Count -gt 20) {
        Add-Issue -Level 'warn' -Category 'Startup' -Message "$($startupItems.Count) startup items found — excessive startup load may slow boot." -ScorePenalty 5
    }

    Write-Line ''
    Write-Line ('  {0,-35} {1,-20} {2}' -f 'Name', 'Location', 'Command') -Fg DarkGray
    foreach ($s in $startupItems | Sort-Object Location, Name | Select-Object -First 30) {
        $cmdShort = $s.Command.Substring(0, [Math]::Min(50, $s.Command.Length))
        Write-Line ('  {0,-35} {1,-20} {2}' -f `
            $s.Name.Substring(0,[Math]::Min(34,$s.Name.Length)),
            $s.Location.Substring(0,[Math]::Min(19,$s.Location.Length)),
            $cmdShort)
    }

    # Scheduled task startup items
    Write-Line ''
    Write-Line '  Scheduled tasks set to run at logon/startup:' -Fg DarkGray
    try {
        $logonTasks = Get-ScheduledTask -ErrorAction Stop |
                      Where-Object {
                          $_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'Logon|Boot' }
                      } | Select-Object -First 15
        foreach ($t in $logonTasks) {
            Write-KV "  $($t.TaskName)" "$($t.TaskPath) [$($t.State)]"
        }
        if (-not $logonTasks) {
            Write-Line '  None found.' -Fg DarkGray
        }
    } catch { Write-Line '  (requires elevation)' -Fg DarkGray }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Reliability Monitor
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionReliability {
    if (-not (Test-SectionEnabled 'reliability')) { return }
    Write-SectionHeader 'Reliability & Event Health' ([char]0x1F4C8)

    # Windows Reliability Monitor score via WMI
    try {
        $reliability = Get-CimInstance -Namespace 'root/cimv2' -ClassName Win32_ReliabilityStabilityMetrics `
                       -ErrorAction Stop | Sort-Object StartMeasurementDate -Descending | Select-Object -First 1
        if ($reliability) {
            $score    = [math]::Round($reliability.SystemStabilityIndex, 2)
            $scoreLevel = if ($score -ge 7) { 'ok' } elseif ($score -ge 4) { 'warn' } else { 'crit' }
            Write-KV 'Reliability score (0-10)' "$score / 10" $scoreLevel
            Write-KV 'As of'                    $reliability.StartMeasurementDate.ToString('yyyy-MM-dd')
            if ($score -lt 4) {
                Add-Issue -Level 'crit' -Category 'Reliability' -Message "Windows Reliability score is very low ($score/10) — investigate recent crashes." -ScorePenalty 20
            } elseif ($score -lt 7) {
                Add-Issue -Level 'warn' -Category 'Reliability' -Message "Windows Reliability score is below average ($score/10)." -ScorePenalty 8
            }
        }
    } catch { Write-Line '  Reliability index unavailable (needs elevation).' -Fg DarkGray }

    # Recent reliability events
    Write-Line ''
    Write-Line '  Recent crash/error events from Reliability Monitor:' -Fg DarkGray
    try {
        $relEvents = Get-CimInstance -Namespace 'root/cimv2' -ClassName Win32_ReliabilityRecords `
                     -ErrorAction Stop |
                     Where-Object { $_.SourceName -and $_.EventIdentifier -in @(0,1,2) } |
                     Sort-Object TimeGenerated -Descending |
                     Select-Object -First 10
        foreach ($re in $relEvents) {
            $typeStr = switch ($re.EventIdentifier) {
                0 { 'Application crash' }
                1 { 'Application hang' }
                2 { 'Windows Error Reporting' }
                default { "Event $($re.EventIdentifier)" }
            }
            Write-Line "  [$($re.TimeGenerated.ToString('yyyy-MM-dd HH:mm'))]  $typeStr  — $($re.SourceName)" -Fg DarkYellow
        }
        if (-not $relEvents) { Write-Line '  No recent reliability events ✓' -Fg Green }
    } catch { Write-Line '  (unavailable or requires elevation)' -Fg DarkGray }

    # Recent BSOD / system crash (Event 41 = unexpected shutdown, 1001 = BugCheck)
    Write-Line ''
    Write-Line '  Recent BSODs / unexpected shutdowns (Event 41/1001, last 7 days):' -Fg DarkGray
    try {
        $cutoff = (Get-Date).AddDays(-7)
        $bsods  = Get-WinEvent -LogName 'System' -MaxEvents 200 -ErrorAction Stop |
                  Where-Object { $_.Id -in @(41, 1001) -and $_.TimeCreated -ge $cutoff }
        if ($bsods) {
            foreach ($b in $bsods | Select-Object -First 5) {
                $msg = $b.Message -replace '\s+', ' '
                Write-Line "  [$($b.TimeCreated.ToString('yyyy-MM-dd HH:mm'))]  ID $($b.Id)  $($msg.Substring(0,[Math]::Min(80,$msg.Length)))" -Fg Red
            }
            Add-Issue -Level 'crit' -Category 'Reliability' -Message "$($bsods.Count) BSOD/unexpected shutdown event(s) in last 7 days." -ScorePenalty 25
        } else {
            Write-Line '  No BSOD or unexpected shutdowns in last 7 days ✓' -Fg Green
        }
    } catch { Write-Line '  (System event log requires elevation)' -Fg DarkGray }

    # Application crashes
    Write-Line ''
    Write-Line '  Application crashes (Event 1000, last 24h):' -Fg DarkGray
    try {
        $cutoff     = (Get-Date).AddHours(-24)
        $appCrashes = Get-WinEvent -LogName 'Application' -MaxEvents 100 -ErrorAction Stop |
                      Where-Object { $_.Id -eq 1000 -and $_.TimeCreated -ge $cutoff }
        if ($appCrashes) {
            foreach ($ac in $appCrashes | Select-Object -First 5) {
                $msg = $ac.Message -replace '\s+', ' '
                Write-Line "  [$($ac.TimeCreated.ToString('HH:mm:ss'))]  $($msg.Substring(0,[Math]::Min(80,$msg.Length)))" -Fg Yellow
            }
            Add-Issue -Level 'warn' -Category 'Reliability' -Message "$($appCrashes.Count) application crash(es) in last 24h." -ScorePenalty 5
        } else {
            Write-Line '  No application crashes in last 24 hours ✓' -Fg Green
        }
    } catch { Write-Line '  (Application log requires elevation)' -Fg DarkGray }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Services
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionServices {
    if (-not (Test-SectionEnabled 'services')) { return }
    Write-SectionHeader 'Services' ([char]0x26A1)

    $stopped = Get-Service -ErrorAction SilentlyContinue |
               Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' }

    if ($stopped) {
        Write-KV 'Auto-start not running' "$($stopped.Count) service(s)" 'warn'
        Write-Line '  ─ Name ──────────────────────── DisplayName ──────────────────────' -Fg DarkGray
        foreach ($s in $stopped | Sort-Object Name | Select-Object -First 15) {
            Write-Line ('  {0,-35} {1}' -f $s.Name, $s.DisplayName) -Fg Yellow
        }
        if ($stopped.Count -gt 0) {
            Add-Issue -Level 'warn' -Category 'Services' -Message "$($stopped.Count) auto-start service(s) are not running." -ScorePenalty 5
        }
    } else {
        Write-KV 'Auto-start services' 'all running ✓' 'ok'
    }

    $allSvcs    = Get-Service -ErrorAction SilentlyContinue
    $runCount   = ($allSvcs | Where-Object { $_.Status -eq 'Running' } | Measure-Object).Count
    $stoppedAll = ($allSvcs | Where-Object { $_.Status -eq 'Stopped' } | Measure-Object).Count
    Write-Line ''
    Write-KV 'Running services'  $runCount
    Write-KV 'Stopped services'  $stoppedAll

    # Critical services
    Write-Line ''
    Write-Line '  Critical service health:' -Fg DarkGray
    $criticalSvcs = [ordered]@{
        'wuauserv'     = 'Windows Update'
        'WinDefend'    = 'Windows Defender'
        'EventLog'     = 'Event Log'
        'Dnscache'     = 'DNS Client'
        'Winmgmt'      = 'WMI'
        'Schedule'     = 'Task Scheduler'
        'SamSs'        = 'Security Accounts Manager'
        'LanmanServer' = 'File Sharing (Server)'
        'Spooler'      = 'Print Spooler'
        'BITS'         = 'Background Intel. Transfer'
        'CryptSvc'     = 'Cryptographic Services'
        'W32Time'      = 'Windows Time'
        'Audiosrv'     = 'Windows Audio'
        'Themes'       = 'Themes'
    }
    foreach ($sn in $criticalSvcs.Keys) {
        $svc = Get-Service -Name $sn -ErrorAction SilentlyContinue
        if ($svc) {
            $sl = if ($svc.Status -eq 'Running') { 'ok' } else { 'crit' }
            Write-KV "  $($criticalSvcs[$sn])" $svc.Status $sl
            if ($svc.Status -ne 'Running' -and $sn -in @('WinDefend','EventLog','Winmgmt')) {
                Add-Issue -Level 'crit' -Category 'Services' -Message "Critical service '$($criticalSvcs[$sn])' is not running." -ScorePenalty 20
            }
        }
    }

    # Recent critical event log entries
    Write-Line ''
    Write-Line '  Recent critical/error events (System log, last 6h):' -Fg DarkGray
    try {
        $cutoff = (Get-Date).AddHours(-6)
        $evts   = Get-WinEvent -LogName System -MaxEvents 200 -ErrorAction Stop |
                  Where-Object { $_.Level -le 2 -and $_.TimeCreated -ge $cutoff } |
                  Select-Object -First 8
        if ($evts) {
            foreach ($e in $evts) {
                $lvlStr = if ($e.Level -eq 1) { 'CRIT' } else { 'ERR ' }
                $msg    = ($e.Message -replace '\s+', ' ').Substring(0, [Math]::Min(90, $e.Message.Length))
                Write-Line "  [$lvlStr] $($e.TimeCreated.ToString('HH:mm:ss'))  $($e.Id)  $msg" -Fg $(if ($e.Level -eq 1) { [ConsoleColor]::Red } else { [ConsoleColor]::DarkYellow })
            }
        } else {
            Write-Line '  None in the last 6 hours ✓' -Fg Green
        }
    } catch { Write-Line '  (event log requires Administrator)' -Fg DarkGray }

    # Boot duration
    try {
        $bootEvt = Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' `
                   -MaxEvents 1 -ErrorAction Stop | Where-Object { $_.Id -eq 100 }
        if ($bootEvt) {
            $bootMs = ([xml]$bootEvt.ToXml()).Event.EventData.Data |
                      Where-Object { $_.Name -eq 'BootDuration' } |
                      Select-Object -ExpandProperty '#text'
            $bootSec = [math]::Round($bootMs/1000, 1)
            Write-Line ''
            Write-KV 'Last boot duration' "$bootSec seconds" $(if ($bootSec -gt 120) {'warn'} else {'ok'})
            if ($bootSec -gt 120) {
                Add-Issue -Level 'warn' -Category 'Performance' -Message "Slow boot time: $bootSec seconds. Consider reviewing startup items." -ScorePenalty 5
            }
        }
    } catch { }

    Add-JsonKey 'services_auto_stopped' ($stopped | Measure-Object).Count
    Add-JsonKey 'services_running'      $runCount
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Top Processes
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionProcesses {
    if (-not (Test-SectionEnabled 'processes')) { return }
    Write-SectionHeader 'Top Processes' ([char]0x1F4CA)

    $allProcs = Get-Process -ErrorAction SilentlyContinue

    Write-Line '  By CPU time:' -Fg DarkGray
    Write-Line ('  {0,-8} {1,-30} {2,-12} {3,-12} {4}' -f 'PID','Name','CPU(s)','WS(MB)','Threads') -Fg DarkGray
    $allProcs | Sort-Object CPU -Descending | Select-Object -First 10 | ForEach-Object {
        Write-Line ('  {0,-8} {1,-30} {2,-12} {3,-12} {4}' -f `
            $_.Id,
            $_.ProcessName.Substring(0,[Math]::Min(29,$_.ProcessName.Length)),
            [math]::Round($_.CPU, 1),
            [math]::Round($_.WorkingSet64 / 1MB, 1),
            $_.Threads.Count)
    }

    Write-Line ''
    Write-Line '  By memory (working set):' -Fg DarkGray
    Write-Line ('  {0,-8} {1,-30} {2,-12} {3,-12} {4}' -f 'PID','Name','CPU(s)','WS(MB)','Handles') -Fg DarkGray
    $allProcs | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 | ForEach-Object {
        Write-Line ('  {0,-8} {1,-30} {2,-12} {3,-12} {4}' -f `
            $_.Id,
            $_.ProcessName.Substring(0,[Math]::Min(29,$_.ProcessName.Length)),
            [math]::Round($_.CPU, 1),
            [math]::Round($_.WorkingSet64 / 1MB, 1),
            $_.HandleCount)
    }

    Write-Line ''
    Write-KV 'Total processes' ($allProcs | Measure-Object).Count
    Write-KV 'Total threads'   ($allProcs | Measure-Object -Property Threads.Count -Sum).Sum

    # Not responding
    $hung = $allProcs | Where-Object { $_.Responding -eq $false }
    $hungCount = ($hung | Measure-Object).Count
    if ($hungCount -gt 0) {
        Write-KV 'Not responding' $hungCount 'warn'
        $hung | Select-Object -First 5 | ForEach-Object {
            Write-Line "  ⚠  $($_.ProcessName) (PID $($_.Id))" -Fg Yellow
        }
        Add-Issue -Level 'warn' -Category 'Processes' -Message "$hungCount process(es) not responding." -ScorePenalty 5
    } else {
        Write-KV 'Not responding' '0 ✓' 'ok'
    }

    # High handle count (possible leak)
    $highHandles = $allProcs | Where-Object { $_.HandleCount -gt 5000 }
    foreach ($hp in $highHandles | Select-Object -First 3) {
        Write-Line "  ⚠  $($hp.ProcessName) (PID $($hp.Id)) has $($hp.HandleCount) handles — possible handle leak." -Fg Yellow
        Add-Issue -Level 'warn' -Category 'Processes' -Message "$($hp.ProcessName) has $($hp.HandleCount) handles — possible resource leak." -ScorePenalty 5
    }

    Add-JsonKey 'process_count' ($allProcs | Measure-Object).Count
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Security Snapshot
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionSecurity {
    if (-not (Test-SectionEnabled 'security')) { return }
    Write-SectionHeader 'Security Snapshot' ([char]0x1F512)

    # Windows Defender
    Write-Line '  Windows Defender:' -Fg DarkGray
    try {
        $mpStatus  = Get-MpComputerStatus -ErrorAction Stop
        $avEnabled = $mpStatus.AntivirusEnabled
        $rtEnabled = $mpStatus.RealTimeProtectionEnabled
        $sigAge    = ((Get-Date) - $mpStatus.AntivirusSignatureLastUpdated).Days
        Write-KV '  Antivirus enabled'    ($avEnabled ? 'Yes' : 'No')  ($avEnabled ? 'ok' : 'crit')
        Write-KV '  Real-time protection' ($rtEnabled ? 'Yes' : 'No')  ($rtEnabled ? 'ok' : 'crit')
        Write-KV '  Signature age (days)' $sigAge                      (Get-Threshold $sigAge 3 7)
        Write-KV '  Last scan type'       $mpStatus.LastFullScanSource
        Write-KV '  Last quick scan'      ($mpStatus.QuickScanStartTime ? $mpStatus.QuickScanStartTime.ToString('yyyy-MM-dd') : 'Never')
        Write-KV '  Last full scan'       ($mpStatus.FullScanStartTime  ? $mpStatus.FullScanStartTime.ToString('yyyy-MM-dd')  : 'Never')

        if (-not $avEnabled)  { Add-Issue -Level 'crit' -Category 'Security' -Message 'Windows Defender antivirus is DISABLED.' -ScorePenalty 30 }
        if (-not $rtEnabled)  { Add-Issue -Level 'crit' -Category 'Security' -Message 'Windows Defender real-time protection is DISABLED.' -ScorePenalty 30 }
        if ($sigAge -ge 7)    { Add-Issue -Level 'crit' -Category 'Security' -Message "Antivirus signatures are $sigAge days old — update immediately." -ScorePenalty 15 }
        elseif ($sigAge -ge 3){ Add-Issue -Level 'warn' -Category 'Security' -Message "Antivirus signatures are $sigAge days old." -ScorePenalty 5 }

        if (-not $mpStatus.FullScanStartTime -or $mpStatus.FullScanStartTime -lt (Get-Date).AddDays(-30)) {
            Add-Issue -Level 'warn' -Category 'Security' -Message 'No Windows Defender full scan in last 30 days.' -ScorePenalty 5
        }
    } catch {
        Write-Line '  (Windows Defender WMI unavailable — may need elevation)' -Fg DarkGray
    }

    # Firewall
    Write-Line ''
    Write-Line '  Windows Firewall:' -Fg DarkGray
    try {
        $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($fp in $fwProfiles) {
            $fl = if ($fp.Enabled) { 'ok' } else { 'crit' }
            Write-KV "  $($fp.Name)" ($fp.Enabled ? 'Enabled ✓' : 'DISABLED ✗') $fl
            if (-not $fp.Enabled) {
                Add-Issue -Level 'crit' -Category 'Security' -Message "Firewall profile '$($fp.Name)' is DISABLED." -ScorePenalty 20
            }
        }
    } catch { Write-Line '  (requires elevation)' -Fg DarkGray }

    # UAC
    Write-Line ''
    try {
        $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
                -Name 'EnableLUA' -ErrorAction Stop).EnableLUA
        Write-KV 'UAC (EnableLUA)' ($uac -eq 1 ? 'Enabled ✓' : 'DISABLED ✗') ($uac -eq 1 ? 'ok' : 'crit')
        if ($uac -ne 1) { Add-Issue -Level 'crit' -Category 'Security' -Message 'UAC is disabled.' -ScorePenalty 20 }
    } catch { Write-KV 'UAC' 'unable to read registry' }

    # Secure Boot
    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction Stop
        Write-KV 'Secure Boot' ($sb ? 'Enabled ✓' : 'Disabled') ($sb ? 'ok' : 'warn')
        if (-not $sb) { Add-Issue -Level 'warn' -Category 'Security' -Message 'Secure Boot is disabled.' -ScorePenalty 10 }
    } catch { Write-KV 'Secure Boot' 'N/A (Legacy BIOS)' 'dim' }

    # BitLocker
    Write-Line ''
    Write-Line '  BitLocker:' -Fg DarkGray
    try {
        $blv = Get-BitLockerVolume -ErrorAction Stop
        foreach ($v in $blv) {
            $bl = if ($v.ProtectionStatus -eq 'On') { 'ok' } else { 'warn' }
            Write-KV "  $($v.MountPoint)" "$($v.ProtectionStatus)  [$($v.EncryptionMethod)]" $bl
        }
    } catch { Write-Line '  (BitLocker query requires elevation)' -Fg DarkGray }

    # Local Administrators
    Write-Line ''
    Write-Line '  Local Administrators:' -Fg DarkGray
    try {
        $admins = Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop
        foreach ($a in $admins) {
            $isBuiltin = ($a.Name -like '*\Administrator' -or $a.Name -like '*\Admin')
            Write-KV "  $($a.Name)" $a.ObjectClass $(if ($isBuiltin) { 'warn' } else { 'info' })
        }
    } catch { Write-Line '  (local group query unavailable)' -Fg DarkGray }

    # Suspicious scheduled tasks
    Write-Line ''
    Write-Line '  Suspicious scheduled tasks (SYSTEM, non-system path):' -Fg DarkGray
    try {
        $suspTasks = Get-ScheduledTask -ErrorAction Stop |
            Where-Object {
                $_.Principal.UserId -like '*SYSTEM*' -and
                $_.Actions | Where-Object {
                    $_.Execute -and
                    $_.Execute -notlike '*system32*' -and
                    $_.Execute -notlike '*syswow64*' -and
                    $_.Execute -notlike '*windows*'
                }
            } | Select-Object -First 10
        if ($suspTasks) {
            foreach ($t in $suspTasks) {
                Write-Line "  ⚠  $($t.TaskName)  [$($t.TaskPath)]" -Fg Yellow
                Add-Issue -Level 'warn' -Category 'Security' -Message "Suspicious scheduled task: '$($t.TaskName)' runs as SYSTEM from non-system path." -ScorePenalty 10
            }
        } else { Write-Line '  None found ✓' -Fg Green }
    } catch { Write-Line '  (requires elevation)' -Fg DarkGray }

    # Failed logons
    Write-Line ''
    Write-Line '  Recent failed logons (last 24h):' -Fg DarkGray
    try {
        $cutoff = (Get-Date).AddHours(-24)
        $failed = Get-WinEvent -LogName Security -MaxEvents 500 -ErrorAction Stop |
                  Where-Object { $_.Id -eq 4625 -and $_.TimeCreated -ge $cutoff }
        $fCount = ($failed | Measure-Object).Count
        if ($fCount -gt 0) {
            Write-KV '  Failed logon count' $fCount (Get-Threshold $fCount 5 20)
            if ($fCount -ge 20) {
                Add-Issue -Level 'crit' -Category 'Security' -Message "High number of failed logons in 24h: $fCount. Possible brute-force attack." -ScorePenalty 20
            } elseif ($fCount -ge 5) {
                Add-Issue -Level 'warn' -Category 'Security' -Message "$fCount failed logon attempts in last 24h." -ScorePenalty 5
            }
            $failed | Select-Object -First 5 | ForEach-Object {
                $xml  = [xml]$_.ToXml()
                $user = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
                $src  = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'IpAddress' }).'#text'
                Write-Line "  $($_.TimeCreated.ToString('HH:mm:ss'))  user=$user  src=$src" -Fg $(if ($fCount -ge 20) { [ConsoleColor]::Red } else { [ConsoleColor]::Yellow })
            }
        } else {
            Write-Line '  None in the last 24 hours ✓' -Fg Green
        }
    } catch { Write-Line '  (Security log requires Administrator)' -Fg DarkGray }

    # SMBv1 check
    Write-Line ''
    try {
        $smbv1 = Get-SmbServerConfiguration -ErrorAction Stop | Select-Object -ExpandProperty EnableSMB1Protocol
        Write-KV 'SMBv1 protocol' ($smbv1 ? 'ENABLED (security risk)' : 'Disabled ✓') ($smbv1 ? 'crit' : 'ok')
        if ($smbv1) { Add-Issue -Level 'crit' -Category 'Security' -Message 'SMBv1 is enabled — this is a known attack vector (EternalBlue/WannaCry).' -ScorePenalty 20 }
    } catch { }

    # Remote Desktop check
    try {
        $rdpEnabled = (Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
                       -Name 'fDenyTSConnections' -ErrorAction Stop).fDenyTSConnections -eq 0
        Write-KV 'Remote Desktop (RDP)' ($rdpEnabled ? 'Enabled' : 'Disabled') ($rdpEnabled ? 'info' : 'ok')
    } catch { }

    Add-JsonKey 'uac_enabled' ($uac -eq 1)
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Pending Updates
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionUpdates {
    if (-not (Test-SectionEnabled 'updates')) { return }
    Write-SectionHeader 'Pending Updates' ([char]0x1F4E6)

    try {
        $updateSession  = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        Write-Line '  Searching for updates...' -Fg DarkGray
        $searchResult   = $updateSearcher.Search('IsInstalled=0 and Type=''Software''')
        $updateCount    = $searchResult.Updates.Count

        if ($updateCount -eq 0) {
            Write-KV 'Windows Update' 'Up to date ✓' 'ok'
        } else {
            Write-KV 'Pending updates' "$updateCount update(s)" (Get-Threshold $updateCount 1 10)
            $critCount = 0
            foreach ($u in $searchResult.Updates) {
                $isSec  = $u.Categories | Where-Object { $_.Name -like '*Security*' }
                $isCrit = $u.MsrcSeverity -eq 'Critical'
                if ($isSec -or $isCrit) { $critCount++ }
                $tag  = if ($isCrit) { '[CRITICAL]' } elseif ($isSec) { '[Security]' } else { '[Update]  ' }
                Write-Line "  $tag $($u.Title.Substring(0,[Math]::Min(70,$u.Title.Length)))" -Fg $(if ($isCrit) { [ConsoleColor]::Red } elseif ($isSec) { [ConsoleColor]::Yellow } else { [ConsoleColor]::Gray })
            }
            if ($critCount -gt 0) {
                Add-Issue -Level 'crit' -Category 'Updates' -Message "$critCount critical/security update(s) pending." -ScorePenalty 20
            } else {
                Add-Issue -Level 'warn' -Category 'Updates' -Message "$updateCount update(s) pending." -ScorePenalty 5
            }
        }

        $history = $updateSearcher.QueryHistory(0, 1)
        if ($history.Count -gt 0) {
            Write-KV 'Last update installed' $history.Item(0).Date.ToString('yyyy-MM-dd HH:mm')
        }
        Add-JsonKey 'updates_pending' $updateCount
    } catch {
        Write-Line '  Windows Update COM unavailable — try running as Administrator.' -Fg DarkGray
    }

    # Winget
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Line ''
        Write-Line '  Winget outdated packages:' -Fg DarkGray
        try {
            $wgOut   = & winget upgrade --include-unknown 2>&1 | Select-String '^\w'
            $wgCount = [Math]::Max(0, ($wgOut | Measure-Object).Count - 2)
            Write-KV '  Winget updates' $(if ($wgCount -gt 0) { "$wgCount package(s)" } else { 'up to date ✓' }) $(if ($wgCount -gt 0) {'warn'} else {'ok'})
            if ($wgCount -gt 0) { Add-Issue -Level 'info' -Category 'Updates' -Message "$wgCount winget package(s) have updates available." -ScorePenalty 0 }
        } catch { Write-Line '  (winget query failed)' -Fg DarkGray }
    }

    # Chocolatey
    $choco = Get-Command choco -ErrorAction SilentlyContinue
    if ($choco) {
        Write-Line ''
        Write-Line '  Chocolatey outdated:' -Fg DarkGray
        try {
            $chocoOut   = & choco outdated --no-color 2>&1
            $chocoCount = ($chocoOut | Where-Object { $_ -match '\|' } | Measure-Object).Count
            Write-KV '  Choco outdated' $(if ($chocoCount -gt 0) { "$chocoCount package(s)" } else { 'up to date ✓' }) $(if ($chocoCount -gt 0) {'warn'} else {'ok'})
        } catch { Write-Line '  (choco query failed)' -Fg DarkGray }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Deep Event Log Analysis
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionEventLog {
    if (-not (Test-SectionEnabled 'eventlog')) { return }
    Write-SectionHeader 'Deep Event Log Analysis' ([char]0x1F4DD)

    $channels = [ordered]@{
        'System'      = @{ MaxEvents=500; Levels=@(1,2) }
        'Application' = @{ MaxEvents=500; Levels=@(1,2) }
        'Security'    = @{ MaxEvents=200; Levels=@(0)   }   # level 0 = all audit
        'Microsoft-Windows-Kernel-Power/Operational'     = @{ MaxEvents=50; Levels=@(1,2) }
        'Microsoft-Windows-Kernel-IO/Operational'        = @{ MaxEvents=50; Levels=@(1,2) }
        'Microsoft-Windows-Storage-Storport/Operational' = @{ MaxEvents=50; Levels=@(1,2) }
        'Microsoft-Windows-WHEA-Logger/Operational'      = @{ MaxEvents=50; Levels=@(1,2) }
    }

    $cutoff   = (Get-Date).AddHours(-24)
    $allFound = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($ch in $channels.Keys) {
        try {
            $cfg    = $channels[$ch]
            $events = Get-WinEvent -LogName $ch -MaxEvents $cfg.MaxEvents -ErrorAction Stop |
                      Where-Object { $_.TimeCreated -ge $cutoff -and ($cfg.Levels -contains 0 -or $cfg.Levels -contains $_.Level) }
            foreach ($e in $events) {
                $allFound.Add([pscustomobject]@{
                    Time    = $e.TimeCreated
                    Channel = $ch
                    Id      = $e.Id
                    Level   = $e.Level
                    Message = ($e.Message -replace '\s+',' ').Substring(0,[Math]::Min(100,$e.Message.Length))
                })
            }
        } catch { }
    }

    # WHEA hardware errors (machine check exceptions, memory ECC, PCIe errors)
    Write-Line ''
    Write-Line '  Hardware Error (WHEA) events (last 24h):' -Fg DarkGray
    $wheaEvents = $allFound | Where-Object { $_.Channel -like '*WHEA*' }
    if ($wheaEvents) {
        foreach ($w in $wheaEvents | Select-Object -First 10) {
            Write-Line "  [$($w.Time.ToString('HH:mm:ss'))]  ID $($w.Id)  $($w.Message)" -Fg Red
        }
        Add-Issue -Level 'crit' -Category 'Hardware' -Message "$($wheaEvents.Count) WHEA hardware error(s) in last 24h — possible failing CPU, RAM, or PCIe device." -ScorePenalty 25
    } else {
        Write-Line '  No WHEA hardware errors ✓' -Fg Green
    }

    # Kernel power events (unexpected power loss)
    Write-Line ''
    Write-Line '  Kernel Power events (last 24h):' -Fg DarkGray
    $kernelPwr = $allFound | Where-Object { $_.Channel -like '*Kernel-Power*' }
    if ($kernelPwr) {
        foreach ($k in $kernelPwr | Select-Object -First 5) {
            Write-Line "  [$($k.Time.ToString('HH:mm:ss'))]  ID $($k.Id)  $($k.Message)" -Fg Yellow
        }
        Add-Issue -Level 'warn' -Category 'Power' -Message "$($kernelPwr.Count) kernel power event(s) in last 24h." -ScorePenalty 10
    } else {
        Write-Line '  No kernel power events ✓' -Fg Green
    }

    # Storage errors
    Write-Line ''
    Write-Line '  Storage/IO errors (last 24h):' -Fg DarkGray
    $storageErr = $allFound | Where-Object { $_.Channel -like '*Storport*' -or $_.Channel -like '*Kernel-IO*' }
    if ($storageErr) {
        foreach ($s in $storageErr | Select-Object -First 5) {
            Write-Line "  [$($s.Time.ToString('HH:mm:ss'))]  $($s.Channel)  ID $($s.Id)  $($s.Message)" -Fg Yellow
        }
        Add-Issue -Level 'warn' -Category 'Disk' -Message "$($storageErr.Count) storage/IO error(s) in last 24h — disk may be failing." -ScorePenalty 15
    } else {
        Write-Line '  No storage errors ✓' -Fg Green
    }

    # Summary table
    Write-Line ''
    Write-Line '  Event summary (last 24h, Errors/Criticals per log):' -Fg DarkGray
    $grouped = $allFound | Where-Object { $_.Level -in @(1,2) } | Group-Object Channel
    foreach ($g in $grouped | Sort-Object Count -Descending) {
        $lvl = if ($g.Count -ge 10) {'crit'} elseif ($g.Count -ge 3) {'warn'} else {'ok'}
        Write-KV "  $($g.Name.Split('/')[-1])" "$($g.Count) event(s)" $lvl
    }
    if (-not $grouped) {
        Write-Line '  No errors or criticals in any monitored log ✓' -Fg Green
    }

    Add-JsonKey 'whea_errors_24h' $wheaEvents.Count
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: PCIe / Expansion Bus
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionPCIe {
    if (-not (Test-SectionEnabled 'pcie')) { return }
    Write-SectionHeader 'PCIe / PnP Bus Devices' ([char]0x1F50C)

    # All PnP devices grouped by class
    $allPnP = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
              Where-Object { $_.PNPClass -and $_.Status }

    $classSummary = $allPnP | Group-Object PNPClass | Sort-Object Count -Descending
    Write-Line '  Device class summary:' -Fg DarkGray
    foreach ($cls in $classSummary | Select-Object -First 15) {
        Write-KV "  $($cls.Name)" "$($cls.Count) device(s)"
    }

    # Problem devices (any error code != 0)
    Write-Line ''
    Write-Line '  All devices with problems:' -Fg DarkGray
    $problemDevs = $allPnP | Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
                   Sort-Object ConfigManagerErrorCode
    if ($problemDevs) {
        foreach ($pd in $problemDevs) {
            $errDesc = switch ($pd.ConfigManagerErrorCode) {
                1  { 'Misconfigured'            }
                3  { 'Driver corrupted/missing' }
                10 { 'Device cannot start'      }
                12 { 'Cannot find resources'    }
                14 { 'Needs restart'            }
                18 { 'Reinstall drivers'        }
                19 { 'Registry corrupted'       }
                21 { 'Being removed'            }
                22 { 'Disabled'                 }
                24 { 'Not present'              }
                28 { 'Driver not installed'     }
                31 { 'Not working properly'     }
                32 { 'Driver service disabled'  }
                43 { 'USB device error (43)'    }
                45 { 'Not connected'            }
                52 { 'Unsigned driver blocked'  }
                default { "Error $($pd.ConfigManagerErrorCode)" }
            }
            $lvl = if ($pd.ConfigManagerErrorCode -in @(3,10,19,28,43,52)) { 'crit' } else { 'warn' }
            Write-KV "  [$($pd.PNPClass)] $($pd.Caption)" $errDesc $lvl
            Add-Issue -Level $lvl -Category 'PCIe/Device' -Message "$($pd.Caption): $errDesc (code $($pd.ConfigManagerErrorCode))" -ScorePenalty $(if ($lvl -eq 'crit') {15} else {5})
        }
    } else {
        Write-Line '  No device problems detected ✓' -Fg Green
    }

    # Recently changed devices (installed/removed last 7 days via setupapi)
    Write-Line ''
    Write-Line '  Recently installed devices (last 7 days, SetupAPI):' -Fg DarkGray
    $setupLog = "$env:SystemRoot\INF\setupapi.dev.log"
    if (Test-Path $setupLog) {
        try {
            $cutoff     = (Get-Date).AddDays(-7).ToString('yyyy/MM/dd')
            $recentDevs = Select-String -Path $setupLog -Pattern 'Device Install.*>>>.*<<<' -ErrorAction Stop |
                          Where-Object { $_.Line -match '\d{4}/\d{2}/\d{2}' } |
                          Select-Object -Last 10
            if ($recentDevs) {
                foreach ($rd in $recentDevs) {
                    Write-Line "  $($rd.Line.Trim().Substring(0,[Math]::Min(90,$rd.Line.Length)))" -Fg DarkGray
                }
            } else {
                Write-Line '  No recent device installs found in log.' -Fg DarkGray
            }
        } catch { Write-Line '  (SetupAPI log parse failed)' -Fg DarkGray }
    } else {
        Write-Line '  SetupAPI log not found.' -Fg DarkGray
    }

    Add-JsonKey 'pci_problem_devices' ($problemDevs | Measure-Object).Count
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Network Deep Dive
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionNetworkDeep {
    if (-not (Test-SectionEnabled 'networking')) { return }
    Write-SectionHeader 'Network Deep Diagnostics' ([char]0x1F4E1)

    # Adapter error counters
    Write-Line '  Adapter error counters:' -Fg DarkGray
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
    foreach ($a in $adapters) {
        try {
            $stats = Get-NetAdapterStatistics -Name $a.Name -ErrorAction Stop
            $rxErr = $stats.ReceivedPacketsWithErrors
            $txErr = $stats.OutboundPacketsWithErrors
            $rxDrop= $stats.ReceivedDiscardedPackets
            $txDrop= $stats.OutboundDiscardedPackets
            $lvl   = if (($rxErr + $txErr) -gt 100) {'crit'} elseif (($rxErr + $txErr) -gt 0) {'warn'} else {'ok'}
            Write-KV "  $($a.Name)" "RxErr=$rxErr  TxErr=$txErr  RxDrop=$rxDrop  TxDrop=$txDrop" $lvl
            if (($rxErr + $txErr) -gt 100) {
                Add-Issue -Level 'crit' -Category 'Network' -Message "Adapter '$($a.Name)' has $($rxErr+$txErr) packet errors — cable, NIC, or driver issue." -ScorePenalty 15
            } elseif (($rxErr + $txErr) -gt 0) {
                Add-Issue -Level 'warn' -Category 'Network' -Message "Adapter '$($a.Name)' has some packet errors (Rx=$rxErr, Tx=$txErr)." -ScorePenalty 5
            }
        } catch { }
    }

    # Link speed check
    Write-Line ''
    Write-Line '  Link speed:' -Fg DarkGray
    foreach ($a in $adapters) {
        $speedMbps = if ($a.LinkSpeed) { [math]::Round($a.LinkSpeed / 1MB, 0) } else { 0 }
        $lvl       = if ($speedMbps -lt 100 -and $speedMbps -gt 0) {'warn'} else {'ok'}
        Write-KV "  $($a.Name)" "$speedMbps Mbps" $lvl
        if ($speedMbps -gt 0 -and $speedMbps -lt 100) {
            Add-Issue -Level 'warn' -Category 'Network' -Message "Adapter '$($a.Name)' negotiated at only $speedMbps Mbps — check cable or switch port." -ScorePenalty 5
        }
    }

    # DNS resolution test
    Write-Line ''
    Write-Line '  DNS resolution test:' -Fg DarkGray
    $dnsHosts = @('www.microsoft.com', 'www.google.com', 'cloudflare.com')
    foreach ($h in $dnsHosts) {
        try {
            $result = Resolve-DnsName $h -ErrorAction Stop | Select-Object -First 1
            Write-KV "  $h" "$($result.IPAddress) ✓" 'ok'
        } catch {
            Write-KV "  $h" 'FAILED' 'crit'
            Add-Issue -Level 'crit' -Category 'Network' -Message "DNS resolution failed for $h — DNS may be broken." -ScorePenalty 15
        }
    }

    # TCP retransmit rate via netstat
    Write-Line ''
    Write-Line '  TCP statistics:' -Fg DarkGray
    try {
        $tcpStats = Get-NetTCPStatistics -ErrorAction Stop
        foreach ($ts in $tcpStats) {
            Write-KV '  Segments sent'        $ts.SegmentsSent
            Write-KV '  Segments received'    $ts.SegmentsReceived
            Write-KV '  Segments retransmitted' $ts.SegmentsRetransmitted
            $retransPct = if ($ts.SegmentsSent -gt 0) { [math]::Round($ts.SegmentsRetransmitted / $ts.SegmentsSent * 100, 2) } else { 0 }
            $retransLvl = if ($retransPct -gt 5) {'crit'} elseif ($retransPct -gt 1) {'warn'} else {'ok'}
            Write-KV '  Retransmit rate'      "$retransPct %" $retransLvl
            if ($retransPct -gt 5) {
                Add-Issue -Level 'crit' -Category 'Network' -Message "TCP retransmit rate $retransPct% is critically high — unstable network connection." -ScorePenalty 20
            } elseif ($retransPct -gt 1) {
                Add-Issue -Level 'warn' -Category 'Network' -Message "TCP retransmit rate $retransPct% is elevated." -ScorePenalty 5
            }
        }
    } catch { Write-Line '  (TCP stats unavailable)' -Fg DarkGray }

    # IPv6 connectivity
    Write-Line ''
    $ipv6Ok = Test-Connection 'ipv6.google.com' -Count 1 -Quiet -ErrorAction SilentlyContinue
    Write-KV '  IPv6 connectivity' $(if ($ipv6Ok) { 'reachable ✓' } else { 'no IPv6 route (info only)' }) $(if ($ipv6Ok) {'ok'} else {'dim'})

    # Wi-Fi signal strength
    $wifiAdapters = Get-NetAdapter -ErrorAction SilentlyContinue |
                    Where-Object { $_.PhysicalMediaType -like '*802.11*' -or $_.InterfaceDescription -like '*Wi-Fi*' -or $_.InterfaceDescription -like '*Wireless*' }
    if ($wifiAdapters) {
        Write-Line ''
        Write-Line '  Wi-Fi signal (netsh):' -Fg DarkGray
        try {
            $netsh   = netsh wlan show interfaces 2>$null
            $ssid    = ($netsh | Select-String 'SSID\s+:') -replace '.*:\s*',''
            $signal  = ($netsh | Select-String 'Signal\s+:') -replace '.*:\s*',''
            $radioTy = ($netsh | Select-String 'Radio type\s+:') -replace '.*:\s*',''
            $channel = ($netsh | Select-String 'Channel\s+:') -replace '.*:\s*',''
            if ($ssid) {
                Write-KV '  SSID'       $ssid.Trim()
                Write-KV '  Signal'     $signal.Trim() $(if ($signal -match '([0-9]+)' -and [int]$Matches[1] -lt 50) {'warn'} else {'ok'})
                Write-KV '  Radio type' $radioTy.Trim()
                Write-KV '  Channel'    $channel.Trim()
                if ($signal -match '([0-9]+)' -and [int]$Matches[1] -lt 30) {
                    Add-Issue -Level 'warn' -Category 'Network' -Message "Wi-Fi signal is weak ($([int]$Matches[1])%) — consider moving closer to AP or checking antenna." -ScorePenalty 5
                }
            }
        } catch { Write-Line '  (netsh wlan unavailable)' -Fg DarkGray }
    }

    # Proxy settings
    Write-Line ''
    Write-Line '  Proxy configuration:' -Fg DarkGray
    try {
        $proxy = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ($proxy.ProxyEnable -eq 1) {
            Write-KV '  Proxy'        $proxy.ProxyServer   'warn'
            Write-KV '  Proxy bypass' $proxy.ProxyOverride
            Add-Issue -Level 'info' -Category 'Network' -Message "HTTP proxy is configured: $($proxy.ProxyServer)" -ScorePenalty 0
        } else {
            Write-KV '  Proxy' 'None (direct)' 'ok'
        }
    } catch { }

    Add-JsonKey 'wifi_signal' ($signal -replace '[^0-9]','')
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Virtualization & Hypervisor
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionVirtualization {
    if (-not (Test-SectionEnabled 'virtualization')) { return }
    Write-SectionHeader 'Virtualization & Hypervisor' ([char]0x1F4E6)

    $cs       = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $hvPresent= $cs.HypervisorPresent

    Write-KV 'Hypervisor present'  ($hvPresent ? 'Yes' : 'No') $(if ($hvPresent) {'warn'} else {'ok'})
    Write-KV 'System type'        $cs.SystemType
    Write-KV 'PC system type'     $(switch ($cs.PCSystemType) {
        1 {'Desktop'} 2 {'Mobile/Laptop'} 3 {'Workstation'} 4 {'Enterprise Server'}
        5 {'SOHO Server'} 6 {'Appliance PC'} 7 {'Performance Server'} default {"Type $($cs.PCSystemType)"}
    })

    # VM detection heuristics
    Write-Line ''
    Write-Line '  VM/Container detection:' -Fg DarkGray
    $vmHints = [ordered]@{}

    # BIOS/board strings
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $mb   = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    if ($bios.Manufacturer -match 'VRTUAL|VMware|Xen|Hyper|QEMU|innotek|Bochs') { $vmHints['BIOS vendor']   = $bios.Manufacturer }
    if ($mb.Manufacturer   -match 'VMware|Xen|QEMU|Microsoft|VirtualBox')        { $vmHints['Board vendor']  = $mb.Manufacturer  }
    if ($bios.SerialNumber -match 'VMware|QEMU|Xen')                             { $vmHints['BIOS serial']   = $bios.SerialNumber }

    # Services
    $vmServices = @('vmbus','vmickvpexchange','vpcbus','xenfilt','vmmemctl','VBoxService')
    foreach ($vs in $vmServices) {
        $svc = Get-Service -Name $vs -ErrorAction SilentlyContinue
        if ($svc) { $vmHints["Service '$vs'"] = $svc.Status }
    }

    # Drivers
    $vmDrivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
                 Where-Object { $_.DeviceName -match 'VMware|VirtualBox|Xen|Hyper-V|QEMU' }
    foreach ($vd in $vmDrivers | Select-Object -First 3) {
        $vmHints["Driver '$($vd.DeviceName)'"] = $vd.DriverVersion
    }

    if ($vmHints.Count -gt 0) {
        Write-Line '  VM indicators detected:' -Fg Yellow
        foreach ($k in $vmHints.Keys) {
            Write-KV "  $k" $vmHints[$k] 'warn'
        }
        Add-Issue -Level 'info' -Category 'Virtualization' -Message "System appears to be running inside a virtual machine ($($vmHints.Count) indicator(s))." -ScorePenalty 0
    } else {
        Write-Line '  No VM indicators detected (likely bare metal) ✓' -Fg Green
    }

    # Hyper-V role
    Write-Line ''
    Write-Line '  Hyper-V / WSL features:' -Fg DarkGray
    $hvFeatures = @('Microsoft-Hyper-V','Microsoft-Hyper-V-Management-PowerShell',
                    'Microsoft-Windows-Subsystem-Linux','VirtualMachinePlatform',
                    'HypervisorPlatform')
    foreach ($f in $hvFeatures) {
        try {
            $feat = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop
            if ($feat) {
                Write-KV "  $f" $feat.State $(if ($feat.State -eq 'Enabled') {'info'} else {'dim'})
            }
        } catch { }
    }

    # Running VMs (Hyper-V, if host)
    try {
        $vms = Get-VM -ErrorAction Stop
        if ($vms) {
            Write-Line ''
            Write-Line '  Running Hyper-V VMs:' -Fg DarkGray
            foreach ($vm in $vms) {
                $vmMem = Format-Bytes ($vm.MemoryAssigned)
                Write-KV "  $($vm.Name)" "$($vm.State)  CPUs=$($vm.ProcessorCount)  RAM=$vmMem" $(if ($vm.State -eq 'Running') {'info'} else {'dim'})
            }
        }
    } catch { }

    Add-JsonKey 'hypervisor_present' $hvPresent
    Add-JsonKey 'vm_indicators'      $vmHints.Count
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Time Sync
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionTime {
    if (-not (Test-SectionEnabled 'time')) { return }
    Write-SectionHeader 'Time Synchronization' ([char]0x23F0)

    # W32tm status
    Write-Line '  Windows Time service:' -Fg DarkGray
    try {
        $w32status = w32tm /query /status 2>$null
        if ($w32status) {
            $leapIndicator = ($w32status | Select-String 'Leap Indicator')?.Line
            $stratum       = ($w32status | Select-String 'Stratum')?.Line
            $sourceStr     = ($w32status | Select-String 'Source')?.Line
            $lastSync      = ($w32status | Select-String 'Last Successful Sync')?.Line
            $offset        = ($w32status | Select-String 'Phase Offset')?.Line

            if ($stratum)   { Write-KV '  Stratum'         ($stratum  -replace '.*:\s*','').Trim() }
            if ($sourceStr) { Write-KV '  Source'          ($sourceStr -replace '.*:\s*','').Trim() }
            if ($lastSync)  { Write-KV '  Last sync'       ($lastSync  -replace '.*:\s*','').Trim() }
            if ($offset) {
                $offsetVal = ($offset -replace '.*:\s*','').Trim()
                Write-KV '  Phase offset'    $offsetVal $(if ($offsetVal -match '(\d+\.\d+)s' -and [double]$Matches[1] -gt 5) {'crit'} else {'ok'})
                if ($offsetVal -match '(\d+\.\d+)s' -and [double]$Matches[1] -gt 60) {
                    Add-Issue -Level 'crit' -Category 'Time' -Message "Time offset is more than 60 seconds ($offsetVal) — may affect authentication and certificates." -ScorePenalty 15
                } elseif ($offsetVal -match '(\d+\.\d+)s' -and [double]$Matches[1] -gt 5) {
                    Add-Issue -Level 'warn' -Category 'Time' -Message "Time offset is elevated ($offsetVal)." -ScorePenalty 5
                }
            }
        }
    } catch { Write-Line '  (w32tm query failed)' -Fg DarkGray }

    # Check W32Time service
    $w32svc = Get-Service -Name 'W32Time' -ErrorAction SilentlyContinue
    $svcLvl = if ($w32svc.Status -eq 'Running') { 'ok' } else { 'warn' }
    Write-KV '  W32Time service' $w32svc.Status $svcLvl
    if ($w32svc.Status -ne 'Running') {
        Add-Issue -Level 'warn' -Category 'Time' -Message 'Windows Time service is not running.' -ScorePenalty 5
    }

    # NTP peers
    Write-Line ''
    Write-Line '  Configured NTP peers:' -Fg DarkGray
    try {
        $peers = w32tm /query /peers 2>$null
        if ($peers) {
            $peers | Select-Object -First 10 | ForEach-Object { Write-Line "  $_" -Fg DarkGray }
        }
    } catch { }

    # System clock vs internet comparison
    Write-Line ''
    try {
        $webTime = (Invoke-RestMethod 'http://worldtimeapi.org/api/ip' -TimeoutSec 5 -ErrorAction Stop).datetime
        $sysTime = Get-Date -Format 'o'
        $diff    = [Math]::Abs(([DateTimeOffset]::Parse($webTime) - [DateTimeOffset]::Parse($sysTime)).TotalSeconds)
        $diffLvl = if ($diff -gt 60) {'crit'} elseif ($diff -gt 5) {'warn'} else {'ok'}
        Write-KV '  Clock vs internet (sec)' ([math]::Round($diff,2)) $diffLvl
    } catch { Write-Line '  (internet time check unavailable)' -Fg DarkGray }

    Add-JsonKey 'time_source' ($sourceStr -replace '.*:\s*','')
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Network Shares & Open Files
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionShares {
    if (-not (Test-SectionEnabled 'shares')) { return }
    Write-SectionHeader 'Network Shares & Open Sessions' ([char]0x1F5C2)

    # Local shares
    Write-Line '  Local network shares:' -Fg DarkGray
    try {
        $shares = Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -notmatch '^\w+\$$' }
        if ($shares) {
            foreach ($s in $shares) {
                Write-KV "  \\$env:COMPUTERNAME\$($s.Name)" "$($s.Path)  [$($s.ShareType)]"
            }
        } else {
            Write-Line '  No custom shares (admin$ and default hidden shares excluded).' -Fg DarkGray
        }
    } catch { Write-Line '  (Get-SmbShare failed — may need elevation)' -Fg DarkGray }

    # Admin shares state
    Write-Line ''
    Write-Line '  Admin shares (C$, ADMIN$, IPC$):' -Fg DarkGray
    try {
        $adminShares = Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -match '^\w+\$$' }
        foreach ($s in $adminShares) {
            Write-KV "  $($s.Name)" $s.Path 'info'
        }
    } catch { }

    # Active SMB sessions
    Write-Line ''
    Write-Line '  Active SMB sessions:' -Fg DarkGray
    try {
        $sessions = Get-SmbSession -ErrorAction Stop
        if ($sessions) {
            foreach ($sess in $sessions | Select-Object -First 10) {
                Write-KV "  $($sess.ClientComputerName)" "$($sess.ClientUserName)  Files=$($sess.NumOpens)"
            }
        } else {
            Write-Line '  No active SMB sessions.' -Fg DarkGray
        }
    } catch { Write-Line '  (SmbSession query requires elevation)' -Fg DarkGray }

    # Mapped drives
    Write-Line ''
    Write-Line '  Mapped network drives:' -Fg DarkGray
    $netDrives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayRoot -like '\\*' }
    if ($netDrives) {
        foreach ($nd in $netDrives) {
            $reachable = Test-Path $nd.Root -ErrorAction SilentlyContinue
            $lvl       = if ($reachable) { 'ok' } else { 'warn' }
            Write-KV "  $($nd.Name): → $($nd.DisplayRoot)" $(if ($reachable) { 'Connected ✓' } else { 'UNREACHABLE' }) $lvl
            if (-not $reachable) {
                Add-Issue -Level 'warn' -Category 'Shares' -Message "Mapped drive $($nd.Name): ($($nd.DisplayRoot)) is unreachable." -ScorePenalty 5
            }
        }
    } else {
        Write-Line '  No mapped network drives.' -Fg DarkGray
    }

    # Open TCP file sharing port check (445)
    $port445 = Test-NetConnection -ComputerName 'localhost' -Port 445 -InformationLevel Quiet -ErrorAction SilentlyContinue
    Write-Line ''
    Write-KV 'SMB port 445 listening' $(if ($port445) { 'Yes' } else { 'No' }) $(if ($port445) { 'info' } else { 'ok' })

    Add-JsonKey 'smb_shares' ($shares | Measure-Object).Count
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: SSL/TLS Certificates
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionCertificates {
    if (-not (Test-SectionEnabled 'certificates')) { return }
    Write-SectionHeader 'SSL/TLS Certificates' ([char]0x1F4DC)

    $stores = @('Cert:\LocalMachine\My', 'Cert:\LocalMachine\Root', 'Cert:\CurrentUser\My')
    $now    = Get-Date
    $expiringSoon   = [System.Collections.Generic.List[hashtable]]::new()
    $alreadyExpired = [System.Collections.Generic.List[hashtable]]::new()
    $weakCerts      = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($store in $stores) {
        try {
            $certs = Get-ChildItem $store -ErrorAction Stop |
                     Where-Object { $_.HasPrivateKey -or $store -like '*Root*' }
            foreach ($c in $certs) {
                $daysLeft = ($c.NotAfter - $now).Days
                $keySize  = $c.PublicKey.Key.KeySize
                $sigAlg   = $c.SignatureAlgorithm.FriendlyName

                if ($daysLeft -lt 0) {
                    $alreadyExpired.Add(@{ Subject=$c.Subject; Store=$store; Expired=$c.NotAfter; DaysLeft=$daysLeft })
                } elseif ($daysLeft -le 30) {
                    $expiringSoon.Add(@{ Subject=$c.Subject; Store=$store; Expiry=$c.NotAfter; DaysLeft=$daysLeft })
                }

                # Weak algorithm / key size
                if ($sigAlg -match 'md5|sha1' -or ($keySize -gt 0 -and $keySize -lt 2048)) {
                    $weakCerts.Add(@{ Subject=$c.Subject; Store=$store; Alg=$sigAlg; KeySize=$keySize })
                }
            }
        } catch { }
    }

    # Expired
    Write-Line '  Expired certificates:' -Fg DarkGray
    if ($alreadyExpired.Count -gt 0) {
        foreach ($ec in $alreadyExpired | Select-Object -First 10) {
            Write-KV "  $($ec.Subject.Substring(0,[Math]::Min(50,$ec.Subject.Length)))" "Expired $([Math]::Abs($ec.DaysLeft)) days ago" 'crit'
        }
        Add-Issue -Level 'crit' -Category 'Certificates' -Message "$($alreadyExpired.Count) expired certificate(s) in personal/root stores." -ScorePenalty 10
    } else {
        Write-Line '  No expired certificates ✓' -Fg Green
    }

    # Expiring soon
    Write-Line ''
    Write-Line '  Certificates expiring within 30 days:' -Fg DarkGray
    if ($expiringSoon.Count -gt 0) {
        foreach ($sc in $expiringSoon | Sort-Object DaysLeft) {
            Write-KV "  $($sc.Subject.Substring(0,[Math]::Min(50,$sc.Subject.Length)))" "Expires in $($sc.DaysLeft) days" $(if ($sc.DaysLeft -le 7) {'crit'} else {'warn'})
        }
        Add-Issue -Level 'warn' -Category 'Certificates' -Message "$($expiringSoon.Count) certificate(s) expiring within 30 days." -ScorePenalty 5
    } else {
        Write-Line '  No certificates expiring within 30 days ✓' -Fg Green
    }

    # Weak certs
    Write-Line ''
    Write-Line '  Weak algorithm/key-size certificates:' -Fg DarkGray
    if ($weakCerts.Count -gt 0) {
        foreach ($wc in $weakCerts | Select-Object -First 10) {
            Write-KV "  $($wc.Subject.Substring(0,[Math]::Min(45,$wc.Subject.Length)))" "Alg=$($wc.Alg)  KeySize=$($wc.KeySize)b" 'warn'
        }
        Add-Issue -Level 'warn' -Category 'Certificates' -Message "$($weakCerts.Count) certificate(s) use weak algorithms or small key sizes." -ScorePenalty 5
    } else {
        Write-Line '  No weak certificates detected ✓' -Fg Green
    }

    # Certificate store counts
    Write-Line ''
    Write-Line '  Store counts:' -Fg DarkGray
    foreach ($store in $stores) {
        try {
            $count = (Get-ChildItem $store -ErrorAction Stop | Measure-Object).Count
            Write-KV "  $($store.Replace('Cert:\',''))" "$count certificate(s)"
        } catch { }
    }

    Add-JsonKey 'certs_expired'       $alreadyExpired.Count
    Add-JsonKey 'certs_expiring_soon' $expiringSoon.Count
    Add-JsonKey 'certs_weak'          $weakCerts.Count
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Disk I/O Performance
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionDiskIO {
    if (-not (Test-SectionEnabled 'diskio')) { return }
    Write-SectionHeader 'Disk I/O Performance' ([char]0x1F504)

    Write-Line '  Sampling disk I/O counters (2 seconds)...' -Fg DarkGray
    try {
        $samples = Get-Counter '\PhysicalDisk(*)\*' -SampleInterval 2 -MaxSamples 1 -ErrorAction Stop
        $counters = $samples.CounterSamples | Where-Object { $_.InstanceName -ne '_total' }

        $diskGroups = $counters | Group-Object { $_.InstanceName }
        foreach ($dg in $diskGroups | Sort-Object Name) {
            Write-Line ''
            Write-Line "  Disk: $($dg.Name)" -Fg White

            $readBps   = ($dg.Group | Where-Object { $_.Path -like '*Disk Read Bytes*'  }).CookedValue
            $writeBps  = ($dg.Group | Where-Object { $_.Path -like '*Disk Write Bytes*' }).CookedValue
            $queueLen  = ($dg.Group | Where-Object { $_.Path -like '*Current Disk Queue*' }).CookedValue
            $readLatMs = ($dg.Group | Where-Object { $_.Path -like '*Avg. Disk sec/Read*'  }).CookedValue * 1000
            $wrLatMs   = ($dg.Group | Where-Object { $_.Path -like '*Avg. Disk sec/Write*' }).CookedValue * 1000
            $pctTime   = ($dg.Group | Where-Object { $_.Path -like '*% Disk Time*' }).CookedValue

            Write-KV '  Read speed'    (Format-Bytes $readBps) + '/s'
            Write-KV '  Write speed'   (Format-Bytes $writeBps) + '/s'
            Write-KV '  Queue depth'   ([math]::Round($queueLen, 1)) $(if ($queueLen -gt 4) {'crit'} elseif ($queueLen -gt 1) {'warn'} else {'ok'})
            Write-KV '  Read latency'  "$([math]::Round($readLatMs,1)) ms" $(if ($readLatMs -gt 20) {'crit'} elseif ($readLatMs -gt 10) {'warn'} else {'ok'})
            Write-KV '  Write latency' "$([math]::Round($wrLatMs,1)) ms"   $(if ($wrLatMs   -gt 20) {'crit'} elseif ($wrLatMs   -gt 10) {'warn'} else {'ok'})
            Write-Bar '  % Disk time'  ([int]$pctTime) 20 $(if ($pctTime -gt 80) {'crit'} elseif ($pctTime -gt 50) {'warn'} else {'ok'})

            if ($queueLen -gt 4) {
                Add-Issue -Level 'crit' -Category 'DiskIO' -Message "Disk '$($dg.Name)' queue depth $([math]::Round($queueLen,1)) — I/O bottleneck." -ScorePenalty 15
            }
            if ($readLatMs -gt 20 -or $wrLatMs -gt 20) {
                Add-Issue -Level 'warn' -Category 'DiskIO' -Message "Disk '$($dg.Name)' high latency (read=$([math]::Round($readLatMs,1))ms write=$([math]::Round($wrLatMs,1))ms)." -ScorePenalty 10
            }
        }
    } catch {
        Write-Line '  (Disk I/O counters unavailable — run as Administrator)' -Fg DarkGray
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Memory Performance (pool, paged, non-paged)
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionMemoryPool {
    if (-not (Test-SectionEnabled 'mempool')) { return }
    Write-SectionHeader 'Memory Pool & Commit' ([char]0x1F9E0)

    try {
        # Pool counters
        $pagedPool    = (Get-Counter '\Memory\Pool Paged Bytes'         -ErrorAction Stop).CounterSamples[0].CookedValue
        $nonPagedPool = (Get-Counter '\Memory\Pool Nonpaged Bytes'      -ErrorAction Stop).CounterSamples[0].CookedValue
        $commitLimit  = (Get-Counter '\Memory\Commit Limit'             -ErrorAction Stop).CounterSamples[0].CookedValue
        $committedMem = (Get-Counter '\Memory\Committed Bytes'          -ErrorAction Stop).CounterSamples[0].CookedValue
        $pageFaults   = (Get-Counter '\Memory\Page Faults/sec'          -ErrorAction Stop).CounterSamples[0].CookedValue
        $hardFaults   = (Get-Counter '\Memory\Page Reads/sec'           -ErrorAction Stop).CounterSamples[0].CookedValue
        $cacheBytes   = (Get-Counter '\Memory\Cache Bytes'              -ErrorAction Stop).CounterSamples[0].CookedValue
        $availBytes   = (Get-Counter '\Memory\Available Bytes'          -ErrorAction Stop).CounterSamples[0].CookedValue
        $sysCodeBytes = (Get-Counter '\Memory\System Code Total Bytes'  -ErrorAction Stop).CounterSamples[0].CookedValue

        $commitPct = [int]($committedMem / $commitLimit * 100)
        $commitLvl = Get-Threshold $commitPct 75 90

        Write-KV 'Pool paged'          (Format-Bytes $pagedPool)
        Write-KV 'Pool non-paged'      (Format-Bytes $nonPagedPool)
        Write-KV 'Committed'           (Format-Bytes $committedMem)
        Write-KV 'Commit limit'        (Format-Bytes $commitLimit)
        Write-Bar 'Commit charge'       $commitPct 30 $commitLvl
        Write-KV 'Available'           (Format-Bytes $availBytes) $(if ($availBytes -lt 256MB) {'crit'} elseif ($availBytes -lt 512MB) {'warn'} else {'ok'})
        Write-KV 'Cache size'          (Format-Bytes $cacheBytes)
        Write-KV 'System code'         (Format-Bytes $sysCodeBytes)
        Write-KV 'Page faults/sec'     ([math]::Round($pageFaults,1)) $(if ($pageFaults -gt 1000) {'warn'} else {'ok'})
        Write-KV 'Hard page faults/sec'([math]::Round($hardFaults,1)) $(if ($hardFaults -gt 5) {'crit'} elseif ($hardFaults -gt 0) {'warn'} else {'ok'})

        if ($commitPct -ge 90) {
            Add-Issue -Level 'crit' -Category 'Memory' -Message "Commit charge at $commitPct% — system is running out of virtual memory." -ScorePenalty 20
        }
        if ($availBytes -lt 256MB) {
            Add-Issue -Level 'crit' -Category 'Memory' -Message "Available RAM critically low: $(Format-Bytes $availBytes)." -ScorePenalty 20
        }
        if ($hardFaults -gt 5) {
            Add-Issue -Level 'crit' -Category 'Memory' -Message "Hard page faults $([math]::Round($hardFaults,1))/sec — system is actively paging (RAM exhausted)." -ScorePenalty 20
        }
    } catch {
        Write-Line '  (Memory pool counters unavailable)' -Fg DarkGray
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Environment & Path Sanity
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionEnvironment {
    if (-not (Test-SectionEnabled 'environment')) { return }
    Write-SectionHeader 'Environment & Path Sanity' ([char]0x1F527)

    # PATH duplicate / phantom entries
    Write-Line '  PATH entries:' -Fg DarkGray
    $pathEntries  = $env:PATH -split ';' | Where-Object { $_ }
    $missing      = [System.Collections.Generic.List[string]]::new()
    $duplicates   = $pathEntries | Group-Object | Where-Object { $_.Count -gt 1 }

    foreach ($p in $pathEntries) {
        $exists = Test-Path $p -ErrorAction SilentlyContinue
        $lvl    = if ($exists) { 'ok' } else { 'warn' }
        Write-KV "  $($p.Substring(0,[Math]::Min(55,$p.Length)))" $(if ($exists) { '✓' } else { 'MISSING' }) $lvl
        if (-not $exists) { $missing.Add($p) }
    }

    if ($missing.Count -gt 0) {
        Add-Issue -Level 'warn' -Category 'Environment' -Message "$($missing.Count) PATH entry/entries point to non-existent directories." -ScorePenalty 5
    }
    if ($duplicates) {
        Write-Line ''
        Write-Line "  Duplicate PATH entries ($($duplicates.Count)):" -Fg Yellow
        $duplicates | ForEach-Object { Write-Line "  $($_.Name)" -Fg Yellow }
        Add-Issue -Level 'info' -Category 'Environment' -Message "$($duplicates.Count) duplicate PATH entry/entries found." -ScorePenalty 0
    }

    # Key environment variables
    Write-Line ''
    Write-Line '  Key environment variables:' -Fg DarkGray
    $envVars = @('TEMP','TMP','USERPROFILE','SystemRoot','ProgramFiles','OneDrive','JAVA_HOME','PYTHON')
    foreach ($ev in $envVars) {
        $val = [System.Environment]::GetEnvironmentVariable($ev)
        if ($val) {
            $exists = Test-Path $val -ErrorAction SilentlyContinue
            $lvl    = if ($exists) { 'ok' } else { 'warn' }
            Write-KV "  $ev" "$($val.Substring(0,[Math]::Min(50,$val.Length)))" $lvl
        }
    }

    # TEMP writable?
    $tempPath = $env:TEMP
    Write-Line ''
    try {
        $testFile = Join-Path $tempPath "syscheck_$([System.IO.Path]::GetRandomFileName())"
        [IO.File]::WriteAllText($testFile, 'test')
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        Write-KV '  TEMP writable' 'Yes ✓' 'ok'
    } catch {
        Write-KV '  TEMP writable' 'NO — applications may fail' 'crit'
        Add-Issue -Level 'crit' -Category 'Environment' -Message "TEMP directory '$tempPath' is not writable." -ScorePenalty 15
    }

    # PowerShell version & execution policy
    Write-Line ''
    Write-KV 'PowerShell version'    $PSVersionTable.PSVersion.ToString()
    try {
        $execPolicy = Get-ExecutionPolicy -ErrorAction Stop
        $epLvl      = switch ($execPolicy) {
            'Unrestricted' { 'warn' } 'Bypass' { 'crit' } default { 'ok' }
        }
        Write-KV 'Execution policy'    $execPolicy $epLvl
        if ($execPolicy -eq 'Bypass') {
            Add-Issue -Level 'crit' -Category 'Security' -Message "PowerShell execution policy is Bypass — any script can run." -ScorePenalty 15
        } elseif ($execPolicy -eq 'Unrestricted') {
            Add-Issue -Level 'warn' -Category 'Security' -Message "PowerShell execution policy is Unrestricted." -ScorePenalty 5
        }
    } catch { }

    # .NET versions
    Write-Line ''
    Write-Line '  Installed .NET runtimes:' -Fg DarkGray
    $dotnetPath = "$env:SystemRoot\Microsoft.NET\Framework64"
    if (Test-Path $dotnetPath) {
        Get-ChildItem $dotnetPath -Directory | Sort-Object Name |
            ForEach-Object { Write-Line "  $($_.Name)" -Fg DarkGray }
    }

    Add-JsonKey 'path_missing_count' $missing.Count
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Installed Software Inventory
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionSoftware {
    if (-not (Test-SectionEnabled 'software')) { return }
    Write-SectionHeader 'Installed Software Snapshot' ([char]0x1F4E6)

    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $apps = foreach ($rp in $regPaths) {
        try {
            Get-ItemProperty $rp -ErrorAction Stop |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
        } catch { }
    }
    $apps = $apps | Sort-Object DisplayName -Unique

    Write-KV 'Total installed apps' ($apps | Measure-Object).Count

    # Recently installed (last 30 days)
    $cutoffDate = (Get-Date).AddDays(-30).ToString('yyyyMMdd')
    $recent = $apps | Where-Object { $_.InstallDate -and $_.InstallDate -ge $cutoffDate } |
              Sort-Object InstallDate -Descending | Select-Object -First 15

    Write-Line ''
    Write-Line '  Recently installed (last 30 days):' -Fg DarkGray
    if ($recent) {
        foreach ($r in $recent) {
            Write-KV "  $($r.DisplayName.Substring(0,[Math]::Min(40,$r.DisplayName.Length)))" "$($r.InstallDate)  v$($r.DisplayVersion)"
        }
    } else {
        Write-Line '  No apps installed in last 30 days.' -Fg DarkGray
    }

    # Security software detection
    Write-Line ''
    Write-Line '  Security software detected:' -Fg DarkGray
    $secKeywords = @('antivirus','antimalware','firewall','endpoint','kaspersky','malwarebytes',
                     'bitdefender','eset','norton','mcafee','trend','avast','avg','sophos',
                     'cylance','crowdstrike','sentinel','defender','carbon black')
    $secApps = $apps | Where-Object { $n = $_.DisplayName.ToLower(); $secKeywords | Where-Object { $n -like "*$_*" } }
    if ($secApps) {
        foreach ($sa in $secApps | Select-Object -First 10) {
            Write-KV "  $($sa.DisplayName)" $sa.DisplayVersion 'info'
        }
    } else {
        Write-Line '  No third-party security software detected.' -Fg DarkGray
    }

    # EOL / known risky software
    Write-Line ''
    Write-Line '  Potentially outdated / risky software:' -Fg DarkGray
    $riskyKeywords = @('Flash Player','Silverlight','Java 6','Java 7','Java 8 Update [0-9]{1,2}[^0-9]',
                       'QuickTime','RealPlayer','WinRAR 4\.','\bAdobe Reader [0-9]\b',
                       'Internet Explorer','TeamViewer 1[0-3]\.','uTorrent')
    $riskyFound = $apps | Where-Object {
        $n = $_.DisplayName
        $riskyKeywords | Where-Object { $n -match $_ }
    }
    if ($riskyFound) {
        foreach ($rf in $riskyFound | Select-Object -First 10) {
            Write-KV "  $($rf.DisplayName)" "v$($rf.DisplayVersion)" 'warn'
            Add-Issue -Level 'warn' -Category 'Software' -Message "Potentially outdated/risky software: '$($rf.DisplayName)' v$($rf.DisplayVersion)" -ScorePenalty 5
        }
    } else {
        Write-Line '  No obviously risky software found ✓' -Fg Green
    }

    Add-JsonKey 'installed_apps_count' ($apps | Measure-Object).Count
    Add-JsonKey 'recently_installed'   ($recent | Measure-Object).Count
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Baseline Comparison
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionBaseline {
    if (-not $Baseline -or -not (Test-Path $Baseline)) { return }
    Write-SectionHeader 'Baseline Comparison' ([char]0x1F4CA)

    try {
        $base = Get-Content $Baseline -Raw | ConvertFrom-Json -ErrorAction Stop

        $comparisons = [ordered]@{
            'Health score'       = @{ Old = $base.health_score;         New = $script:HealthScore;           Unit = '' }
            'CPU load %'         = @{ Old = $base.cpu_load_pct;         New = $script:JsonData['cpu_load_pct']; Unit = '%' }
            'RAM used %'         = @{ Old = $base.mem_used_pct;         New = $script:JsonData['mem_used_pct']; Unit = '%' }
            'Process count'      = @{ Old = $base.process_count;        New = $script:JsonData['process_count']; Unit = '' }
            'Services stopped'   = @{ Old = $base.services_auto_stopped;New = $script:JsonData['services_auto_stopped']; Unit = '' }
            'Updates pending'    = @{ Old = $base.updates_pending;      New = $script:JsonData['updates_pending']; Unit = '' }
            'Device errors'      = @{ Old = $base.device_errors;        New = $script:JsonData['device_errors']; Unit = '' }
            'Certs expired'      = @{ Old = $base.certs_expired;        New = $script:JsonData['certs_expired']; Unit = '' }
            'WHEA errors 24h'    = @{ Old = $base.whea_errors_24h;      New = $script:JsonData['whea_errors_24h']; Unit = '' }
        }

        Write-Line ('  {0,-25} {1,-12} {2,-12} {3}' -f 'Metric','Baseline','Current','Change') -Fg DarkGray
        foreach ($key in $comparisons.Keys) {
            $c      = $comparisons[$key]
            $oldVal = $c.Old
            $newVal = $c.New
            if ($null -eq $oldVal -or $null -eq $newVal) { continue }
            $delta  = $newVal - $oldVal
            $sign   = if ($delta -gt 0) { '+' } elseif ($delta -lt 0) { '' } else { '=' }
            $lvl    = 'ok'
            # For metrics where higher is worse
            if ($key -in @('CPU load %','RAM used %','Services stopped','Updates pending','Device errors','Certs expired','WHEA errors 24h') -and $delta -gt 0) {
                $lvl = if ($delta -gt 10) { 'crit' } else { 'warn' }
                Add-Issue -Level $lvl -Category 'Baseline' -Message "$key regressed: was $oldVal, now $newVal ($sign$delta)." -ScorePenalty $(if ($lvl -eq 'crit') {10} else {3})
            }
            # For metrics where lower is worse (health score)
            if ($key -eq 'Health score' -and $delta -lt -10) {
                $lvl = 'crit'
                Add-Issue -Level 'crit' -Category 'Baseline' -Message "Health score dropped from $oldVal to $newVal ($delta)." -ScorePenalty 0
            }

            Write-KV "  $key" ('{0,-12} {1,-12} {2}{3}{4}' -f "$oldVal$($c.Unit)", "$newVal$($c.Unit)", $sign, $delta, $c.Unit) $lvl
        }

        $baseDate = $base.report_time ?? '(unknown date)'
        Write-Line ''
        Write-KV '  Baseline captured' $baseDate
    } catch {
        Write-Line "  Failed to load baseline from '$Baseline': $_" -Fg Red
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HEALTH SCORE & ISSUES SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
function Write-HealthSummary {
    $line = '═' * 62
    if (-not $Json) {
        $scoreColor = if ($script:HealthScore -ge 80) { [ConsoleColor]::Green }
                      elseif ($script:HealthScore -ge 50) { [ConsoleColor]::Yellow }
                      else { [ConsoleColor]::Red }

        Write-Host ''
        Write-Host $line -ForegroundColor DarkBlue
        Write-Host '  ★  HEALTH SUMMARY' -ForegroundColor White
        Write-Host $line -ForegroundColor DarkBlue
        Write-Host ''
        Write-Host "  Health Score:  " -NoNewline
        Write-Host "$($script:HealthScore) / 100" -ForegroundColor $scoreColor

        $crits = $script:Issues | Where-Object { $_.Level -eq 'crit' }
        $warns = $script:Issues | Where-Object { $_.Level -eq 'warn' }
        $infos = $script:Issues | Where-Object { $_.Level -eq 'info' }

        Write-Host "  Critical:      $($crits.Count)" -ForegroundColor $(if ($crits.Count -gt 0) { [ConsoleColor]::Red } else { [ConsoleColor]::Green })
        Write-Host "  Warnings:      $($warns.Count)" -ForegroundColor $(if ($warns.Count -gt 0) { [ConsoleColor]::Yellow } else { [ConsoleColor]::Green })
        Write-Host "  Info:          $($infos.Count)" -ForegroundColor Cyan
        Write-Host ''

        if ($script:Issues.Count -eq 0) {
            Write-Host '  ✓  No issues detected. System looks healthy!' -ForegroundColor Green
        } else {
            # Critical first
            foreach ($iss in $crits) {
                Write-Host "  ✗  [CRIT]  [$($iss.Category)]  $($iss.Message)" -ForegroundColor Red
            }
            foreach ($iss in $warns) {
                Write-Host "  ⚠  [WARN]  [$($iss.Category)]  $($iss.Message)" -ForegroundColor Yellow
            }
            foreach ($iss in $infos) {
                Write-Host "  ℹ  [INFO]  [$($iss.Category)]  $($iss.Message)" -ForegroundColor Cyan
            }
        }

        Write-Host ''
        Write-Host $line -ForegroundColor DarkBlue
        Write-Host ''
    }

    # Diagnose-mode output (only if -Diagnose was specified)
    if ($Diagnose) {
        Write-Host ''
        Write-Host '══ DIAGNOSIS REPORT ══' -ForegroundColor White
        Write-Host "  Health Score: $($script:HealthScore) / 100" -ForegroundColor $(if ($script:HealthScore -ge 80) {'Green'} elseif ($script:HealthScore -ge 50) {'Yellow'} else {'Red'})
        Write-Host ''
        if ($script:Issues.Count -eq 0) {
            Write-Host '  ✓  No issues found.' -ForegroundColor Green
        } else {
            foreach ($iss in ($script:Issues | Where-Object { $_.Level -in @('crit','warn') } | Sort-Object Level)) {
                $icon  = if ($iss.Level -eq 'crit') { '✗' } else { '⚠' }
                $color = if ($iss.Level -eq 'crit') { [ConsoleColor]::Red } else { [ConsoleColor]::Yellow }
                Write-Host "  $icon  [$($iss.Level.ToUpper())]  [$($iss.Category)]  $($iss.Message)" -ForegroundColor $color
            }
        }
        Write-Host ''
    }

    Add-JsonKey 'health_score'  $script:HealthScore
    Add-JsonKey 'issues'        ($script:Issues | ForEach-Object { [ordered]@{ level=$_.Level; category=$_.Category; message=$_.Message } })
}

# ─────────────────────────────────────────────────────────────────────────────
# HTML REPORT GENERATOR
# ─────────────────────────────────────────────────────────────────────────────
function Save-HtmlReport([string]$Path) {
    $scoreColor = if ($script:HealthScore -ge 80) { '#4caf50' } elseif ($script:HealthScore -ge 50) { '#ff9800' } else { '#f44336' }
    $issuesHtml = ($script:Issues | ForEach-Object {
        $cls = $_.Level
        "<li class='$cls'><b>[$($_.Category)]</b> $([System.Web.HttpUtility]::HtmlEncode($_.Message))</li>"
    }) -join "`n"

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SysCheck Report — $(Get-Date -Format 'yyyy-MM-dd HH:mm')</title>
<style>
  body { font-family: 'Cascadia Code', Consolas, monospace; background:#0d1117; color:#c9d1d9; margin:0; padding:20px; }
  h1 { color:#58a6ff; }
  .score { font-size:2em; font-weight:bold; color:$scoreColor; }
  .summary { background:#161b22; border:1px solid #30363d; border-radius:8px; padding:16px; margin-bottom:24px; }
  ul.issues { list-style:none; padding:0; }
  ul.issues li { padding:4px 0; }
  ul.issues li.crit::before { content:'✗ '; color:#f44336; }
  ul.issues li.warn::before { content:'⚠ '; color:#ff9800; }
  ul.issues li.info::before { content:'ℹ '; color:#58a6ff; }
  pre { background:#161b22; border:1px solid #30363d; border-radius:4px; padding:16px; overflow-x:auto; font-size:0.85em; line-height:1.5; white-space:pre; }
  .meta { color:#8b949e; font-size:0.85em; }
</style>
</head>
<body>
<h1>SysCheck v$SCRIPT_VERSION — System Health Report</h1>
<p class="meta">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Host: $env:COMPUTERNAME</p>

<div class="summary">
  <div class="score">$($script:HealthScore) / 100</div>
  <p>Health Score</p>
  <ul class="issues">
$issuesHtml
  </ul>
</div>

<h2>Full Report</h2>
<pre>$(($script:ReportLines | ForEach-Object { [System.Web.HttpUtility]::HtmlEncode($_) }) -join "`n")</pre>
</body>
</html>
"@
    $html | Set-Content -Path $Path -Encoding UTF8
    Write-Host "`nHTML report saved to: $Path" -ForegroundColor DarkGray
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN RUNNER
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-AllSections {
    if (-not $Json -and -not $Diagnose) { Write-Banner }

    # Stamp report time for baseline comparison
    Add-JsonKey 'report_time' (Get-Date -Format 'o')

    Invoke-SectionOverview

    if (Test-SectionEnabled 'cpu')            { Invoke-SectionCPU            }
    if (Test-SectionEnabled 'memory')         { Invoke-SectionMemory         }
    if (Test-SectionEnabled 'mempool')        { Invoke-SectionMemoryPool     }
    if (Test-SectionEnabled 'disk')           { Invoke-SectionDisk           }
    if (Test-SectionEnabled 'diskio')         { Invoke-SectionDiskIO         }
    if (Test-SectionEnabled 'gpu')            { Invoke-SectionGPU            }
    if (Test-SectionEnabled 'temps')          { Invoke-SectionTemps          }
    if (Test-SectionEnabled 'smart')          { Invoke-SectionSmart          }
    if (Test-SectionEnabled 'network')        { Invoke-SectionNetwork        }
    if (Test-SectionEnabled 'networking')     { Invoke-SectionNetworkDeep    }
    if (Test-SectionEnabled 'usb')            { Invoke-SectionUSB            }
    if (Test-SectionEnabled 'audio')          { Invoke-SectionAudio          }
    if (Test-SectionEnabled 'display')        { Invoke-SectionDisplay        }
    if (Test-SectionEnabled 'battery')        { Invoke-SectionBattery        }
    if (Test-SectionEnabled 'drivers')        { Invoke-SectionDrivers        }
    if (Test-SectionEnabled 'pcie')           { Invoke-SectionPCIe           }
    if (Test-SectionEnabled 'virtualization') { Invoke-SectionVirtualization }
    if (Test-SectionEnabled 'startup')        { Invoke-SectionStartup        }
    if (Test-SectionEnabled 'reliability')    { Invoke-SectionReliability    }
    if (Test-SectionEnabled 'eventlog')       { Invoke-SectionEventLog       }
    if (Test-SectionEnabled 'services')       { Invoke-SectionServices       }
    if (Test-SectionEnabled 'processes')      { Invoke-SectionProcesses      }
    if (Test-SectionEnabled 'security')       { Invoke-SectionSecurity       }
    if (Test-SectionEnabled 'time')           { Invoke-SectionTime           }
    if (Test-SectionEnabled 'shares')         { Invoke-SectionShares         }
    if (Test-SectionEnabled 'certificates')   { Invoke-SectionCertificates   }
    if (Test-SectionEnabled 'environment')    { Invoke-SectionEnvironment    }
    if (Test-SectionEnabled 'software')       { Invoke-SectionSoftware       }
    if (Test-SectionEnabled 'updates')        { Invoke-SectionUpdates        }

    # Baseline comparison (runs after all data is collected)
    Invoke-SectionBaseline

    Write-HealthSummary

    if ($Json) {
        $out = $script:JsonData | ConvertTo-Json -Depth 6
        $out
        # Optionally save as baseline
        if ($ExportBaseline) {
            $blPath = if ($Output) { [IO.Path]::ChangeExtension($Output,'.baseline.json') } else { '.\syscheck.baseline.json' }
            $out | Set-Content $blPath -Encoding UTF8
            Write-Host "Baseline exported to: $blPath" -ForegroundColor DarkGray
        }
        return
    }

    if (-not $Diagnose) {
        $line = '─' * 62
        Write-Line ''
        Write-Line $line                                                              -Fg DarkBlue
        Write-Line "  SysCheck v$SCRIPT_VERSION  |  Report complete."               -Fg DarkGray
        Write-Line "  Sections: overview,cpu,memory,mempool,disk,diskio,gpu,temps," -Fg DarkGray
        Write-Line "    smart,network,networking,usb,audio,display,battery,drivers," -Fg DarkGray
        Write-Line "    pcie,virtualization,startup,reliability,eventlog,services,"  -Fg DarkGray
        Write-Line "    processes,security,time,shares,certificates,environment,"    -Fg DarkGray
        Write-Line "    software,updates"                                             -Fg DarkGray
        Write-Line "  Tips: -Diagnose  -HtmlOutput  -Json -ExportBaseline"          -Fg DarkGray
        Write-Line $line                                                              -Fg DarkBlue
        Write-Line ''
    }

    if ($ExportBaseline -and $Json) { <# handled above #> }
    elseif ($ExportBaseline) {
        # Export a JSON baseline even without -Json flag
        Add-JsonKey 'health_score' $script:HealthScore
        $blPath = if ($Output) { [IO.Path]::ChangeExtension($Output,'.baseline.json') } else { '.\syscheck.baseline.json' }
        $script:JsonData | ConvertTo-Json -Depth 6 | Set-Content $blPath -Encoding UTF8
        Write-Host "Baseline exported to: $blPath" -ForegroundColor DarkGray
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUT / WATCH DISPATCH
# ─────────────────────────────────────────────────────────────────────────────
function Save-Report([string]$Path) {
    $script:ReportLines | Set-Content -Path $Path -Encoding UTF8
    Write-Host "`nReport saved to: $Path" -ForegroundColor DarkGray
}

if ($Watch -gt 0) {
    while ($true) {
        Clear-Host
        $script:ReportLines.Clear()
        $script:HtmlRows.Clear()
        $script:Issues.Clear()
        $script:HealthScore = 100
        $script:JsonData    = [ordered]@{}
        Invoke-AllSections
        if ($Output)     { Save-Report     $Output     }
        if ($HtmlOutput) { Save-HtmlReport $HtmlOutput }
        Write-Host "`n  Refreshing in ${Watch}s ... (Ctrl-C to stop)" -ForegroundColor DarkGray
        Start-Sleep -Seconds $Watch
    }
} else {
    Invoke-AllSections
    if ($Output)     { Save-Report     $Output     }
    if ($HtmlOutput) { Save-HtmlReport $HtmlOutput }
}
