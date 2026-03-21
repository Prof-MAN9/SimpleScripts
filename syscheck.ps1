<#
.SYNOPSIS
    SysCheck.ps1 v1.0.0 — Comprehensive Windows System Health Report

.DESCRIPTION
    Produces a detailed health report covering: System Overview, CPU, Memory,
    Disk, Temperatures (OpenHardwareMonitor/LibreHardwareMonitor), SMART,
    Network, Services, Processes, Security, and Pending Updates.

.PARAMETER Json
    Output machine-readable JSON instead of the formatted report.

.PARAMETER Watch
    Refresh every N seconds (Ctrl-C to stop). E.g. -Watch 10

.PARAMETER NoColor
    Disable colour output (useful for log files / CI).

.PARAMETER Output
    Save report to a plain-text file in addition to console output.

.PARAMETER Sections
    Comma-separated list of sections to run.
    Available: overview,cpu,memory,disk,temps,smart,network,services,processes,security,updates

.PARAMETER Version
    Show version and exit.

.PARAMETER Help
    Show this help.

.NOTES
    Run as Administrator for full data (SMART, firewall, event logs, scheduled tasks).
    PowerShell 5.1+ required. Compatible with PowerShell 7+.

.EXAMPLE
    .\SysCheck.ps1
    .\SysCheck.ps1 -Sections cpu,memory,disk
    .\SysCheck.ps1 -Watch 10
    .\SysCheck.ps1 -Json -Output C:\health.json
    .\SysCheck.ps1 -NoColor -Output C:\health.txt
#>

[CmdletBinding()]
param(
    [switch]$Json,
    [int]$Watch       = 0,
    [switch]$NoColor,
    [string]$Output   = '',
    [string]$Sections = '',
    [switch]$Version,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ─────────────────────────────────────────────────────────────────────────────
# VERSION / HELP
# ─────────────────────────────────────────────────────────────────────────────
$SCRIPT_VERSION = '1.0.0'
$SCRIPT_NAME    = $MyInvocation.MyCommand.Name

if ($Version) { Write-Host "$SCRIPT_NAME v$SCRIPT_VERSION"; exit 0 }
if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# COLOUR HELPERS
# ─────────────────────────────────────────────────────────────────────────────
# We write directly to the host with colour rather than Write-Output so that
# colour codes don't corrupt the -Output plain-text file or -Json stream.
# Plain text is accumulated in $script:ReportLines for file output.

$script:ReportLines = [System.Collections.Generic.List[string]]::new()

function Write-Line {
    param([string]$Text = '', [ConsoleColor]$Fg = [ConsoleColor]::Gray, [switch]$Plain)
    # Always save plain version
    $script:ReportLines.Add($Text)
    if ($Json) { return }   # suppress console during JSON run
    if ($NoColor -or $Plain) {
        Write-Host $Text
    } else {
        Write-Host $Text -ForegroundColor $Fg
    }
}

# Severity → ConsoleColor
function Get-LevelColor([string]$Level) {
    switch ($Level) {
        'ok'   { return [ConsoleColor]::Green  }
        'warn' { return [ConsoleColor]::Yellow }
        'crit' { return [ConsoleColor]::Red    }
        'info' { return [ConsoleColor]::Cyan   }
        'dim'  { return [ConsoleColor]::DarkGray }
        default{ return [ConsoleColor]::Gray   }
    }
}

function Write-Colored([string]$Text, [string]$Level = '') {
    # Inline coloured fragment — used inside compound lines
    if ($NoColor -or $Json) { return $Text }
    $col = Get-LevelColor $Level
    # We return an escape-free string; actual colour is via Write-Host segments
    return $Text   # caller uses Write-KV which handles coloring
}

# Section header
function Write-SectionHeader([string]$Title, [string]$Icon = '●') {
    $line = '─' * 62
    Write-Line ''
    Write-Line $line                          -Fg ([ConsoleColor]::DarkBlue)
    Write-Line "  $Icon  $Title"              -Fg ([ConsoleColor]::White)
    Write-Line $line                          -Fg ([ConsoleColor]::DarkBlue)
}

# Key-value row
function Write-KV([string]$Key, [string]$Value, [string]$Level = '') {
    $keyPad  = $Key.PadRight(28)
    $plain   = "  $keyPad $Value"
    $script:ReportLines.Add($plain)
    if ($Json) { return }
    if ($NoColor) { Write-Host $plain; return }

    Write-Host "  " -NoNewline
    Write-Host $keyPad -ForegroundColor Cyan -NoNewline
    Write-Host " " -NoNewline
    if ($Level) {
        Write-Host $Value -ForegroundColor (Get-LevelColor $Level)
    } else {
        Write-Host $Value
    }
}

# ASCII progress bar
function Get-Bar([int]$Pct, [int]$Width = 30, [string]$Level = 'ok') {
    $Pct     = [Math]::Max(0, [Math]::Min(100, $Pct))
    $filled  = [Math]::Round($Pct * $Width / 100)
    $empty   = $Width - $filled
    $barStr  = ('█' * $filled) + ('░' * $empty)
    $pctStr  = "$($Pct.ToString().PadLeft(3))%"
    return @{ Bar = $barStr; Pct = $pctStr; Level = $Level }
}

function Write-Bar([string]$Key, [int]$Pct, [int]$Width = 30, [string]$Level = '') {
    if (-not $Level) { $Level = Get-Threshold $Pct 75 90 }
    $b       = Get-Bar $Pct $Width $Level
    $keyPad  = $Key.PadRight(28)
    $plain   = "  $keyPad $($b.Bar) $($b.Pct)"
    $script:ReportLines.Add($plain)
    if ($Json) { return }
    if ($NoColor) { Write-Host $plain; return }
    Write-Host "  " -NoNewline
    Write-Host $keyPad -ForegroundColor Cyan -NoNewline
    Write-Host " " -NoNewline
    Write-Host $b.Bar -ForegroundColor (Get-LevelColor $Level) -NoNewline
    Write-Host " $($b.Pct)" -ForegroundColor DarkGray
}

# Threshold helper
function Get-Threshold([int]$Val, [int]$Warn, [int]$Crit) {
    if ($Val -ge $Crit) { return 'crit' }
    if ($Val -ge $Warn) { return 'warn' }
    return 'ok'
}

# Human-readable bytes
function Format-Bytes([long]$Bytes) {
    if ($Bytes -ge 1TB) { return '{0:N2} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# Section guard
function Test-SectionEnabled([string]$Name) {
    if (-not $Sections) { return $true }
    return ($Sections -split ',') -contains $Name
}

# Admin check
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [Security.Principal.WindowsPrincipal]$id
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# JSON accumulator
$script:JsonData = [ordered]@{}
function Add-JsonKey([string]$Key, $Value) { $script:JsonData[$Key] = $Value }

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
function Write-Banner {
    if ($Json) { return }
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

    $cs   = Get-CimInstance Win32_ComputerSystem    -ErrorAction SilentlyContinue
    $os   = Get-CimInstance Win32_OperatingSystem   -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS              -ErrorAction SilentlyContinue

    $hostname   = $env:COMPUTERNAME
    $osName     = $os.Caption
    $osVer      = $os.Version
    $osBuild    = $os.BuildNumber
    $arch       = $env:PROCESSOR_ARCHITECTURE
    $domain     = if ($cs.PartOfDomain) { $cs.Domain } else { 'WORKGROUP' }
    $totalRam   = if ($cs) { Format-Bytes ($cs.TotalPhysicalMemory) } else { 'N/A' }

    # Uptime
    $bootTime   = $os.LastBootUpTime
    $uptime     = (Get-Date) - $bootTime
    $uptimeStr  = '{0}d {1}h {2}m' -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes

    # Timezone
    $tz = (Get-TimeZone).DisplayName

    Write-KV 'Hostname'       $hostname
    Write-KV 'OS'             "$osName (Build $osBuild)"
    Write-KV 'Version'        $osVer
    Write-KV 'Architecture'   $arch
    Write-KV 'Domain/Workgrp' $domain
    Write-KV 'RAM (total)'    $totalRam
    Write-KV 'Last boot'      ($bootTime.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-KV 'Uptime'         $uptimeStr
    Write-KV 'Timezone'       $tz
    Write-KV 'Report time'    (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

    # Elevation warning
    if (-not (Test-IsAdmin)) {
        Write-Line ''
        Write-Line '  ⚠  Not running as Administrator — some data may be unavailable.' -Fg Yellow
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
        Write-KV 'Model'            $proc.Name.Trim()
        Write-KV 'Socket'           $proc.SocketDesignation
        Write-KV 'Cores (physical)' $proc.NumberOfCores
        Write-KV 'Threads (logical)'$proc.NumberOfLogicalProcessors
        Write-KV 'Base speed'       "$($proc.MaxClockSpeed) MHz"
        Write-KV 'L2 cache'         (Format-Bytes ($proc.L2CacheSize * 1KB))
        Write-KV 'L3 cache'         (Format-Bytes ($proc.L3CacheSize * 1KB))
        Write-KV 'Architecture'     $(switch ($proc.Architecture) {
            0 {'x86'} 1 {'MIPS'} 2 {'Alpha'} 3 {'PowerPC'}
            5 {'ARM'} 6 {'ia64'} 9 {'x64'} default {'Unknown'}
        })
        Write-KV 'Virtualization'   $(if ($proc.VirtualizationFirmwareEnabled) { 'Enabled' } else { 'Disabled/Unknown' })
    }

    # Live CPU usage via counter
    try {
        $cpuLoad = (Get-CimInstance Win32_Processor).LoadPercentage
        if ($null -eq $cpuLoad) {
            # Fallback: performance counter
            $cpuLoad = [int](Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1).CounterSamples[0].CookedValue
        }
        $cpuLoad = [int]$cpuLoad
        Write-Bar 'Usage (live)' $cpuLoad 30 (Get-Threshold $cpuLoad 70 90)
        Add-JsonKey 'cpu_load_pct' $cpuLoad
    } catch {
        Write-KV 'Usage (live)' 'unavailable (needs elevation)'
    }

    # Per-core usage
    try {
        $coreCounters = Get-Counter '\Processor(*)\% Processor Time' -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop
        Write-Line ''
        Write-Line "  $(([ConsoleColor]::DarkGray))Per-core load:" -Fg DarkGray
        foreach ($s in $coreCounters.CounterSamples | Where-Object { $_.InstanceName -ne '_total' } | Sort-Object InstanceName) {
            $cPct   = [int]$s.CookedValue
            $cLevel = Get-Threshold $cPct 70 90
            Write-Bar "  Core $($s.InstanceName)" $cPct 20 $cLevel
        }
    } catch { <# optional #> }

    # Hypervisor
    $hv = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
    if ($hv) {
        Write-Line ''
        Write-KV 'Hypervisor detected' 'yes (running inside VM or Hyper-V host)' 'warn'
    }

    Add-JsonKey 'cpu_model' ($procs | Select-Object -First 1 -ExpandProperty Name)
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Memory
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionMemory {
    if (-not (Test-SectionEnabled 'memory')) { return }
    Write-SectionHeader 'Memory' ([char]0x1F4BE)

    $os  = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs  = Get-CimInstance Win32_ComputerSystem  -ErrorAction SilentlyContinue

    $total    = $cs.TotalPhysicalMemory
    $free     = $os.FreePhysicalMemory * 1KB
    $used     = $total - $free
    $usedPct  = [int]($used / $total * 100)
    $level    = Get-Threshold $usedPct 75 90

    Write-KV 'Total'     (Format-Bytes $total)
    Write-KV 'Used'      (Format-Bytes $used)
    Write-KV 'Free'      (Format-Bytes $free) 'ok'
    Write-Bar 'Usage' $usedPct 30 $level

    # Virtual memory / page file
    $vm         = Get-CimInstance Win32_OperatingSystem
    $pfTotal    = $vm.TotalVirtualMemorySize * 1KB
    $pfFree     = $vm.FreeVirtualMemory      * 1KB
    $pfUsed     = $pfTotal - $pfFree
    $pfPct      = if ($pfTotal -gt 0) { [int]($pfUsed / $pfTotal * 100) } else { 0 }
    $pfLevel    = Get-Threshold $pfPct 60 80

    Write-Line ''
    Write-KV 'Page file total'  (Format-Bytes $pfTotal)
    Write-KV 'Page file free'   (Format-Bytes $pfFree)
    Write-Bar 'Page file usage' $pfPct 30 $pfLevel
    if ($pfPct -ge 60) {
        Write-Line '  ⚠  Elevated page file usage may indicate memory pressure.' -Fg Yellow
    }

    # Physical DIMM slots
    $dimms = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    if ($dimms) {
        Write-Line ''
        Write-Line '  Physical DIMMs:' -Fg DarkGray
        foreach ($d in $dimms) {
            $spd    = if ($d.Speed) { "$($d.Speed) MHz" } else { 'N/A' }
            $type   = switch ($d.MemoryType) {
                20 {'DDR'} 21 {'DDR2'} 22 {'DDR2 FB-DIMM'} 24 {'DDR3'} 26 {'DDR4'} 34 {'DDR5'} default {"Type $($d.MemoryType)"}
            }
            $formFactor = switch ($d.FormFactor) {
                8 {'DIMM'} 12 {'SO-DIMM'} default { "FF$($d.FormFactor)" }
            }
            Write-KV "  Slot $($d.DeviceLocator)" "$(Format-Bytes $d.Capacity)  $type  $formFactor  $spd"
        }
    }

    Add-JsonKey 'mem_total_bytes' $total
    Add-JsonKey 'mem_used_pct'    $usedPct
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Disk
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionDisk {
    if (-not (Test-SectionEnabled 'disk')) { return }
    Write-SectionHeader 'Disk Usage' ([char]0x1F4BF)

    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
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

        $jsonDrives += [ordered]@{ drive=$d.Name; used_pct=$usedPct; free_bytes=$d.Free; total_bytes=$total }
    }

    # Physical disk info
    $physDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($physDisks) {
        Write-Line '  Physical disks:' -Fg DarkGray
        foreach ($pd in $physDisks) {
            $mediaType = $pd.MediaType
            $bus       = $pd.BusType
            Write-KV "  $($pd.FriendlyName)" "$(Format-Bytes $pd.Size)  [$mediaType]  Bus: $bus"
        }
    }

    # Large folder scan (user profile top-5)
    Write-Line ''
    Write-Line '  Largest folders in user profile:' -Fg DarkGray
    try {
        $profilePath = $env:USERPROFILE
        Get-ChildItem -Path $profilePath -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $sz = (Get-ChildItem $_.FullName -Recurse -ErrorAction SilentlyContinue |
                       Measure-Object -Property Length -Sum).Sum
                [pscustomobject]@{ Path = $_.FullName; Bytes = $sz }
            } |
            Sort-Object Bytes -Descending |
            Select-Object -First 5 |
            ForEach-Object {
                Write-KV "  $([IO.Path]::GetFileName($_.Path))" (Format-Bytes $_.Bytes)
            }
    } catch { Write-Line '  (scan unavailable)' -Fg DarkGray }

    Add-JsonKey 'drives' $jsonDrives
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Temperatures
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionTemps {
    if (-not (Test-SectionEnabled 'temps')) { return }
    Write-SectionHeader 'Temperatures' ([char]0x1F321)

    $found = $false

    # --- OpenHardwareMonitor / LibreHardwareMonitor WMI namespace ---
    # Requires OHM/LHM to be running with WMI support enabled
    $ohmNs = 'root/OpenHardwareMonitor'
    $lhmNs = 'root/LibreHardwareMonitor'
    foreach ($ns in @($ohmNs, $lhmNs)) {
        try {
            $sensors = Get-CimInstance -Namespace $ns -ClassName Sensor `
                       -Filter "SensorType='Temperature'" -ErrorAction Stop
            if ($sensors) {
                $found = $true
                $src = if ($ns -like '*Libre*') { 'LibreHardwareMonitor' } else { 'OpenHardwareMonitor' }
                Write-Line "  (via $src)" -Fg DarkGray
                foreach ($s in $sensors | Sort-Object Parent, Name) {
                    $tempC  = [int]$s.Value
                    $level  = Get-Threshold $tempC 70 85
                    Write-KV "  $($s.Parent.Split('/')[-1]) / $($s.Name)" "${tempC}°C" $level
                }
                break
            }
        } catch { <# OHM/LHM not running #> }
    }

    # --- MSAcpi_ThermalZoneTemperature (basic, often only one zone) ---
    if (-not $found) {
        try {
            $tzs = Get-CimInstance -Namespace 'root/wmi' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
            if ($tzs) {
                $found = $true
                Write-Line '  (via ACPI thermal zones — limited resolution)' -Fg DarkGray
                foreach ($tz in $tzs) {
                    $tempC  = [int](($tz.CurrentTemperature / 10.0) - 273.15)
                    $level  = Get-Threshold $tempC 70 85
                    Write-KV "  $($tz.InstanceName)" "${tempC}°C" $level
                }
            }
        } catch { <# no ACPI thermal WMI #> }
    }

    if (-not $found) {
        Write-Line ''
        Write-Line '  No temperature sensors accessible via WMI.' -Fg DarkGray
        Write-Line '  For full CPU/GPU temps install OpenHardwareMonitor or LibreHardwareMonitor' -Fg DarkGray
        Write-Line '  and enable its WMI option: https://openhardwaremonitor.org' -Fg DarkGray
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: SMART Disk Health
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionSmart {
    if (-not (Test-SectionEnabled 'smart')) { return }
    Write-SectionHeader 'Disk Health (SMART)' ([char]0x1F50D)

    # StorageReliabilityCounter (Win8+, needs elevation)
    try {
        $disks = Get-PhysicalDisk -ErrorAction Stop
        foreach ($disk in $disks) {
            Write-Line ''
            Write-Line "  $($disk.FriendlyName)  [$($disk.MediaType)]" -Fg White

            # Health status from Windows Storage subsystem
            $hs     = $disk.HealthStatus
            $opSt   = $disk.OperationalStatus
            $hsLvl  = switch ($hs) { 'Healthy' {'ok'} 'Warning' {'warn'} 'Unhealthy' {'crit'} default {'warn'} }
            Write-KV '  Health status'      $hs       $hsLvl
            Write-KV '  Operational status' $opSt

            try {
                $rel = $disk | Get-StorageReliabilityCounter -ErrorAction Stop
                Write-KV '  Read errors'          $rel.ReadErrorsTotal
                Write-KV '  Write errors'         $rel.WriteErrorsTotal

                $tempC = $rel.Temperature
                if ($tempC -and $tempC -gt 0) {
                    $tLvl = Get-Threshold $tempC 50 65
                    Write-KV '  Temperature'  "${tempC}°C" $tLvl
                }

                $pwrHrs = $rel.PowerOnHours
                if ($pwrHrs) { Write-KV '  Power-on hours' $pwrHrs }

                $wear = $rel.Wear
                if ($wear -ne $null -and $wear -ge 0) {
                    $wearLvl = Get-Threshold $wear 80 95
                    Write-KV '  Wear (SSD %)' "$wear %" $wearLvl
                    Write-Bar '  Wear level' $wear 20 $wearLvl
                }

                if ($rel.ReadErrorsTotal -gt 0 -or $rel.WriteErrorsTotal -gt 0) {
                    Write-Line '  ⚠  Errors detected — consider backup and replacement.' -Fg Yellow
                }
            } catch {
                Write-KV '  SMART detail' 'unavailable (requires Administrator)'
            }

            # Seek smartctl if installed
            $smartctl = Get-Command smartctl -ErrorAction SilentlyContinue
            if ($smartctl) {
                try {
                    $num    = $disk.DeviceId
                    $sOut   = & smartctl -H -A "/dev/pd$num" 2>$null
                    $health = ($sOut | Select-String 'SMART overall-health').Line
                    if ($health) { Write-KV '  smartctl health' $health.Trim() }
                } catch { <# optional #> }
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

    # Interface table
    Write-Line ('  {0,-22} {1,-10} {2,-20} {3,-30} {4,-10} {5,-10}' -f 'Adapter','State','IPv4','IPv6','Sent','Recv') -Fg DarkGray

    $adapters   = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Not Present' }
    $jsonIfaces = @()

    foreach ($a in $adapters | Sort-Object Status, Name) {
        $ipv4 = (Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -notlike '169.*' } | Select-Object -First 1).IPAddress
        $ipv6 = (Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue |
                 Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress

        $stats = Get-NetAdapterStatistics -Name $a.Name -ErrorAction SilentlyContinue
        $sent  = if ($stats) { Format-Bytes $stats.SentBytes }     else { 'N/A' }
        $recv  = if ($stats) { Format-Bytes $stats.ReceivedBytes } else { 'N/A' }

        $stateLevel = switch ($a.Status) {
            'Up'           { 'ok' }
            'Disconnected' { 'warn' }
            default        { 'dim' }
        }

        $line = '  {0,-22} {1,-10} {2,-20} {3,-30} {4,-10} {5,-10}' -f `
            ($a.Name.Substring(0, [Math]::Min(21, $a.Name.Length))),
            $a.Status,
            ($ipv4 ?? '-'),
            ($ipv6 ?? '-'),
            $sent, $recv

        $script:ReportLines.Add($line)
        if (-not $Json) {
            if ($NoColor) { Write-Host $line }
            else {
                Write-Host ('  {0,-22} ' -f $a.Name.Substring(0, [Math]::Min(21, $a.Name.Length))) -NoNewline
                Write-Host ('{0,-10} ' -f $a.Status) -ForegroundColor (Get-LevelColor $stateLevel) -NoNewline
                Write-Host ('{0,-20} {1,-30} {2,-10} {3,-10}' -f ($ipv4 ?? '-'), ($ipv6 ?? '-'), $sent, $recv)
            }
        }

        $jsonIfaces += [ordered]@{
            name    = $a.Name
            status  = $a.Status
            ipv4    = $ipv4
            sent    = $stats.SentBytes
            recv    = $stats.ReceivedBytes
        }
    }

    # DNS
    Write-Line ''
    $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                  Where-Object { $_.ServerAddresses } |
                  Select-Object -ExpandProperty ServerAddresses -Unique |
                  Select-Object -First 4
    Write-KV 'DNS servers' ($dnsServers -join ', ')

    # Default gateway
    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
           Sort-Object RouteMetric | Select-Object -First 1).NextHop
    Write-KV 'Default gateway' ($gw ?? '(none)')

    # Connectivity probes
    Write-Line ''
    Write-Line '  Connectivity:' -Fg DarkGray
    foreach ($target in @('8.8.8.8', '1.1.1.1', 'www.google.com')) {
        $ok = Test-Connection $target -Count 1 -Quiet -ErrorAction SilentlyContinue
        $ll = if ($ok) { 'ok' } else { 'warn' }
        Write-KV "  ping $target" (if ($ok) { 'reachable' } else { 'unreachable' }) $ll
    }

    # Listening ports
    Write-Line ''
    Write-Line '  Listening ports:' -Fg DarkGray
    try {
        $listeners = Get-NetTCPConnection -State Listen -ErrorAction Stop |
                     Sort-Object LocalPort |
                     Select-Object -First 20
        Write-Line ('  {0,-30} {1}' -f 'Local endpoint', 'Process') -Fg DarkGray
        foreach ($l in $listeners) {
            $procName = try { (Get-Process -Id $l.OwningProcess -ErrorAction Stop).ProcessName } catch { "PID $($l.OwningProcess)" }
            Write-Line ('  {0,-30} {1}' -f "$($l.LocalAddress):$($l.LocalPort)", $procName)
        }
    } catch { Write-Line '  (requires elevation for process names)' -Fg DarkGray }

    # Active connections count
    $estCount = (Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Line ''
    Write-KV 'Established connections' $estCount

    Add-JsonKey 'interfaces' $jsonIfaces
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Services
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionServices {
    if (-not (Test-SectionEnabled 'services')) { return }
    Write-SectionHeader 'Services' ([char]0x26A1)

    # Stopped services that are set to Automatic (should be running)
    $stopped = Get-Service -ErrorAction SilentlyContinue |
               Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' }

    if ($stopped) {
        Write-KV 'Auto-start not running' "$($stopped.Count) service(s)" 'warn'
        Write-Line '  ─ Name ──────────────────────── DisplayName ──────────────────────' -Fg DarkGray
        foreach ($s in $stopped | Sort-Object Name | Select-Object -First 15) {
            Write-Line ('  {0,-35} {1}' -f $s.Name, $s.DisplayName) -Fg Yellow
        }
    } else {
        Write-KV 'Auto-start services' 'all running ✓' 'ok'
    }

    # Counts
    $allSvcs     = Get-Service -ErrorAction SilentlyContinue
    $runCount    = ($allSvcs | Where-Object { $_.Status -eq 'Running'  } | Measure-Object).Count
    $stoppedAll  = ($allSvcs | Where-Object { $_.Status -eq 'Stopped'  } | Measure-Object).Count
    Write-Line ''
    Write-KV 'Running services'   $runCount
    Write-KV 'Stopped services'   $stoppedAll

    # Critical Windows services health
    Write-Line ''
    Write-Line '  Critical service health:' -Fg DarkGray
    $criticalSvcs = @{
        'wuauserv'  = 'Windows Update'
        'WinDefend' = 'Windows Defender'
        'EventLog'  = 'Event Log'
        'Dnscache'  = 'DNS Client'
        'Winmgmt'   = 'WMI'
        'Schedule'  = 'Task Scheduler'
        'SamSs'     = 'Security Accounts Manager'
        'LanmanServer' = 'File Sharing (Server)'
    }
    foreach ($sn in $criticalSvcs.Keys | Sort-Object) {
        $svc = Get-Service -Name $sn -ErrorAction SilentlyContinue
        if ($svc) {
            $sl = if ($svc.Status -eq 'Running') { 'ok' } else { 'crit' }
            Write-KV "  $($criticalSvcs[$sn])" $svc.Status $sl
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
                $msg    = $e.Message -replace '\s+', ' '
                $msg    = $msg.Substring(0, [Math]::Min(90, $msg.Length))
                $line   = '  [{0}] {1}  {2}  {3}' -f $lvlStr, $e.TimeCreated.ToString('HH:mm:ss'), $e.Id, $msg
                Write-Line $line -Fg $(if ($e.Level -eq 1) { [ConsoleColor]::Red } else { [ConsoleColor]::DarkYellow })
            }
        } else {
            Write-Line '  None in the last 6 hours.' -Fg DarkGray
        }
    } catch {
        Write-Line '  (event log requires Administrator)' -Fg DarkGray
    }

    # Boot performance (boot duration from event 100)
    try {
        $bootEvt = Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' `
                   -MaxEvents 1 -ErrorAction Stop | Where-Object { $_.Id -eq 100 }
        if ($bootEvt) {
            $bootMs = ([xml]$bootEvt.ToXml()).Event.EventData.Data |
                      Where-Object { $_.Name -eq 'BootDuration' } |
                      Select-Object -ExpandProperty '#text'
            Write-Line ''
            Write-KV 'Last boot duration' "$([math]::Round($bootMs/1000, 1)) seconds"
        }
    } catch { <# optional #> }

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

    # Top 8 by CPU
    Write-Line '  By CPU time:' -Fg DarkGray
    Write-Line ('  {0,-8} {1,-30} {2,-12} {3,-12} {4}' -f 'PID','Name','CPU(s)','WS(MB)','Threads') -Fg DarkGray
    $allProcs | Sort-Object CPU -Descending | Select-Object -First 8 | ForEach-Object {
        Write-Line ('  {0,-8} {1,-30} {2,-12} {3,-12} {4}' -f `
            $_.Id,
            $_.ProcessName.Substring(0,[Math]::Min(29,$_.ProcessName.Length)),
            [math]::Round($_.CPU, 1),
            [math]::Round($_.WorkingSet64 / 1MB, 1),
            $_.Threads.Count)
    }

    # Top 8 by Memory
    Write-Line ''
    Write-Line '  By memory (working set):' -Fg DarkGray
    Write-Line ('  {0,-8} {1,-30} {2,-12} {3,-12} {4}' -f 'PID','Name','CPU(s)','WS(MB)','Handles') -Fg DarkGray
    $allProcs | Sort-Object WorkingSet64 -Descending | Select-Object -First 8 | ForEach-Object {
        Write-Line ('  {0,-8} {1,-30} {2,-12} {3,-12} {4}' -f `
            $_.Id,
            $_.ProcessName.Substring(0,[Math]::Min(29,$_.ProcessName.Length)),
            [math]::Round($_.CPU, 1),
            [math]::Round($_.WorkingSet64 / 1MB, 1),
            $_.HandleCount)
    }

    Write-Line ''
    Write-KV 'Total processes'  ($allProcs | Measure-Object).Count
    Write-KV 'Total threads'    ($allProcs | Measure-Object -Property Threads.Count -Sum).Sum

    # Hung / Not Responding
    $hung = $allProcs | Where-Object { $_.Responding -eq $false }
    if (($hung | Measure-Object).Count -gt 0) {
        Write-KV 'Not responding' ($hung | Measure-Object).Count 'warn'
        $hung | Select-Object -First 5 | ForEach-Object {
            Write-Line "  ⚠  $($_.ProcessName) (PID $($_.Id))" -Fg Yellow
        }
    } else {
        Write-KV 'Not responding' '0 ✓' 'ok'
    }

    Add-JsonKey 'process_count' ($allProcs | Measure-Object).Count
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Security Snapshot
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionSecurity {
    if (-not (Test-SectionEnabled 'security')) { return }
    Write-SectionHeader 'Security Snapshot' ([char]0x1F512)

    # Windows Defender status
    Write-Line '  Windows Defender:' -Fg DarkGray
    try {
        $mpStatus = Get-MpComputerStatus -ErrorAction Stop
        $avEnabled = $mpStatus.AntivirusEnabled
        $rtEnabled = $mpStatus.RealTimeProtectionEnabled
        $sigAge    = ((Get-Date) - $mpStatus.AntivirusSignatureLastUpdated).Days
        Write-KV '  Antivirus enabled'       ($avEnabled ? 'Yes' : 'No')  ($avEnabled ? 'ok' : 'crit')
        Write-KV '  Real-time protection'    ($rtEnabled ? 'Yes' : 'No')  ($rtEnabled ? 'ok' : 'crit')
        Write-KV '  Signature age (days)'    $sigAge                      (Get-Threshold $sigAge 3 7)
        if ($sigAge -ge 3) {
            Write-Line '  ⚠  Antivirus signatures are outdated. Run Windows Update.' -Fg Yellow
        }
    } catch {
        Write-Line '  (Windows Defender WMI unavailable — may need elevation)' -Fg DarkGray
    }

    # Windows Firewall profiles
    Write-Line ''
    Write-Line '  Windows Firewall:' -Fg DarkGray
    try {
        $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($fp in $fwProfiles) {
            $fl = if ($fp.Enabled) { 'ok' } else { 'crit' }
            Write-KV "  $($fp.Name)" ($fp.Enabled ? 'Enabled' : 'DISABLED') $fl
        }
    } catch {
        Write-Line '  (firewall query requires elevation)' -Fg DarkGray
    }

    # UAC status
    Write-Line ''
    try {
        $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
                -Name 'EnableLUA' -ErrorAction Stop).EnableLUA
        Write-KV 'UAC (EnableLUA)' ($uac -eq 1 ? 'Enabled ✓' : 'DISABLED ✗') ($uac -eq 1 ? 'ok' : 'crit')
    } catch { Write-KV 'UAC' 'unable to read registry' }

    # Secure Boot
    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction Stop
        Write-KV 'Secure Boot' ($sb ? 'Enabled ✓' : 'Disabled') ($sb ? 'ok' : 'warn')
    } catch { Write-KV 'Secure Boot' 'N/A or Legacy BIOS' 'dim' }

    # BitLocker
    Write-Line ''
    Write-Line '  BitLocker:' -Fg DarkGray
    try {
        $blv = Get-BitLockerVolume -ErrorAction Stop
        foreach ($v in $blv) {
            $bl  = if ($v.ProtectionStatus -eq 'On') { 'ok' } else { 'warn' }
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
            $color     = if ($isBuiltin) { 'warn' } else { 'info' }
            Write-KV "  $($a.Name)" $a.ObjectClass $color
        }
    } catch { Write-Line '  (local group query unavailable)' -Fg DarkGray }

    # Scheduled tasks with odd triggers (run as SYSTEM from non-system paths)
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
            }
        } else {
            Write-Line '  None found ✓' -Fg Green
        }
    } catch { Write-Line '  (task query requires elevation)' -Fg DarkGray }

    # Recent failed logons (Security event log 4625)
    Write-Line ''
    Write-Line '  Recent failed logons (last 24h):' -Fg DarkGray
    try {
        $cutoff  = (Get-Date).AddHours(-24)
        $failed  = Get-WinEvent -LogName Security -MaxEvents 500 -ErrorAction Stop |
                   Where-Object { $_.Id -eq 4625 -and $_.TimeCreated -ge $cutoff }
        $fCount  = ($failed | Measure-Object).Count
        if ($fCount -gt 0) {
            Write-KV '  Failed logon count' $fCount (Get-Threshold $fCount 5 20)
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

    Add-JsonKey 'uac_enabled' ($uac -eq 1)
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION: Pending Updates
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SectionUpdates {
    if (-not (Test-SectionEnabled 'updates')) { return }
    Write-SectionHeader 'Pending Updates' ([char]0x1F4E6)

    # Windows Update via COM (works without PSWindowsUpdate module)
    try {
        $updateSession   = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher  = $updateSession.CreateUpdateSearcher()
        Write-Line '  Searching for updates (this may take a moment)...' -Fg DarkGray
        $searchResult    = $updateSearcher.Search('IsInstalled=0 and Type=''Software''')
        $updateCount     = $searchResult.Updates.Count

        if ($updateCount -eq 0) {
            Write-KV 'Windows Update' 'Up to date ✓' 'ok'
        } else {
            Write-KV 'Pending updates' "$updateCount update(s) available" (Get-Threshold $updateCount 1 10)
            $critCount = 0
            foreach ($u in $searchResult.Updates) {
                $isSec  = $u.Categories | Where-Object { $_.Name -like '*Security*' }
                $isCrit = $u.MsrcSeverity -eq 'Critical'
                if ($isSec -or $isCrit) { $critCount++ }
                $tag  = if ($isCrit) { '[CRITICAL]' } elseif ($isSec) { '[Security]' } else { '[Update]  ' }
                $line = "  $tag $($u.Title.Substring(0,[Math]::Min(70,$u.Title.Length)))"
                Write-Line $line -Fg $(if ($isCrit) { [ConsoleColor]::Red } elseif ($isSec) { [ConsoleColor]::Yellow } else { [ConsoleColor]::Gray })
            }
            if ($critCount -gt 0) {
                Write-Line ''
                Write-Line "  ✗  $critCount critical/security update(s) pending — patch immediately." -Fg Red
            }
        }

        # Last update install time
        $history    = $updateSearcher.QueryHistory(0, 1)
        if ($history.Count -gt 0) {
            Write-KV 'Last update installed' $history.Item(0).Date.ToString('yyyy-MM-dd HH:mm')
        }

        Add-JsonKey 'updates_pending' $updateCount
    } catch {
        Write-Line '  Windows Update COM unavailable — try running as Administrator.' -Fg DarkGray
    }

    # Winget outdated (if available)
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Line ''
        Write-Line '  Winget outdated packages:' -Fg DarkGray
        try {
            $wgOut = & winget upgrade --include-unknown 2>&1 | Select-String '^\w'
            $wgCount = ($wgOut | Measure-Object).Count - 2   # subtract header lines
            if ($wgCount -gt 0) {
                Write-KV '  Winget updates' "$wgCount package(s)" 'warn'
            } else {
                Write-KV '  Winget' 'all packages up to date ✓' 'ok'
            }
        } catch { Write-Line '  (winget query failed)' -Fg DarkGray }
    }

    # Chocolatey outdated
    $choco = Get-Command choco -ErrorAction SilentlyContinue
    if ($choco) {
        Write-Line ''
        Write-Line '  Chocolatey outdated packages:' -Fg DarkGray
        try {
            $chocoOut   = & choco outdated --no-color 2>&1
            $chocoCount = ($chocoOut | Where-Object { $_ -match '\|' } | Measure-Object).Count
            if ($chocoCount -gt 0) {
                Write-KV '  Choco outdated' "$chocoCount package(s)" 'warn'
                $chocoOut | Where-Object { $_ -match '\|' } | Select-Object -First 8 | ForEach-Object {
                    Write-Line "  $_" -Fg Yellow
                }
            } else {
                Write-KV '  Chocolatey' 'up to date ✓' 'ok'
            }
        } catch { Write-Line '  (choco query failed)' -Fg DarkGray }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN RUNNER
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-AllSections {
    if (-not $Json) { Write-Banner }

    Invoke-SectionOverview
    Invoke-SectionCPU
    Invoke-SectionMemory
    Invoke-SectionDisk
    Invoke-SectionTemps
    Invoke-SectionSmart
    Invoke-SectionNetwork
    Invoke-SectionServices
    Invoke-SectionProcesses
    Invoke-SectionSecurity
    Invoke-SectionUpdates

    if ($Json) {
        $script:JsonData | ConvertTo-Json -Depth 5
        return
    }

    # Footer
    $line = '─' * 62
    Write-Line ''
    Write-Line $line                                                     -Fg DarkBlue
    Write-Line "  Report complete. Run with -Help to see all options."   -Fg DarkGray
    Write-Line $line                                                     -Fg DarkBlue
    Write-Line ''
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
        Invoke-AllSections
        Write-Host "`n  Refreshing in ${Watch}s ... (Ctrl-C to stop)" -ForegroundColor DarkGray
        Start-Sleep -Seconds $Watch
    }
} else {
    Invoke-AllSections
    if ($Output) { Save-Report $Output }
}
