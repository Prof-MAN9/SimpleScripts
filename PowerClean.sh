#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------------------------------------------------
# power_cleaner.sh v1.4
# Modular cleanup + interactive package removal + FS inspector
# -------------------------------------------------------------------

# ----- Metadata & Paths -----
VERSION="1.4.0"
SCRIPT_NAME="$(basename "$0")"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$BASE_DIR/lib"
LOG_FILE="${LOGFILE:-/var/log/power_cleaner_$(date +'%Y%m%d_%H%M%S').log}"

# ----- Initial Disk State -----
INITIAL_AVAIL=$(df --output=avail / | tail -1)

# ----- Modules List -----
MODULES=(
  apt_cache.sh thumbnail_cache.sh old_logs.sh temp_files.sh
  trash.sh browser_cache.sh large_files.sh docker_cleanup.sh
  journalctl_cleanup.sh tmpreaper_cleanup.sh tmpfiles_cleanup.sh
  logrotate_cleanup.sh snap_cleanup.sh
)

# ----- Logging -----
log_info()  { echo "INFO  [$(date +'%F %T')] $*" | tee -a "$LOG_FILE"; }
log_error() { echo "ERROR [$(date +'%F %T')] $*" | tee -a "$LOG_FILE" >&2; }

# ----- Dry‑Run Wrapper -----
DRY_RUN=false
execute() {
  if $DRY_RUN; then
    echo "[DRY RUN] $*"
  else
    eval "$@" || { log_error "Command failed: $*"; exit 1; }
  fi
}

# ----- Final Cleanup & Report -----
cleanup() {
  if ! $DRY_RUN; then
    local FINAL_AVAIL FREED_KB FREED_HR
    FINAL_AVAIL=$(df --output=avail / | tail -1)
    FREED_KB=$(( FINAL_AVAIL - INITIAL_AVAIL ))
    FREED_HR=$(numfmt --to=iec --suffix=B $(( FREED_KB * 1024 )))
    echo -e "\nTotal space freed: $FREED_HR\n"
  fi
  log_info "Cleaning up internal state."
}
trap cleanup EXIT INT ERR

# ----- Usage & Controls -----
usage() {
  cat <<-EOF

	Usage: $SCRIPT_NAME [OPTIONS]

	Options:
	  -n, --dry-run       Dry‑run (commands printed, not executed)
	  -v, --verbose       Enable bash debug output
	  -c, --config FILE   Source additional configuration
	      --init          Re‑scaffold modules then exit
	      --yes           Non‑interactive; auto‑answer prompts “yes”
	  -h, --help          Show this help
	  --version           Show version and exit

	Script Controls:
	  • Use menu numbers to select actions
	  • 0 = Exit the script
	  • Toggle dry‑run via option or menu item
	  • Run as root for system‑level tasks
	EOF
  exit 1
}

# ----- Parse CLI -----
CONFIG_FILE="" FORCE_SCAFFOLD=false NONINTERACTIVE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--dry-run) DRY_RUN=true; shift ;;
    -v|--verbose) set -x; shift ;;
    -c|--config)  CONFIG_FILE="$2"; shift 2 ;;
    --init)       FORCE_SCAFFOLD=true; shift ;;
    --yes)        NONINTERACTIVE=true; shift ;;
    --version)    echo "$SCRIPT_NAME v$VERSION"; exit 0 ;;
    -h|--help)    usage ;;
    *) break ;;
  esac
done

# ----- Source Extra Config -----
if [[ -n "$CONFIG_FILE" ]]; then
  [[ -f "$CONFIG_FILE" ]] || { log_error "Config '$CONFIG_FILE' not found"; exit 1; }
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  log_info "Loaded config from $CONFIG_FILE"
fi

# ----- Scaffold Modules If Missing -----
scaffold_modules() {
  log_info "Scaffolding modules into $LIB_DIR"
  mkdir -p "$LIB_DIR"
  declare -A TPL

  TPL[apt_cache.sh]='#!/usr/bin/env bash
clean_apt_cache() {
  log_info "Cleaning APT cache"
  execute "apt-get clean"
  execute "apt-get autoclean"
  execute "apt-get autoremove -y"
}'
  TPL[thumbnail_cache.sh]='#!/usr/bin/env bash
clean_thumbnail_cache() {
  log_info "Cleaning thumbnail cache"
  execute "rm -rf \"$HOME/.cache/thumbnails\"/*"
}'
  TPL[old_logs.sh]='#!/usr/bin/env bash
remove_old_logs() {
  log_info "Removing system logs older than ${LOG_MAX_AGE:-7}d"
  execute "find /var/log -name '\''*.log'\'' -mtime +${LOG_MAX_AGE:-7} -delete"
}'
  TPL[temp_files.sh]='#!/usr/bin/env bash
remove_temp_files() {
  log_info "Deleting /tmp files older than ${TMP_MAX_AGE:-3}d"
  execute "find /tmp -type f -mtime +${TMP_MAX_AGE:-3} -delete"
}'
  TPL[trash.sh]='#!/usr/bin/env bash
clean_trash() {
  log_info "Emptying Trash older than ${TRASH_MAX_AGE:-7}d"
  execute "find \"$HOME/.local/share/Trash/files\" -mtime +${TRASH_MAX_AGE:-7} -delete"
}'
  TPL[browser_cache.sh]='#!/usr/bin/env bash
clear_cache_browser() {
  log_info "Cleaning browser caches"
  for d in \"$HOME/.cache/google-chrome\" \"$HOME/.cache/chromium\"; do
    [[ -d \"$d\" ]] && execute "rm -rf \"$d\"/*"
  done
}'
  TPL[large_files.sh]='#!/usr/bin/env bash
remove_large_files() {
  log_info "Removing large files (> ${MAX_SIZE:-100M}) older than ${MAX_AGE:-30}d in \$HOME"
  execute "find \"\$HOME\" -type f -size +\${MAX_SIZE:-100M} -mtime +\${MAX_AGE:-30} -delete"
}'
  TPL[docker_cleanup.sh]='#!/usr/bin/env bash
docker_cleanup() {
  log_info "Pruning Docker"
  execute "docker system prune -af --volumes"
}'
  TPL[journalctl_cleanup.sh]='#!/usr/bin/env bash
journalctl_cleanup() {
  log_info "Vacuuming journal"
  execute "journalctl --vacuum-size=\${JOURNAL_MAX_SIZE:-200M}"
}'
  TPL[tmpreaper_cleanup.sh]='#!/usr/bin/env bash
tmpreaper_cleanup() {
  log_info "Running tmpreaper"
  execute "tmpreaper --protect '\''*.X*'\'' \${TMPREAPER_AGE:-5d} /tmp"
}'
  TPL[tmpfiles_cleanup.sh]='#!/usr/bin/env bash
tmpfiles_cleanup() {
  log_info "Running systemd‑tmpfiles"
  execute "systemd-tmpfiles --clean"
}'
  TPL[logrotate_cleanup.sh]='#!/usr/bin/env bash
logrotate_cleanup() {
  log_info "Forcing logrotate"
  execute "logrotate --force /etc/logrotate.conf"
}'
  TPL[snap_cleanup.sh]='#!/usr/bin/env bash
snap_cleanup() {
  log_info "Removing old snaps"
  for rev in $(snap list --all | awk '\''/disabled/ {print $1, $3}'\''); do
    execute "snap remove $rev"
  done
}'

  for m in "${MODULES[@]}"; do
    target="$LIB_DIR/$m"
    if [[ ! -f "$target" ]] || $FORCE_SCAFFOLD; then
      printf '%s\n' "${TPL[$m]}" >"$target"
      chmod +x "$target"
      log_info "Created module $m"
    fi
  done
}

# Detect and scaffold if needed
missing=false
for m in "${MODULES[@]}"; do
  [[ -f "$LIB_DIR/$m" ]] || missing=true
done
if $missing || $FORCE_SCAFFOLD; then
  if $NONINTERACTIVE; then
    scaffold_modules
    $FORCE_SCAFFOLD && exit 0
  else
    echo "Missing modules in $LIB_DIR."
    read -rp "Generate now? [Y/n]: " ans
    [[ "$ans" =~ ^[Yy]|$ ]] && scaffold_modules || { log_error "Aborting."; exit 1; }
    $FORCE_SCAFFOLD && exit 0
  fi
fi

# ----- Source Modules -----
for m in "${MODULES[@]}"; do
  # shellcheck source=/dev/null
  source "$LIB_DIR/$m"
done

# ----- Old‑Kernel Cleanup -----
clean_old_kernels() {
  log_info "Removing old kernels"
  if command -v purge-old-kernels &>/dev/null; then
    execute "purge-old-kernels --keep 2 --purge"
    return
  fi
  local current pkg
  current="$(uname -r)"
  mapfile -t pkgs < <(dpkg-query -W -f='${Package}\n' 'linux-image-*' | grep -v "$current")
  for pkg in "${pkgs[@]}"; do
    execute "apt-get remove --purge -y $pkg"
  done
}

# ----- Detect & Delete Largest FS Items -----
detect_and_delete() {
  require_cmd whiptail
  log_info "Detecting largest directories and files"
  tmpfs=$(mktemp)
  # Top 8 dirs
  du -h --max-depth=1 / 2>/dev/null | sort -hr | head -n 8 >>"$tmpfs"
  echo >>"$tmpfs"
  # Top 8 files >10M
  find / -xdev -type f -size +10M -printf '%s\t%p\n' 2>/dev/null \
    | sort -nr | head -n 8 \
    | awk '{printf("%s\t%s\n",$1,$2)}' >>"$tmpfs"

  # Build checklist
  list=()
  while IFS=$'\t' read -r size path; do
    list+=("$path" "$size" off)
  done <"$tmpfs"

  choices=$(whiptail --title "Large FS Items" --checklist \
    "Select items to delete" 20 80 12 "${list[@]}" 3>&1 1>&2 2>&3)
  clear
  [[ -z "$choices" ]] && { whiptail --msgbox "No selection made." 8 50; return; }

  for item in $choices; do
    execute "rm -rf \"$item\""
    log_info "Deleted $item"
  done
  rm -f "$tmpfs"
}

# ----- Progress Indicator -----
clean_with_progress() {
  { echo 20; sleep 1; echo 50; sleep 1; echo 80; sleep 1; echo 100; sleep 1; } \
    | whiptail --gauge "Running full cleanup..." 8 60 0
}

# ----- Main Menu -----
main_menu() {
  # Print controls at top
  cat <<-EOC

	Controls:
	  • Menu number → select action
	  • 0 = exit
	  • -n flag or menu item → dry‑run mode

	EOC

  whiptail --title "Power Cleaner" --menu "Select action:" 24 70 18 \
    1  "Clean APT Cache" \
    2  "Clean Thumbnails" \
    3  "Remove Old Logs" \
    4  "Delete Temp Files" \
    5  "Empty Trash" \
    6  "Clean Browser Caches" \
    7  "Remove Large Files" \
    8  "Docker System Prune" \
    9  "Journalctl Vacuum" \
    10 "Tmpreaper Cleanup" \
    11 "Systemd‑tmpfiles Cleanup" \
    12 "Force Logrotate" \
    13 "Snap Revision Cleanup" \
    14 "Remove Old Kernels" \
    15 "Package Cleanup" \
    16 "Detect & Delete Large FS Items" \
    17 "Full Cleanup w/ Progress" \
    18 "Toggle Dry‑Run (Now: $DRY_RUN)" \
    0  "Exit" 3>&1 1>&2 2>&3
}

# ----- Menu Loop -----
while true; do
  choice=$(main_menu)
  case $choice in
    1)  clean_apt_cache ;;
    2)  clean_thumbnail_cache ;;
    3)  remove_old_logs ;;
    4)  remove_temp_files ;;
    5)  clean_trash ;;
    6)  clear_cache_browser ;;
    7)  remove_large_files ;;
    8)  docker_cleanup ;;
    9)  journalctl_cleanup ;;
    10) tmpreaper_cleanup ;;
    11) tmpfiles_cleanup ;;
    12) logrotate_cleanup ;;
    13) snap_cleanup ;;
    14) clean_old_kernels ;;
    15) clean_packages ;;
    16) detect_and_delete ;;
    17) clean_with_progress ;;
    18) DRY_RUN=!$DRY_RUN && log_info "Dry‑run: $DRY_RUN" ;;
    0)  log_info "Exiting. Stay tidy!" && exit 0 ;;
    *)  log_error "Invalid choice: $choice" ;;
  esac
done
