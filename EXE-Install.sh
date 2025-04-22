#!/usr/bin/env bash

# install-wine.sh — Automate Wine & tools on Chromebook Crostini
# -----------------------------------------------------------------------------
# Debug & crash prevention: exit on error, catch ERR in functions/subshells,
# and unset variables treated as errors. Logs errors with line numbers.
set -Eeuo pipefail
trap 'echo -e "${RED}[ERROR]${RESET} Script failed at line ${BASH_LINENO[0]} (exit code $?)." | tee -a "$LOGFILE"; exit 1' ERR

# Timestamped log file
LOGFILE="$HOME/install-wine-$(date +'%Y%m%d-%H%M%S').log"
: > "$LOGFILE"

# ANSI color codes
RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; RESET='\e[0m'

# Logging functions
log_info ()  { echo -e "${BLUE}[INFO]${RESET}  $1" | tee -a "$LOGFILE"; }
log_warn ()  { echo -e "${YELLOW}[WARN]${RESET}  $1" | tee -a "$LOGFILE"; }
log_error () { echo -e "${RED}[ERROR]${RESET} $1" | tee -a "$LOGFILE"; }

# Ensure script is run in Crostini
if ! grep -qEi 'debian|ubuntu' /etc/os-release; then
  log_error "This script must be run inside a Debian-based Linux container (Crostini)."
  exit 1
fi

log_info "Updating package lists..."
sudo apt update 2>&1 | tee -a "$LOGFILE"

log_info "Upgrading existing packages..."
sudo apt upgrade -y 2>&1 | tee -a "$LOGFILE"

log_info "Enabling i386 architecture for multiarch support..."
sudo dpkg --add-architecture i386 2>&1 | tee -a "$LOGFILE"
sudo apt update 2>&1 | tee -a "$LOGFILE"

log_info "Installing Wine (wine64, wine32) and fonts-wine..."
sudo apt install -y wine64 wine32 fonts-wine 2>&1 | tee -a "$LOGFILE"

log_info "Installing Winetricks..."
sudo apt install -y winetricks 2>&1 | tee -a "$LOGFILE"

log_info "Installing Wine Mono and Gecko via Winetricks..."
winetricks -q mono gecko 2>&1 | tee -a "$LOGFILE"

# Verification
log_info "Verifying Wine installation..."
if command -v wine >/dev/null 2>&1; then
  VERS=$(wine --version)
  log_info "Wine installed: $VERS"
else
  log_error "Wine command not found after installation."
  exit 1
fi

log_info "Verifying Winetricks installation..."
if command -v winetricks >/dev/null 2>&1; then
  WTV=$(winetricks --version)
  log_info "Winetricks installed: $WTV"
else
  log_error "Winetricks command not found after installation."
  exit 1
fi

# Success message
echo -e "${GREEN}Installation complete!${RESET}"
cat <<EOF

To run a Windows .exe:
  1. Copy your .exe into a shared folder (e.g. ~/Downloads).
  2. In Terminal, navigate to that folder:
       cd ~/Downloads
  3. Run:
       wine your_app.exe

Tip: To isolate apps, create a separate prefix:
  WINEPREFIX=\$HOME/.wine-yourapp WINEARCH=win32 winecfg

Logs saved to: $LOGFILE

EOF
