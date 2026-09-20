<div align="center">

# System Maintenance Guide

</div>

---
<div align="center">

|**Version**|**Author**|**Made For**|
|:---:|:---:|:---|
|2026.09|Prof_MAN9|Windows 11|

</div>

---
## Table of Contents
- [Diagnostic](#diagnostic)
  - [Diagnostic-Test - Recommended](#diagnostic-test-recommended)
  - [Device Manager](#device-manager-win--x-m)
  - [Peripheral Diagnostic Utility - usbRecognized](#peripheral-diagnostic-utility-usbrecognized)
  - [Task Manager](#task-manager-ctrl--shift--esc)
  - [DISM and SFC - System Repair](#dism--sfc-system-repair)
  - [Windows Event Viewer](#windows-event-viewer-win--x-v)
  - [Windows Memory Diagnostic](#windows-memory-diagnostic)
- [Optimization](#optimization)
  - [Auto Optimization - Recommended](#auto-optimization-recommended)
  - [CTT Optimization - WinUtil](#ctt-optimization-winutil)
  - [MSConfig - System Configuration](#msconfig-system-configuration)
  - [System Properties](#system-properties)
    - [FOR LAPTOP](#for-laptop)
  - [Task Scheduler](#task-scheduler)
  - [Windows Services](#windows-services)
  - [Windows Settings](#windows-settings)

---
## Diagnostic
### Diagnostic-Test (Recommended)
- **Open PowerShell:** via `Win + X`, then `A`
- **Enter Command:**
```powershell
irm pm9.s.gy/winclean.ps1 | iex
```
**NOTE: If not working, enter this command:**
```powershell
winget install --id Microsoft.PowerShell --source winget
```
**Then, search for *PowerShell 7*, open and try again**

<br>

### Device Manager *(`Win + X, M`)*
- **Inspect Status:** Look for warning signs next to components
  - **Find Errors:** Right-click device, select *Properties*, read *Device Status* and find error codes 
  - **Update Drivers:** Right-click device, select *Properties*, navigate to *Driver* tab, and click *Update Driver*
    - Note: If experiencing instability, select *Uninstall Driver* to trigger a clean driver reinstallation

<br>

### Peripheral Diagnostic Utility *([usbRecognized](https://www.usbrecognized.com))*
- **Quick Check:** Go to the URL above, click *Quick Check*, and verify all components are working **_ONE-BY-ONE_**
  - **Issues Found:** Replace broken components (or issue a *Repair Ticket*)

<br>

### Task Manager *(`Ctrl + Shift + Esc`)*
- **Component Usage:** Navigate to the *Performance* tab and look for any spikes or high component usage
- **Heavy Processes:** Navigate to the *Processes* tab and look for any tasks with high component usage
- **Startup Apps:** Navigate to the *Startup Apps* tab, find any unused apps and disable (via right-click, then *Disable*)

<br>

### DISM & SFC *(System Repair)*
- **Open Command Prompt:** via `Win + R`, type `cmd`, press `Enter`
  - **Repair Windows with:**

  ```CMD
  DISM /Online /Cleanup-Image /RestoreHealth
  ```
  **AND**
  ```CMD
  sfc /scannow
  ```
  - **Verify Logs:** Confirm completion at `C:\Windows\Logs\CBS\CBS.log`

<br>

### Windows Event Viewer *(`Win + X, V`)*
- **Check Critical Logs:** Find any critical errors
  - **Errors Found:** Search up the error code for details and investigate furthur

<br>

### Windows Memory Diagnostic
- **Start Test:** Press `Win + R`, type `mdsched.exe`, press `Enter` and select *Restart Now*
  - **Verify Logs:** Press `Win + X`, then `V`; open Windows Logs > System, then filter by `MemoryDiagnostic-Results`

<br>

---
## Optimization
### Auto Optimization (Recommended)
- **Open PowerShell:** via `Win + X`, then `A`
- **Enter Command:**
```powershell
irm pm9.s.gy/syscheck.ps1 | iex
```
**NOTE: If not working, enter this command:**
```powershell
winget install --id Microsoft.PowerShell --source winget
```
**Then, search for *PowerShell 7*, open and try again**

<br>

### CTT Optimization *(WinUtil)*
- **Open Powershell:** via `Win + X`, then `A`
- **Enter Command:**
```powershell
irm https://christitus.com/win | iex
```
- **Enable Tweaks:** Open *Tweaks* tab, select "Standard" and press *Run*

<br>

### MSConfig *(System Configuration)*
- **Open MSConfig:** via `Win + R`, type `msconfig` and press `Enter`
- **Disable Services:** Navigate to the *Services* tab, press *Hide all Microsoft Services* and press *Disable All*

<br>

### System Properties
- **Open System Properties:** via `Win + R`, type `sysdm.cpl` and press `Enter`
- **Optimize Visuals:** Navigate to the *Advanced* tab, press *Settings* under *Performance*, select *Custom* and **select the following boxes**:
  - *Animations in the Taskbar*
  - *Enable Peak*
  - *Show thumbnails instead of icons*
  - *Smooth edges of screen fonts*
#### FOR LAPTOP:
- **Processor Scheduling:** Within the *Performance Options*, navigate to the advanced tab and select *Programs* under *Processor Scheduling*
- **Setup Virtual Memory:** Under *Virtual Memory*, select *Change...*, uncheck top box, select *Custom Size* and enter recommended value

<br>

### Task Scheduler
- **Open Scheduler:** via `Win + R`, type `taskschd.msc`
- **Disable Unessecary Processes:** Right-click non-essential processes and hit *Disable*. (e.g. Adobe, OneDrive, Epic Games, etc.)

<br>

### Windows Services
- **Open Services:** via `Win + R`, type `services.msc` and press `Enter`
- **Disable Processes:** Right-click the following processes, press *Disable*, then *Apply* and *OK*
  - Xbox Live Networking Service
  - Xbox Live Game Save
  - Xbox Live Auth Manager
  - Xbox Accessory Management
  - Connected User Experiences and Telemetry
  - Downloaded Maps Manager
  - Phone Service
  - Wallet Service

  <br>

  ### Windows Settings
- **Open Settings:** via `Win + X`, then `I`
  - **Disable Widgets:** Navigate to *Personalization > Taskbar* and turn off *Widgets*
  - **Disable Link-Apps:** Navigate to *Apps > Apps for Websites* and turn everything off
  - **Disable Game-Bar:** Navigate to *Gaming > Xbox Game Bar* and turn off
  - **Clean Storage:** Navigate to *System > Storage* and turn on *Storage Sense*
