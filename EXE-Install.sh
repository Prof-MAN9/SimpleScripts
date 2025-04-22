#!/usr/bin/env bash

# Updated install-wine.sh — now with auto-fix for missing winetricks

set -Eeuo pipefail
trap 'echo -e "${RED}[ERROR]${RESET} Script failed at line ${BASH_LINENO[0]} (exit code $?)." | tee -a "$LOGFILE"; exit 1' ERR

LOGFILE="$HOME/install-wine-$(date +'%Y%m%d-%H%M%S').log"
: > "$LOGFILE"

RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; RESET='\e[0m'
log_info ()  { echo -e "${BLUE}[INFO]${RESET}  $1" | tee -a "$LOGFILE"; }
log_warn ()  { echo -e "${YELLOW}[WARN]${RESET}  $1" | tee -a "$LOGFILE"; }
log_error () { echo -e "${RED}[ERROR]${RESET} $1" | tee -a "$LOGFILE"; }

# Ensure script is running in Debian (Crostini)
if ! grep -qEi 'debian|ubuntu' /etc/os-release; then
  log_error "This script must be run inside a Debian-based Linux container (Crostini)."
  exit 1
fi

log_info "Checking APT sources..."
SOURCE_ENTRY="deb http://deb.debian.org/debian bullseye main contrib non-free"
if ! grep -Fxq "$SOURCE_ENTRY" /etc/apt/sources.list; then
  log_warn "Missing standard Debian sources. Adding them now..."
  echo "$SOURCE_ENTRY" | sudo tee -a /etc/apt/sources.list > /dev/null
  log_info "New source added to /etc/apt/sources.list"
else
  log_info "APT source already present."
fi

log_info "Updating package lists..."
sudo apt update 2>&1 | tee -a "$LOGFILE"

log_info "Upgrading existing packages..."
sudo apt upgrade -y 2>&1 | tee -a "$LOGFILE"

log_info "Enabling i386 architecture..."
sudo dpkg --add-architecture i386 2>&1 | tee -a "$LOGFILE"
sudo apt update 2>&1 | tee -a "$LOGFILE"

log_info "Installing Wine and fonts..."
sudo apt install -y wine64 wine32 fonts-wine 2>&1 | tee -a "$LOGFILE"

log_info "Installing Winetricks..."
if ! sudo apt install -y winetricks 2>&1 | tee -a "$LOGFILE"; then
  log_error "Failed to install winetricks. You can try manually with: sudo apt install winetricks"
  exit 1
fi

log_info "Installing Wine Mono and Gecko..."
winetricks -q mono gecko 2>&1 | tee -a "$LOGFILE"

log_info "Verifying installation..."
command -v wine >/dev/null && log_info "Wine: $(wine --version)" || (log_error "Wine not installed." && exit 1)
command -v winetricks >/dev/null && log_info "Winetricks: $(winetricks --version)" || (log_error "Winetricks not installed." && exit 1)

echo -e "${GREEN}Installation complete!${RESET}"
cat <<EOF

To run a Windows .exe:
  1. Copy your .exe to ~/Downloads
  2. In Terminal: cd ~/Downloads
  3. Run with: wine your_app.exe

Need isolated Wine apps?
  WINEPREFIX=\$HOME/.wine-appname WINEARCH=win32 winecfg

Full logs at: $LOGFILE

EOF
