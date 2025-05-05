<#
.SYNOPSIS
  WinClean.ps1 v1.6 – Comprehensive Windows Cleanup Tool

.PARAMETER WhatIf
  Perform a dry-run (preview only).

.PARAMETER Help
  Display help and exit.

.PARAMETER Version
  Show script version and exit.

.PARAMETER Verbose
  Enable verbose debug output.

.NOTES
  Requires PowerShell 5.1+.
  Must run “As Administrator” for full functionality.
#>

# ----- Parameters & Switches -----
param(
  [switch]$WhatIf,
  [switch]$Help,
  [switch]$Version,
  [switch]$Verbose
)

if ($Help) {
  Write-Host @"
WinClean.ps1 v1.6
Usage: .\WinClean.ps1 [-WhatIf] [-Help] [-Version] [-Verbose]

Options:
  -WhatIf    Dry-run (no changes).
  -Help      Display this help text.
  -Version   Show version.
  -Verbose   Enable debug output.
Note: Run “As Administrator” for full cleanup.
"@
  exit
}
if ($Version) {
  Write-Host "WinClean.ps1 version 1.6.0"
  exit
}
if ($Verbose) { $VerbosePreference = 'Continue' }

# ----- Strict Mode & Logging -----
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $PSScriptRoot ("WinClean_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogFile -Append

function Safe-Invoke {
  param([ScriptBlock]$Body)
  try { & $Body }
  catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Stop-Transcript; exit 1
  }
}

# ----- Initial Disk State -----
$InitialFree = (Get-PSDrive C).Free

# ----- Modular Cleanup Functions -----
function Clear-WindowsUpdateCache {
  Safe-Invoke { Remove-Item 'C:\Windows\SoftwareDistribution\Download\*' -Recurse -Force -WhatIf:$WhatIf }
}
function Clear-TempFolders {
  foreach ($p in @("$env:TEMP\*", "C:\Windows\Temp\*")) {
    Safe-Invoke { Remove-Item $p -Recurse -Force -WhatIf:$WhatIf }
  }
}
function Clear-TmpFiles {
  Write-Host "[INFO] Removing .tmp files…" 
  $paths = @(
    'C:\Windows\Temp\*.tmp',
    "$env:SystemRoot\Temp\*.tmp",
    "$env:TEMP\*.tmp",
    'C:\Users\*\AppData\Local\Temp\*.tmp'
  )
  foreach ($path in $paths) {
    Safe-Invoke {
      Get-ChildItem -Path $path -File -Recurse -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue -WhatIf:$WhatIf
    }
  }
}
function Clear-RecycleBin {
  Safe-Invoke { Clear-RecycleBin -Force -WhatIf:$WhatIf }
}
function Clear-EventLogs {
  Get-EventLog -List | ForEach-Object {
    Safe-Invoke { Clear-EventLog -LogName $_.Log }
  }
}
function Flush-DNSCache {
  Safe-Invoke { ipconfig /flushdns }
}
function Clear-Prefetch {
  Safe-Invoke { Remove-Item 'C:\Windows\Prefetch\*' -Recurse -Force -WhatIf:$WhatIf }
}
function Clear-StoreCache {
  Safe-Invoke { wsreset.exe -WhatIf:$WhatIf }
}
function Clear-FontCache {
  Safe-Invoke {
    Stop-Service FontCache -Force
    Remove-Item "$env:WinDir\ServiceProfiles\LocalService\AppData\Local\FontCache\*" -Recurse -Force -WhatIf:$WhatIf
    Start-Service FontCache
  }
}
function Clear-ChocoCache {
  if (Get-Command choco -ErrorAction SilentlyContinue) {
    Safe-Invoke { choco clean all --yes -WhatIf:$WhatIf }
  }
}
function Clear-WSLImages {
  if (Get-Command wsl -ErrorAction SilentlyContinue) {
    wsl --list --quiet | ForEach-Object {
      if ($_ -ne (wsl uname -r)) {
        Safe-Invoke { wsl --unregister $_ }
      }
    }
  }
}
function Clear-ErrorReports {
  Safe-Invoke { Remove-Item 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive\*' -Recurse -Force -WhatIf:$WhatIf }
}
function Clear-DeliveryOptimization {
  Safe-Invoke { Remove-Item 'C:\Windows\SoftwareDistribution\DeliveryOptimization\Cache\*' -Recurse -Force -WhatIf:$WhatIf }
}
function Clear-MemoryDumps {
  Safe-Invoke { Remove-Item 'C:\Windows\MEMORY.DMP','C:\Windows\Minidump\*' -Recurse -Force -WhatIf:$WhatIf }
}
function Clear-RestorePoints {
  Safe-Invoke { vssadmin Delete Shadows /For=C: /Oldest -WhatIf:$WhatIf }
}
function Remove-OldDrivers {
  Safe-Invoke {
    pnputil.exe /enum-drivers |
      Select-String 'Published Name' |
      ForEach-Object {
        $drv = $_.Line.Split(':')[1].Trim()
        pnputil.exe /delete-driver $drv /uninstall /force
      }
  }
}
function Cleanup-OldUpdates {
  Safe-Invoke { dism.exe /online /cleanup-image /startcomponentcleanup /quiet /norestart -WhatIf:$WhatIf }
}

# ----- Detect & Delete Large Items -----
function Detect-AndDeleteLargeItems {
  $items = @()
  Get-ChildItem C:\ -Directory | ForEach-Object {
    $size = (Get-ChildItem $_.FullName -Recurse -ErrorAction SilentlyContinue |
             Measure-Object -Sum Length).Sum
    $items += [PSCustomObject]@{ Path=$_.FullName; Size=$size }
  }
  Get-ChildItem C:\ -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object Length -gt 100MB |
    Sort-Object Length -Descending | Select-Object -First 5 |
    ForEach-Object { $items += [PSCustomObject]@{ Path=$_.FullName; Size=$_.Length } }

  $choices = $items | ForEach-Object {
    [System.Management.Automation.Host.ChoiceDescription]::new(
      "{0:N1} GB - {1}" -f ($_.Size/1GB), $_.Path
    )
  }
  $idx = $Host.UI.PromptForChoice(
    "Delete Large Items","Select items to delete",$choices,0
  )
  if ($idx -ge 0) {
    $path = $choices[$idx].HelpMessage
    Safe-Invoke { Remove-Item $path -Recurse -Force -WhatIf:$WhatIf }
  }
}

# ----- Space Freed Reporting -----
function Report-SpaceFreed {
  if (-not $WhatIf) {
    $final = (Get-PSDrive C).Free
    $freedMB = [math]::Round((($InitialFree - $final)/1MB),2)
    Write-Host "[INFO] Total space freed: $freedMB MB"
  }
}

# ----- Interactive Menu & Controls -----
function Show-Menu {
  Clear-Host
  Write-Host "WinClean v1.6 Controls:`n 0=Exit 1-?=Actions  -WhatIf=DryRun  -Verbose=Debug`n"
  $menu = @(
    @{K='1';  L='Windows Update Cache';      A={Clear-WindowsUpdateCache}},
    @{K='2';  L='Temp Folders';               A={Clear-TempFolders}},
    @{K='3';  L='TMP Files (*.tmp)';          A={Clear-TmpFiles}},
    @{K='4';  L='Recycle Bin';                A={Clear-RecycleBin}},
    @{K='5';  L='Event Logs';                 A={Clear-EventLogs}},
    @{K='6';  L='Flush DNS Cache';            A={Flush-DNSCache}},
    @{K='7';  L='Prefetch Files';             A={Clear-Prefetch}},
    @{K='8';  L='Store Cache';                A={Clear-StoreCache}},
    @{K='9';  L='Font Cache';                 A={Clear-FontCache}},
    @{K='10'; L='Chocolatey Cache';           A={Clear-ChocoCache}},
    @{K='11'; L='WSL Images';                 A={Clear-WSLImages}},
    @{K='12'; L='Error Reports';              A={Clear-ErrorReports}},
    @{K='13'; L='DeliveryOptimization';       A={Clear-DeliveryOptimization}},
    @{K='14'; L='Memory Dumps';               A={Clear-MemoryDumps}},
    @{K='15'; L='Restore Points';             A={Clear-RestorePoints}},
    @{K='16'; L='Remove Old Drivers';         A={Remove-OldDrivers}},
    @{K='17'; L='Old Updates Cleanup';        A={Cleanup-OldUpdates}},
    @{K='18'; L='Detect & Delete Large FS';   A={Detect-AndDeleteLargeItems}},
    @{K='19'; L='Show Freed-Space Report';    A={Report-SpaceFreed}},
    @{K='20'; L='Full Cleanup & Report';      A={
        Clear-WindowsUpdateCache; Clear-TempFolders; Clear-TmpFiles;
        Clear-RecycleBin; Clear-EventLogs; Flush-DNSCache; Clear-Prefetch;
        Clear-StoreCache; Clear-FontCache; Clear-ChocoCache; Clear-WSLImages;
        Clear-ErrorReports; Clear-DeliveryOptimization; Clear-MemoryDumps;
        Clear-RestorePoints; Remove-OldDrivers; Cleanup-OldUpdates;
        Detect-AndDeleteLargeItems; Report-SpaceFreed
    }}
  )
  $menu | ForEach-Object { Write-Host "$($_.K): $($_.L)" }
  $choice = Read-Host 'Select option'
  return $menu | Where-Object { $_.K -eq $choice }
}

# ----- Main Loop -----
do {
  $item = Show-Menu
  if (-not $item) { break }
  Safe-Invoke { & $item.A }
  if ($item.K -ne '20') { Report-SpaceFreed }
  Pause
} while ($true)

Stop-Transcript
