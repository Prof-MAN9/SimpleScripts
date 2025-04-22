#!/usr/bin/env bash
# install-wine-advanced.sh — Robust Wine installer for Crostini with arch detection,
# package checks, prefix init, WineHQ repo addition, and detailed logging.

set -Eeuo pipefail
trap 'echo -e "${RED}[ERROR]${RESET} at line ${BASH_LINENO[0]} (exit $?)." | tee -a "$LOG"; exit 1' ERR

# Log setup
LOG="$HOME/install-wine-$(date +'%Y%m%d-%H%M%S').log"
: > "$LOG"

# Colors
RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; RESET='\e[0m'
log()   { echo -e "${BLUE}[INFO]${RESET} $1" | tee -a "$LOG"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET} $1" | tee -a "$LOG"; }
err()   { echo -e "${RED}[ERROR]${RESET} $1" | tee -a "$LOG"; }

# Check container
if ! grep -qiE 'debian|ubuntu' /etc/os-release; then
  err "Not in a Debian-based Crostini container."
  exit 1
fi

# Ensure standard repos for winetricks
SOURCE="deb http://deb.debian.org/debian bullseye main contrib non-free"
if ! grep -Fxq "$SOURCE" /etc/apt/sources.list; then
  warn "Adding missing Debian main/contrib/non-free repo..."
  echo "$SOURCE" | sudo tee -a /etc/apt/sources.list
fi

# Arch detection
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64)     WINE_CMD="wine";           ;;
  i*86)             WINE_CMD="wine";           ;;
  aarch64|arm64)    WINE_CMD="box64 wine";     ;;
  armv7l|armhf)     WINE_CMD="box86 wine";     ;;
  *) err "Unsupported arch: $ARCH"; exit 1;    ;;
esac
log "Host architecture: $ARCH → using '$WINE_CMD'"

# Helper: is_installed <pkg>
is_installed(){
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok"
}

# Update & multiarch
log "Updating packages..."
sudo apt update | tee -a "$LOG"
log "Upgrading..."
sudo apt upgrade -y | tee -a "$LOG"

if ! dpkg --print-foreign-architectures | grep -q i386; then
  log "Enabling i386 multiarch..."
  sudo dpkg --add-architecture i386
  sudo apt update | tee -a "$LOG"
fi

# WineHQ repo & key (if version <5)
check_wine_ver(){
  local v
  v=$(wine --version 2>/dev/null || echo "wine-0.0")
  v=${v#wine-}; echo "${v%%.*}"
}
if command -v wine &>/dev/null && (( $(check_wine_ver) < 5 )); then
  log "Upgrading to WineHQ stable..."
  sudo mkdir -pm755 /etc/apt/keyrings
  sudo wget -qO /etc/apt/keyrings/winehq-archive.key \
    https://dl.winehq.org/wine-builds/winehq.key
  echo "deb [signed-by=/etc/apt/keyrings/winehq-archive.key] \
    https://dl.winehq.org/wine-builds/debian/ bullseye main" \
    | sudo tee /etc/apt/sources.list.d/winehq.list
  sudo apt update | tee -a "$LOG"
  sudo apt install -y --install-recommends winehq-stable | tee -a "$LOG"
fi

# Install core packages
for pkg in wine64 wine32 fonts-wine winetricks; do
  if is_installed "$pkg"; then
    log "Skipping already installed: $pkg"
  else
    log "Installing $pkg..."
    sudo apt install -y "$pkg" | tee -a "$LOG"
  fi
done

# On ARM, ensure translators
if [[ "$ARCH" =~ aarch64|armv7l ]]; then
  for box_pkg in box64 box86; do
    if command -v "${box_pkg}" &>/dev/null; then
      log "Found translator: $box_pkg"
    else
      log "Installing translator: $box_pkg"
      sudo apt install -y "$box_pkg" | tee -a "$LOG"
    fi
  done
fi

# Initialize or update prefix
if [ ! -d "$HOME/.wine" ]; then
  log "Initializing Wine prefix..."
  $WINE_CMD wineboot --init | tee -a "$LOG"
else
  log "Updating existing Wine prefix..."
  $WINE_CMD wineboot -u | tee -a "$LOG"
fi

# Install Mono & Gecko
log "Installing Wine Mono and Gecko..."
winetricks -q mono gecko | tee -a "$LOG"

# Final verification
for cmd in wine winetricks; do
  if ! command -v "${cmd%% *}" &>/dev/null; then
    err "$cmd not found — installation failed."
    exit 1
  fi
done

# Ensure drive_c exists
if [ ! -d "$HOME/.wine/drive_c" ]; then
  err "Drive C: not found in prefix — prefix initialization failed."
  exit 1
fi

echo -e "${GREEN}✔ Wine setup succeeded!${RESET}"
cat <<EOF

Usage:
  cd ~/Downloads
  $WINE_CMD your_app.exe

To isolate apps:
  WINEPREFIX=\$HOME/.wine-app WINEARCH=win32 winecfg

Log file: $LOG

EOF
