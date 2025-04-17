#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------------------------------------------------
# power_cleaner.sh
# A robust, modular Linux cleanup script that auto‑scaffolds its own modules.
# -------------------------------------------------------------------

VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$BASE_DIR/lib"
LOG_FILE="/var/log/power_cleaner_$(date +'%Y%m%d_%H%M%S').log"

# List of module filenames to expect in lib/
MODULES=(
  "apt_cache.sh"
  "thumbnail_cache.sh"
  "old_logs.sh"
  "temp_files.sh"
  "trash.sh"
  "browser_cache.sh"
  "large_files.sh"
  "docker_cleanup.sh"
  "journalctl_cleanup.sh"
  "tmpreaper_cleanup.sh"
  "tmpfiles_cleanup.sh"
  "logrotate_cleanup.sh"
  "snap_cleanup.sh"
)

# -----------------
# Logging Functions
# -----------------
log_info()  { echo "INFO  [$(date +'%F %T')] $*" | tee -a "$LOG_FILE"; }
log_error() { echo "ERROR [$(date +'%F %T')] $*" | tee -a "$LOG_FILE" >&2; }

# --------------------
# Execution Wrapper
# --------------------
DRY_RUN=false
execute() {
  if $DRY_RUN; then
    echo "[DRY RUN] $*"
  else
    eval "$@" || { log_error "Command failed: $*"; exit 1; }
  fi
}

# ------------------------
# Cleanup & Trap Handlers
# ------------------------
cleanup() {
  log_info "Performing final cleanup."
  # (Add any teardown here)
}
trap cleanup EXIT INT ERR

# ----------------------------
# Usage and CLI Option Parsing
# ----------------------------
CONFIG_FILE=""
FORCE_SCAFFOLD=false

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  -n, --dry-run       Dry‑run mode (no changes; commands are printed)
  -v, --verbose       Enable verbose/extra logging
  -c, --config FILE   Source additional configuration after parsing
      --init          Force (re)creation of the lib/ scaffold, then exit
      --yes           Automatic "yes" to any prompt (non‑interactive)
  -h, --help          Display this help and exit
  --version           Show version and exit
EOF
  exit 1
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--dry-run) DRY_RUN=true; shift ;;
    -v|--verbose) set -x; shift ;;
    -c|--config) CONFIG_FILE="$2"; shift 2 ;;
    --init) FORCE_SCAFFOLD=true; shift ;;
    --yes) NONINTERACTIVE=true; shift ;;
    --version) echo "$SCRIPT_NAME v$VERSION"; exit 0 ;;
    -h|--help) usage ;;
    *) break ;;
  esac
done

# -------------------------------
# Scaffold Creation if Necessary
# -------------------------------
scaffold_modules() {
  log_info "Scaffolding modules into: $LIB_DIR"
  mkdir -p "$LIB_DIR"

  # Template content for each module
  declare -A TEMPLATES

  TEMPLATES[apt_cache.sh]='#!/usr/bin/env bash
# Clean APT cache and remove unused packages

clean_apt_cache() {
  log_info "Cleaning APT cache and removing unused packages"
  execute "apt-get clean"
  execute "apt-get autoclean"
  execute "apt-get autoremove -y"
}'

  TEMPLATES[thumbnail_cache.sh]='#!/usr/bin/env bash
# Clear user thumbnail cache

clean_thumbnail_cache() {
  log_info "Cleaning thumbnail cache"
  execute "rm -rf \"$HOME/.cache/thumbnails\"/*"
}'

  TEMPLATES[old_logs.sh]='#!/usr/bin/env bash
# Remove system logs older than a configurable number of days

remove_old_logs() {
  log_info "Removing system logs older than ${LOG_MAX_AGE:-7} days"
  execute "find /var/log -type f -name '\''*.log'\'' -mtime +${LOG_MAX_AGE:-7} -exec rm -f {} +"
}'

  TEMPLATES[temp_files.sh]='#!/usr/bin/env bash
# Delete /tmp files older than configurable days

remove_temp_files() {
  log_info "Removing /tmp files older than ${TMP_MAX_AGE:-3} days"
  execute "find /tmp -type f -mtime +${TMP_MAX_AGE:-3} -exec rm -f {} +"
}'

  TEMPLATES[trash.sh]='#!/usr/bin/env bash
# Empty user Trash folders older than configurable days

clean_trash() {
  log_info "Emptying Trash files older than ${TRASH_MAX_AGE:-7} days"
  execute "find \"$HOME/.local/share/Trash/files\" -type f -mtime +${TRASH_MAX_AGE:-7} -exec rm -f {} +"
}'

  TEMPLATES[browser_cache.sh]='#!/usr/bin/env bash
# Clear browser caches for common browsers

clear_cache_browser() {
  log_info "Cleaning browser caches"
  for B in "google-chrome" "chromium" "mozilla/firefox"; do
    P="$HOME/.cache/$B"
    if [[ -d "$P" ]]; then
      execute "rm -rf \"$P\"/*"
    fi
  done
}'

  TEMPLATES[large_files.sh]='#!/usr/bin/env bash
# Remove large files in HOME over configurable size/age

remove_large_files() {
  log_info "Removing files > ${MAX_SIZE:-100M} older than ${MAX_AGE:-30} days in $HOME"
  execute "find \"$HOME\" -type f -size +${MAX_SIZE:-100M} -mtime +${MAX_AGE:-30} -exec rm -f {} +"
}'

  TEMPLATES[docker_cleanup.sh]='#!/usr/bin/env bash
# Prune Docker system of unused objects

docker_cleanup() {
  log_info "Pruning Docker system"
  execute "docker system prune -af --volumes"
}'

  TEMPLATES[journalctl_cleanup.sh]='#!/usr/bin/env bash
# Vacuum systemd journal logs based on size/time

journalctl_cleanup() {
  log_info "Vacuuming journal to ${JOURNAL_MAX_SIZE:-200M}"
  execute "journalctl --vacuum-size=${JOURNAL_MAX_SIZE:-200M}"
}'

  TEMPLATES[tmpreaper_cleanup.sh]='#!/usr/bin/env bash
# Use tmpreaper to clean /tmp with protect patterns

tmpreaper_cleanup() {
  log_info "Running tmpreaper on /tmp for ${TMPREAPER_AGE:-5d}"
  execute "tmpreaper --protect '\''*.X*'\'' ${TMPREAPER_AGE:-5d} /tmp"
}'

  TEMPLATES[tmpfiles_cleanup.sh]='#!/usr/bin/env bash
# Use systemd-tmpfiles to clean per /etc/tmpfiles.d/*.conf

tmpfiles_cleanup() {
  log_info "Running systemd-tmpfiles cleanup"
  execute "systemd-tmpfiles --clean"
}'

  TEMPLATES[logrotate_cleanup.sh]='#!/usr/bin/env bash
# Force a logrotate based on /etc/logrotate.conf

logrotate_cleanup() {
  log_info "Forcing logrotate"
  execute "logrotate --force /etc/logrotate.conf"
}'

  TEMPLATES[snap_cleanup.sh]='#!/usr/bin/env bash
# Remove disabled (old) snap revisions

snap_cleanup() {
  log_info "Removing old snap revisions"
  for rev in $(snap list --all | awk '\''/disabled/ {print $1, $3}'\''); do
    execute "snap remove $rev"
  done
}'

  # Write each template file
  for mod in "${MODULES[@]}"; do
    target="$LIB_DIR/$mod"
    echo "Creating $target"
    cat > "$target" <<EOF
${TEMPLATES[$mod]}
EOF
    chmod +x "$target"
  done

  log_info "Scaffolding complete."
}

# Check for missing modules
missing=false
for m in "${MODULES[@]}"; do
  [[ -f "$LIB_DIR/$m" ]] || missing=true
done

if $missing || $FORCE_SCAFFOLD; then
  if [[ "${NONINTERACTIVE:-false}" = true ]]; then
    scaffold_modules
    if $FORCE_SCAFFOLD; then
      log_info "--init requested; exiting after scaffold."
      exit 0
    fi
  else
    echo "Some modules are missing in $LIB_DIR."
    read -rp "Generate all modules now? [Y/n] " ans
    case "$ans" in [yY]|"") scaffold_modules ;; *) log_error "Modules missing; aborting."; exit 1 ;; esac
    if $FORCE_SCAFFOLD; then
      log_info "--init requested; exiting after scaffold."
      exit 0
    fi
  fi
fi

# -----------------------------
# Source Modules & Main Logic
# -----------------------------
for mod in "${MODULES[@]}"; do
  source "$LIB_DIR/$mod"
done

# Full-cleanup progress gauge
clean_with_progress() {
  {
    echo 10; sleep 1
    echo 30; sleep 1
    echo 50; sleep 1
    echo 70; sleep 1
    echo 90; sleep 1
    echo 100; sleep 1
  } | whiptail --gauge "Running full cleanup..." 8 60 0
}

# Interactive menu
main_menu() {
  whiptail --title "Power Cleaner" --menu "Select action:" 16 60 10 \
    1 "Clean APT Cache" \
    2 "Clean Thumbnails" \
    3 "Remove Old Logs" \
    4 "Delete Temp Files" \
    5 "Empty Trash" \
    6 "Clean Browser Caches" \
    7 "Remove Large Files" \
    8 "Docker System Prune" \
    9 "Journalctl Vacuum" \
    10 "Tmpreaper Cleanup" \
    11 "Systemd‑tmpfiles Cleanup" \
    12 "Force Logrotate" \
    13 "Snap Revision Cleanup" \
    14 "Full Cleanup w/ Progress" \
    15 "Toggle Dry‑Run (Now: ${DRY_RUN})" \
    0  "Exit" 3>&1 1>&2 2>&3
}

# Run the menu loop
while true; do
  choice=$(main_menu)
  case $choice in
    1) clean_apt_cache ;;
    2) clean_thumbnail_cache ;;
    3) remove_old_logs ;;
    4) remove_temp_files ;;
    5) clean_trash ;;
    6) clear_cache_browser ;;
    7) remove_large_files ;;
    8) docker_cleanup ;;
    9) journalctl_cleanup ;;
    10) tmpreaper_cleanup ;;
    11) tmpfiles_cleanup ;;
    12) logrotate_cleanup ;;
    13) snap_cleanup ;;
    14) clean_with_progress ;;
    15) DRY_RUN=!$DRY_RUN && log_info "Dry‑run now: $DRY_RUN" ;;
    0) log_info "Exiting. Stay tidy!" && exit 0 ;;
    *) log_error "Invalid choice: $choice" ;;
  esac
done
