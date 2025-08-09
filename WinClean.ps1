<#
.SYNOPSIS
  WinClean.ps1 v2.0 – Comprehensive Windows Cleanup Tool (improved)

.PARAMETER WhatIf
  Dry-run (preview only).

.PARAMETER Verify
  Non-destructive verification (runs checks, shows what would be done).

.PARAMETER RunAll
  Run all available cleanup actions.

.PARAMETER Yes
  Auto-confirm prompts.

.PARAMETER Help
  Show help.

.PARAMETER Version
  Show version.

.PARAMETER Verbose
  Verbose output.

.NOTES
  Requires PowerShell 5.1+.
  For full functionality run "As Administrator".
#>

[CmdletBinding()]
param(
  [switch]$WhatIf,
  [switch]$Verify,
  [switch]$RunAll,
  [switch]$Yes,
  [switch]$Help,
  [switch]$Version,
  [switch]$Verbose
)

if ($Help) {
  @"
WinClean.ps1 v2.0
Usage: .\WinClean.ps1 [-WhatIf] [-Verify] [-RunAll] [-Yes] [-Help] [-Version] [-Verbose]

Options:
  -WhatIf    Dry-run (no changes).
  -Verify    Non-destructive checks (recommend first).
  -RunAll    Run all available cleanup actions (interactive unless -Yes).
  -Yes       Auto-confirm prompts when running destructive actions.
  -Help      Display help text.
  -Version   Show version.
  -Verbose   Enable verbose output.
Note: For full cleanup run as Administrator. Use -Verify first.
"@ | Write-Host
  exit 0
}
if ($Version) { Write-Host "WinClean.ps1 version 2.0.0"; exit 0 }
if ($Verbose) { $VerbosePreference = 'Continue' } else { $VerbosePreference = 'SilentlyContinue' }

# --------------------------
# Init & logging
# --------------------------
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'   # do not stop whole script; errors logged and continue
$LogDir = Join-Path $env:LOCALAPPDATA 'WinClean'
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile = Join-Path $LogDir ("WinClean_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
"Starting WinClean v2.0 at $(Get-Date)" | Tee-Object -FilePath $LogFile

# Transcript for more verbose logging
try { Start-Transcript -Path $LogFile -Append -ErrorAction SilentlyContinue } catch { Write-Verbose "Transcript unavailable: $_" }

function Write-Log { param($msg) $time = (Get-Date).ToString('s'); "$time | $msg" | Tee-Object -FilePath $LogFile -Append }

# --------------------------
# Helpers
# --------------------------
$IsWhatIf = [bool]$WhatIf
$IsVerify = [bool]$Verify
$AutoYes   = [bool]$Yes

function Test-IsAdmin {
  $current = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Confirm-Action {
  param(
    [string]$Message = "Proceed?",
    [switch]$Force
  )
  if ($IsWhatIf -or $IsVerify) {
    Write-Log "VERIFY/WHATIF MODE: would prompt: $Message"
    return $false
  }
  if ($AutoYes -or $Force) { return $true }
  $resp = Read-Host "$Message [y/N]"
  return ($resp -match '^(y|yes)$')
}

function Safe-Invoke {
  param(
    [ScriptBlock]$Script,
    [string]$Name = 'Action',
    [switch]$AllowWhatIf
  )
  try {
    Write-Log "START: $Name"
    if ($IsVerify) {
      Write-Log "VERIFY: would perform: $Name"
      return $true
    }
    if ($IsWhatIf -and -not $AllowWhatIf) {
      Write-Log "WHATIF: suppressed execution of $Name"
      return $true
    }
    & $Script
    Write-Log "DONE: $Name"
    return $true
  } catch {
    Write-Log "ERROR in $Name : $($_.Exception.Message)"
    return $false
  }
}

# --------------------------
# Elevation check
# --------------------------
if (-not (Test-IsAdmin)) {
  if (-not ($IsWhatIf -or $IsVerify)) {
    Write-Host "Warning: Not running elevated. Some operations require Administrator. Re-run PowerShell 'As Administrator' for full cleanup." -ForegroundColor Yellow
  } else {
    Write-Host "Running in Verify/WhatIf mode without elevation (allowed)." -ForegroundColor Cyan
  }
}

# --------------------------
# Utility: safe delete (moves to recycle if possible)
# --------------------------
function Move-ToRecycleBin {
  param([string]$Path)
  # Use Shell.Application COM to send to recycle
  try {
    $shell = New-Object -ComObject Shell.Application
    $file = $shell.NameSpace((Split-Path -Path $Path -Parent)).ParseName((Split-Path -Path $Path -Leaf))
    if ($null -ne $file) {
      $file.InvokeVerb("delete")
      Write-Log "Moved to Recycle: $Path"
      return $true
    } else {
      Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
      Write-Log "Deleted: $Path"
      return $true
    }
  } catch {
    Write-Log "Move-ToRecycleBin failed for $Path: $_. Falling back to Remove-Item"
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    return $false
  }
}

# --------------------------
# Core cleanup functions
# --------------------------

function Clear-WindowsUpdateCache {
  <#
  Remove contents of SoftwareDistribution\Download (safe).
  #>
  $target = 'C:\Windows\SoftwareDistribution\Download'
  Safe-Invoke -Name "Clear Windows Update Cache ($target)" -Script {
    if (Test-Path $target) {
      Get-ChildItem -Path $target -Force -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
          $p = $_.FullName
          if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: Would remove $p" } else { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } else { Write-Log "Path not found: $target" }
  }
}

function Clear-TempFolders {
  $paths = @("$env:TEMP", "$env:windir\Temp", "$env:SystemRoot\Temp")
  Safe-Invoke -Name "Clear Temp Folders" -Script {
    foreach ($p in $paths) {
      if (Test-Path $p) {
        Get-ChildItem -Path $p -Force -Recurse -ErrorAction SilentlyContinue |
          ForEach-Object {
            if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: Would remove $($_.FullName)" } else { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
          }
      } else { Write-Log "Not present: $p" }
    }
  }
}

function Clear-TmpFiles {
  $patterns = @('*.tmp','*.temp')
  $targets = @(
    "$env:TEMP",
    "$env:SystemRoot\Temp",
    "$env:windir\Temp",
    "$env:LOCALAPPDATA\Temp"
  )
  Safe-Invoke -Name "Clear .tmp files" -Script {
    foreach ($t in $targets) {
      if (-not (Test-Path $t)) { continue }
      Get-ChildItem -Path $t -Include $patterns -File -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
          if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: Would remove $($_.FullName)" } else { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
        }
    }
  }
}

function Clear-RecycleBin {
  Safe-Invoke -Name "Empty Recycle Bin (per user)" -Script {
    if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: Would empty recycle bin for current user" } else {
      # Use Shell COM to empty recycle bin
      $shell = New-Object -ComObject Shell.Application
      $shell.Namespace(0).Items() | Out-Null
      $null = $shell.NameSpace(0).Self.InvokeVerb("Empty Recycle Bin") 2>$null
      Write-Log "Recycle bin emptied (attempted via Shell COM)."
    }
  } -AllowWhatIf
}

function Clear-EventLogs {
  Safe-Invoke -Name "Clear Event Logs" -Script {
    Get-WinEvent -ListLog * | ForEach-Object {
      $name = $_.LogName
      try {
        if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: Would clear event log: $name" } else { wevtutil cl $name 2>$null }
      } catch { Write-Log "Failed to clear $name: $_" }
    }
  }
}

function Flush-DNSCache {
  Safe-Invoke -Name "Flush DNS Cache" -Script {
    if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: ipconfig /flushdns" } else { ipconfig /flushdns | Out-Null; Write-Log "Flushed DNS cache" }
  }
}

function Clear-Prefetch {
  $target = "$env:windir\Prefetch"
  Safe-Invoke -Name "Clear Prefetch" -Script {
    if (Test-Path $target) {
      Get-ChildItem -Path $target -File -ErrorAction SilentlyContinue |
        ForEach-Object {
          if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: Would remove $($_.FullName)" } else { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
        }
    } else { Write-Log "Prefetch folder missing: $target" }
  }
}

function Clear-StoreCache {
  Safe-Invoke -Name "Reset Microsoft Store Cache (wsreset)" -Script {
    if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: wsreset.exe" } else { Start-Process -FilePath 'wsreset.exe' -NoNewWindow -Wait; Write-Log "wsreset executed" }
  } -AllowWhatIf
}

function Clear-FontCache {
  Safe-Invoke -Name "Clear Font Cache" -Script {
    try {
      if (-not (Test-IsAdmin)) { Write-Log "Not elevated - skipping FontCache service restart." ; return }
      if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: Stop-Service FontCache; remove font cache files; Start-Service FontCache" }
      else {
        Stop-Service -Name FontCache -ErrorAction SilentlyContinue
        $fcPath = Join-Path $env:WinDir "ServiceProfiles\LocalService\AppData\Local\FontCache"
        if (Test-Path $fcPath) { Get-ChildItem -Path $fcPath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue }
        Start-Service -Name FontCache -ErrorAction SilentlyContinue
        Write-Log "Font cache cleared and service restarted"
      }
    } catch { Write-Log "Font cache clearing error: $_" }
  }
}

function Clear-ChocoCache {
  Safe-Invoke -Name "Chocolatey cache cleanup" -Script {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
      if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: choco clean all --yes" } else { choco clean all --yes | Out-Null; Write-Log "choco cache cleaned" }
    } else { Write-Log "Chocolatey not installed" }
  }
}

function Clear-WSLImages {
  Safe-Invoke -Name "Clean WSL images (unregister unused)" -Script {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) { Write-Log "wsl not found"; return }
    $dists = wsl --list --quiet 2>$null
    if (-not $dists) { Write-Log "No WSL distributions found" ; return }
    foreach ($d in $dists) {
      # If distro is running, skip; else prompt to unregister
      $isRunning = (wsl --status 2>$null) -match $d
      if ($IsWhatIf -or $IsVerify) {
        Write-Log "WHATIF: Would consider unregistering $d (running: $isRunning)"
      } else {
        if ($isRunning) { Write-Log "Skipping running distro $d" ; continue }
        if (Confirm-Action -Message "Unregister and remove WSL distro $d?") {
          wsl --unregister $d
          Write-Log "Unregistered $d"
        } else { Write-Log "Skipped unregistering $d" }
      }
    }
  }
}

function Clear-ErrorReports {
  $target = 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive'
  Safe-Invoke -Name "Clear Error Reports" -Script {
    if (Test-Path $target) {
      Get-ChildItem -Path $target -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: remove $($_.FullName)" } else { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } }
    } else { Write-Log "WER ReportArchive missing" }
  }
}

function Clear-DeliveryOptimization {
  $target = 'C:\Windows\SoftwareDistribution\DeliveryOptimization\Cache'
  Safe-Invoke -Name "Clear Delivery Optimization Cache" -Script {
    if (Test-Path $target) {
      Get-ChildItem -Path $target -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: remove $($_.FullName)" } else { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } }
    } else { Write-Log "DeliveryOptimization cache not found" }
  }
}

function Clear-MemoryDumps {
  $targets = @('C:\Windows\MEMORY.DMP','C:\Windows\Minidump\*')
  Safe-Invoke -Name "Clear Memory Dumps" -Script {
    foreach ($t in $targets) {
      if (Test-Path $t) {
        if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: remove $t" } else { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue }
      }
    }
  }
}

function Clear-RestorePoints {
  Safe-Invoke -Name "Delete Old VSS Shadows (vssadmin)" -Script {
    if (-not (Test-IsAdmin)) { Write-Log "VSS deletion requires elevation" ; return }
    if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: vssadmin list shadows / vssadmin delete shadows /For=C: /Oldest" } else {
      # Show shadows then delete the oldest
      vssadmin list shadows | Out-String | Write-Log
      if (Confirm-Action -Message "Delete oldest shadow copy for C:? (may free space)") {
        vssadmin delete shadows /For=C: /Oldest
        Write-Log "Deleted oldest shadow copy"
      } else { Write-Log "Skipped VSS deletion" }
    }
  }
}

function Remove-OldDrivers {
  Safe-Invoke -Name "Remove Old Drivers (pnputil)" -Script {
    if (-not (Get-Command pnputil -ErrorAction SilentlyContinue)) { Write-Log "pnputil not available"; return }
    if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: enumerate and delete obsolete drivers via pnputil" } else {
      pnputil /enum-drivers | Select-String 'Published Name' | ForEach-Object {
        $drv = ($_ -split ':')[1].Trim()
        # Optionally confirm per driver in interactive
        if (Confirm-Action -Message "Delete driver $drv?") {
          pnputil /delete-driver $drv /uninstall /force 2>$null
          Write-Log "Attempted to delete $drv"
        } else { Write-Log "Skipped driver $drv" }
      }
    }
  }
}

function Cleanup-OldUpdates {
  Safe-Invoke -Name "DISM StartComponentCleanup" -Script {
    if (-not (Get-Command dism.exe -ErrorAction SilentlyContinue)) { Write-Log "DISM not available"; return }
    if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: dism.exe /online /cleanup-image /startcomponentcleanup" } else {
      dism.exe /online /cleanup-image /startcomponentcleanup /quiet | Out-Null
      Write-Log "DISM startcomponentcleanup executed"
    }
  }
}

# --------------------------
# New advanced Windows features
# --------------------------

function Optimize-Trim {
  Safe-Invoke -Name "Run Optimize-Volume -ReTrim (TRIM)" -Script {
    if (-not (Get-Command Optimize-Volume -ErrorAction SilentlyContinue)) { Write-Log "Optimize-Volume cmdlet not available (requires admin/modern PS)"; return }
    if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: Optimize-Volume -DriveLetter C -ReTrim -Verbose" } else {
      Optimize-Volume -DriveLetter C -ReTrim -Verbose | Out-String | Write-Log
      Write-Log "Trim / ReTrim executed for C:"
    }
  }
}

function CompactOS-Offer {
  Safe-Invoke -Name "Compact OS (optional)" -Script {
    if ($IsWhatIf -or $IsVerify) { Write-Log "VERIFY: Would check CompactOS support and optionally apply" ; return }
    if (-not (Test-IsAdmin)) { Write-Log "CompactOS requires elevation" ; return }
    $cap = (Get-WmiObject -Class Win32_OperatingSystem).Caption
    Write-Host "CompactOS can save space on some systems but may slow IO. System: $cap"
    if (Confirm-Action -Message "Enable CompactOS:always? (recommended only on low disk systems)") {
      compact.exe /compactOS:always
      Write-Log "compact /CompactOS:always executed"
    } else { Write-Log "CompactOS skipped by user" }
  }
}

function Get-LargeFilesReport {
  param([int]$Top = 50, [string]$Path = 'C:\')
  Safe-Invoke -Name "Large files report" -Script {
    Write-Log "Generating top $Top largest files under $Path (this may take time)"
    $report = Join-Path $LogDir ("large_files_$(Get-Date -Format yyyyMMdd_HHmmss).csv")
    Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue |
      Sort-Object Length -Descending | Select-Object -First $Top |
      Select-Object FullName, @{N='SizeMB';E={[math]::Round($_.Length/1MB,2)}} |
      Export-Csv -Path $report -NoTypeInformation -Force
    Write-Log "Saved report: $report"
    if (-not $IsWhatIf -and -not $IsVerify) { Invoke-Item $report -ErrorAction SilentlyContinue }
  }
}

function Detect-AndDeleteLargeItems {
  Safe-Invoke -Name "Detect and optionally delete large files/folders" -Script {
    # Find top 10 largest directories at depth 1 (fast) and top 20 largest files
    Write-Log "Scanning top-level directories (May be faster if run on specific mount)"
    $dirs = Get-ChildItem -Path C:\ -Directory -ErrorAction SilentlyContinue |
      ForEach-Object {
        $size = (Get-ChildItem -Path $_.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        [pscustomobject]@{ Path = $_.FullName; SizeBytes = $size }
      } | Sort-Object SizeBytes -Descending | Select-Object -First 10

    Write-Log "Top directories:"
    $dirs | ForEach-Object { Write-Log ("{0:N1} GB - {1}" -f ($_.SizeBytes/1GB), $_.Path) }

    Write-Log "Now gathering top 20 large files..."
    $files = Get-ChildItem -Path C:\ -File -Recurse -ErrorAction SilentlyContinue |
      Sort-Object Length -Descending | Select-Object -First 20

    $i = 0
    foreach ($f in $files) {
      $i++
      Write-Host ("{0}) {1:N2} GB - {2}" -f $i, ($f.Length/1GB), $f.FullName)
    }

    if ($IsWhatIf -or $IsVerify) { Write-Log "VERIFY/WHATIF: listing only, not deleting" ; return }

    if (Confirm-Action -Message "Do you want to delete any of the listed large files? (will prompt per-file)") {
      foreach ($f in $files) {
        if (Confirm-Action -Message "Delete $($f.FullName) (${[math]::Round($f.Length/1MB,2)} MB)?") {
          try {
            # Prefer recycle
            Move-ToRecycleBin -Path $f.FullName
          } catch {
            Write-Log "Fallback remove: $($_)"
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
          }
        } else { Write-Log "Skipped $($f.FullName)" }
      }
    } else { Write-Log "User chose not to delete large files." }
  }
}

function Clean-DockerAdvanced {
  Safe-Invoke -Name "Docker advanced prune" -Script {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Log "Docker CLI not found"; return }
    if ($IsWhatIf -or $IsVerify) { Write-Log "WHATIF: docker system df; docker builder prune --all --filter until=24h; docker network prune; docker volume prune" ; return }
    docker system df | Out-String | Write-Log
    if (Confirm-Action -Message "Prune builder cache older than 24h?") { docker builder prune --all --filter until=24h -f | Out-String | Write-Log }
    if (Confirm-Action -Message "Prune unused networks?") { docker network prune -f | Out-String | Write-Log }
    if (Confirm-Action -Message "Prune volumes? (may remove data)") { docker volume prune -f | Out-String | Write-Log }
    Write-Log "Docker advanced prune completed"
  }
}

function Clean-DockerTagged {
  param([int]$RetainDays = 30)
  Safe-Invoke -Name "Docker selective cleanup (images older than $RetainDays days)" -Script {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Log "Docker CLI not found"; return }
    $threshold = (Get-Date).AddDays(-$RetainDays)
    $images = docker images --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.CreatedAt}}' 2>$null |
      ForEach-Object {
        $parts = $_ -split ' '
        $repoTag = $parts[0]; $id=$parts[1]; $created = ($parts[2..($parts.Length-1)] -join ' ')
        $createdDt = (Get-Date $created -ErrorAction SilentlyContinue)
        if ($createdDt -and $createdDt -lt $threshold) { [pscustomobject]@{RepoTag=$repoTag;Id=$id;Created=$createdDt} }
      }
    if (-not $images) { Write-Log "No old images found"; return }
    $images | ForEach-Object { Write-Log ("Old image: {0} {1} ({2})" -f $_.RepoTag,$_.Id,$_.Created) }
    if ($IsWhatIf -or $IsVerify) { return }
    if (Confirm-Action -Message "Remove the above ${($images).Count} images?") {
      foreach ($img in $images) { docker rmi -f $img.Id | Out-String | Write-Log }
    }
  }
}

# --------------------------
# Reporting & summary
# --------------------------
function Report-SpaceFreed {
  if ($IsWhatIf -or $IsVerify) { Write-Log "VERIFY: Skip final freed space calculation" ; return }
  try {
    $drive = Get-PSDrive -Name C
    $final = $drive.Free
    # Note: we didn't capture initial across runs; estimate by comparing to start of this run's free if needed.
    Write-Log "Free space on C: ${([math]::Round($final/1GB,2))} GB"
  } catch { Write-Log "Unable to read free space: $_" }
}

# --------------------------
# Available actions list
# --------------------------
$Actions = @(
  @{Key='1'; Name='Windows Update Cache'; Action={ Clear-WindowsUpdateCache }},
  @{Key='2'; Name='Temp Folders'; Action={ Clear-TempFolders }},
  @{Key='3'; Name='TMP Files (*.tmp)'; Action={ Clear-TmpFiles }},
  @{Key='4'; Name='Recycle Bin'; Action={ Clear-RecycleBin }},
  @{Key='5'; Name='Event Logs'; Action={ Clear-EventLogs }},
  @{Key='6'; Name='Flush DNS Cache'; Action={ Flush-DNSCache }},
  @{Key='7'; Name='Prefetch Files'; Action={ Clear-Prefetch }},
  @{Key='8'; Name='Store Cache (wsreset)'; Action={ Clear-StoreCache }},
  @{Key='9'; Name='Font Cache'; Action={ Clear-FontCache }},
  @{Key='10'; Name='Chocolatey Cache'; Action={ Clear-ChocoCache }},
  @{Key='11'; Name='WSL Images'; Action={ Clear-WSLImages }},
  @{Key='12'; Name='Error Reports'; Action={ Clear-ErrorReports }},
  @{Key='13'; Name='Delivery Optimization'; Action={ Clear-DeliveryOptimization }},
  @{Key='14'; Name='Memory Dumps'; Action={ Clear-MemoryDumps }},
  @{Key='15'; Name='Restore Points (VSS)'; Action={ Clear-RestorePoints }},
  @{Key='16'; Name='Remove Old Drivers'; Action={ Remove-OldDrivers }},
  @{Key='17'; Name='DISM: StartComponentCleanup'; Action={ Cleanup-OldUpdates }},
  @{Key='18'; Name='Detect & Delete Large FS'; Action={ Detect-AndDeleteLargeItems }},
  @{Key='19'; Name='Large Files Report'; Action={ Get-LargeFilesReport -Top 50 -Path 'C:\' }},
  @{Key='20'; Name='Full Cleanup & Report (interactive)'; Action={
      Clear-WindowsUpdateCache; Clear-TempFolders; Clear-TmpFiles; Clear-RecycleBin; Clear-EventLogs;
      Flush-DNSCache; Clear-Prefetch; Clear-StoreCache; Clear-FontCache; Clear-ChocoCache; Clear-WSLImages;
      Clear-ErrorReports; Clear-DeliveryOptimization; Clear-MemoryDumps; Clear-RestorePoints; Remove-OldDrivers;
      Cleanup-OldUpdates; Detect-AndDeleteLargeItems; Report-SpaceFreed
    }},
  @{Key='21'; Name='Optimize (Trim)'; Action={ Optimize-Trim }},
  @{Key='22'; Name='CompactOS (optional)'; Action={ CompactOS-Offer }},
  @{Key='23'; Name='Docker advanced prune'; Action={ Clean-DockerAdvanced }},
  @{Key='24'; Name='Docker selective prune (by age)'; Action={ Clean-DockerTagged -RetainDays 30 }},
  @{Key='Q'; Name='Quit'; Action={ Write-Log 'User quit'; exit 0 }}
)

# --------------------------
# RunAll or interactive
# --------------------------
if ($RunAll) {
  Write-Log "RUN ALL requested"
  foreach ($a in $Actions) {
    if ($a.Key -eq 'Q') { continue }
    Write-Log "Running action: $($a.Name)"
    & $a.Action
  }
  Report-SpaceFreed
  Stop-Transcript 2>$null
  exit 0
}

# If in Verify mode, run through verification of each action
if ($IsVerify) {
  Write-Log "VERIFY MODE: Listing available checks"
  foreach ($a in $Actions) {
    if ($a.Key -eq 'Q') { continue }
    Write-Log "VERIFY: $($a.Name)"
    # For verification we just call the action; most actions detect $IsVerify and will not perform destructive ops
    & $a.Action
  }
  Write-Log "VERIFY complete"
  Stop-Transcript 2>$null
  exit 0
}

# Interactive menu loop
while ($true) {
  Write-Host "===== WinClean v2.0 ====="
  foreach ($a in $Actions) {
    Write-Host ("{0,-3} {1}" -f $a.Key, $a.Name)
  }
  $choice = Read-Host "Select option (or Q to quit)"
  $selected = $Actions | Where-Object { $_.Key -eq $choice.ToUpper() }
  if (-not $selected) { Write-Host "Invalid choice or cancelled."; continue }
  try {
    & $selected.Action
    Report-SpaceFreed
  } catch {
    Write-Log "Unhandled error running selected action: $_"
  }
  Write-Host "Press Enter to continue..."
  Read-Host | Out-Null
}

Stop-Transcript 2>$null
