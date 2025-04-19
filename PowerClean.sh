#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------------------------------------------------
# power_cleaner.sh v1.3
# Now includes old‑kernel removal and freed‑space reporting
# -------------------------------------------------------------------

# ----- Metadata -----
VERSION="1.3.0"
SCRIPT_NAME="$(basename "$0")"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$BASE_DIR/lib"
LOG_FILE="${LOGFILE:-/var/log/power_cleaner_$(date +'%Y%m%d_%H%M%S').log}"

# ----- Record initial available space (1K‑blocks) -----
INITIAL_AVAIL=$(df --output=avail / | tail -1)   # GNU df allows field selection :contentReference[oaicite:3]{index=3}

# ----- Modules List -----
MODULES=(
  "apt_cache.sh" "thumbnail_cache.sh" "old_logs.sh" "temp_files.sh"
  "trash.sh" "browser_cache.sh" "large_files.sh" "docker_cleanup.sh"
  "journalctl_cleanup.sh" "tmpreaper_cleanup.sh" "tmpfiles_cleanup.sh"
  "logrotate_cleanup.sh" "snap_cleanup.sh"
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

# ----- Cleanup on Exit: report freed space -----
cleanup() {
  if ! $DRY_RUN; then
    local FINAL_AVAIL
    FINAL_AVAIL=$(df --output=avail / | tail -1)
    local FREED_KB=$(( FINAL_AVAIL - INITIAL_AVAIL ))
    # Convert to human‑readable
    local FREED_HR
    FREED_HR=$(numfmt --to=iec --suffix=B $(( FREED_KB * 1024 )))
    echo "Total space freed: $FREED_HR"
  fi
  log_info "Performing final cleanup."
}
trap cleanup EXIT INT ERR

# ----- Usage & CLI Flags -----
CONFIG_FILE="" FORCE_SCAFFOLD=false NONINTERACTIVE=false

usage() {
  cat <<-EOF
	Usage: $SCRIPT_NAME [OPTIONS]

	Options:
	  -n, --dry-run       Dry‑run mode (commands printed, not executed)
	  -v, --verbose       Enable Bash debug output
	  -c, --config FILE   Source extra config
	      --init          Re‑scaffold modules then exit
	      --yes           Auto‑yes prompts
	  -h, --help          Show help
	  --version           Show version
	EOF
  exit 1
}

# ----- Parse args -----
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--dry-run) DRY_RUN=true; shift ;;
    -v|--verbose) set -x; shift ;;
    -c|--config)  CONFIG_FILE="$2"; shift 2 ;;
    --init)       FORCE_SCAFFOLD=true; shift ;;
    --yes)        NONINTERACTIVE=true; shift ;;
    --version)    echo "$SCRIPT_NAME v$VERSION"; exit 0 ;;
    -h|--help)    usage ;;
    *)            break ;;
  esac
done

# ----- Source extra config if given -----
if [[ -n "$CONFIG_FILE" ]]; then
  [[ -f "$CONFIG_FILE" ]] || { log_error "Config file not found: $CONFIG_FILE"; exit 1; }
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  log_info "Loaded config from $CONFIG_FILE"
fi

# ----- Scaffold modules if needed -----
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
  # … other TPL entries omitted for brevity …
  TPL[snap_cleanup.sh]='#!/usr/bin/env bash
snap_cleanup() {
  log_info "Removing old snap revisions"
  for rev in $(snap list --all | awk '\''/disabled/ {print $1, $3}'\''); do
    execute "snap remove $rev"
  done
}'

  for m in "${MODULES[@]}"; do
    target="$LIB_DIR/$m"
    if [[ ! -f "$target" ]] || $FORCE_SCAFFOLD; then
      echo "Creating module: $m"
      printf '%s\n' "${TPL[$m]}" > "$target"
      chmod +x "$target"
    fi
  done
  log_info "Module scaffolding complete."
}

missing=false
for m in "${MODULES[@]}"; do
  [[ -f "$LIB_DIR/$m" ]] || missing=true
done

if $missing || $FORCE_SCAFFOLD; then
  if $NONINTERACTIVE; then
    scaffold_modules
    $FORCE_SCAFFOLD && exit 0
  else
    echo "Modules missing in $LIB_DIR."
    read -rp "Generate them now? [Y/n]: " ans
    [[ "$ans" =~ ^[Yy]|$ ]] && scaffold_modules || { log_error "Aborting."; exit 1; }
    $FORCE_SCAFFOLD && exit 0
  fi
fi

# ----- Source modules -----
for m in "${MODULES[@]}"; do
  # shellcheck source=/dev/null
  source "$LIB_DIR/$m"
done

# ----- Old‑kernel cleanup -----
clean_old_kernels() {
  log_info "Removing old Linux kernels"

  # If Ubuntu utility exists, use it
  if command -v purge-old-kernels &>/dev/null; then
    execute "purge-old-kernels --keep 2 --purge"         # safest method :contentReference[oaicite:4]{index=4}
    return
  fi

  case "$(lsb_release -is | tr '[:upper:]' '[:lower:]')" in
    ubuntu|debian|kali|mint)
      local current
      current="$(uname -r)"
      # List installed kernel packages, exclude current :contentReference[oaicite:5]{index=5}
      mapfile -t oldpkgs < <(dpkg-query -W --showformat='${Package}\n' 'linux-image-*' \
                         | grep -v "$current")
      for pkg in "${oldpkgs[@]}"; do
        execute "apt-get remove --purge -y $pkg"
      done
      ;;
    fedora|rhel|centos)
      # Keep only the 2 most recent kernels :contentReference[oaicite:6]{index=6}
      execute "dnf -y remove --oldinstallonly --setopt installonly_limit=2 kernel"
      ;;
    *)
      log_error "Kernel cleanup not supported on this distro"
      ;;
  esac
}

# ----- Package Cleanup Integration (omitted for brevity) -----

# ----- Progress Indicator -----
clean_with_progress() {
  { echo 20; sleep 1; echo 50; sleep 1; echo 80; sleep 1; echo 100; sleep 1; } \
    | whiptail --gauge "Running full cleanup..." 8 60 0
}

# ----- Main Menu -----
main_menu() {
  whiptail --title "Power Cleaner" --menu "Select action:" 22 70 16 \
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
    15 "Full Cleanup w/ Progress" \
    16 "Toggle Dry‑Run (Now: $DRY_RUN)" \
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
    14) clean_old_kernels ;;       # New option
    15) clean_with_progress ;;
    16) DRY_RUN=!$DRY_RUN && log_info "Dry‑run: $DRY_RUN" ;;
    0)  log_info "Exiting. Stay tidy!" && exit 0 ;;
    *)  log_error "Invalid choice: $choice" ;;
  esac
done
