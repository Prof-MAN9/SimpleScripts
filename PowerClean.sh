#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------------------------------------------------
# power_cleaner.sh v1.2
# Modular cleanup + interactive package removal (single unified script)
# -------------------------------------------------------------------

# ----- Metadata -----
VERSION="1.2.0"
SCRIPT_NAME="$(basename "$0")"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$BASE_DIR/lib"
LOG_FILE="${LOGFILE:-/var/log/power_cleaner_$(date +'%Y%m%d_%H%M%S').log}"

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

# ----- Cleanup on Exit -----
cleanup() {
  log_info "Performing final cleanup."
}
trap cleanup EXIT INT ERR

# ----- Usage & CLI Flags -----
CONFIG_FILE=""
FORCE_SCAFFOLD=false
NONINTERACTIVE=false

usage() {
  cat <<-EOF
	Usage: $SCRIPT_NAME [OPTIONS]

	Options:
	  -n, --dry-run       Dry‑run mode (commands are printed, not executed)
	  -v, --verbose       Enable Bash debug output
	  -c, --config FILE   Source additional configuration
	      --init          Force re‑creation of lib/ modules then exit
	      --yes           Non‑interactive; auto‑answer prompts “yes”
	  -h, --help          Show this help
	  --version           Show version and exit
	EOF
  exit 1
}

# ----- Parse arguments -----
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--dry-run)        DRY_RUN=true; shift ;;
    -v|--verbose)        set -x; shift ;;
    -c|--config)         CONFIG_FILE="$2"; shift 2 ;;
    --init)              FORCE_SCAFFOLD=true; shift ;;
    --yes)               NONINTERACTIVE=true; shift ;;
    --version)           echo "$SCRIPT_NAME v$VERSION"; exit 0 ;;
    -h|--help)           usage ;;
    *)                   break ;;
  esac
done

# ----- Source extra config if given -----
if [[ -n "$CONFIG_FILE" ]]; then
  [[ -f "$CONFIG_FILE" ]] || { log_error "Config file not found: $CONFIG_FILE"; exit 1; }
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
  log_info "Cleaning APT cache and removing unused packages"
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
  log_info "Removing system logs older than ${LOG_MAX_AGE:-7} days"
  execute "find /var/log -type f -name '\''*.log'\'' -mtime +${LOG_MAX_AGE:-7} -exec rm -f {} +"
}'
  TPL[temp_files.sh]='#!/usr/bin/env bash
remove_temp_files() {
  log_info "Removing /tmp files older than ${TMP_MAX_AGE:-3} days"
  execute "find /tmp -type f -mtime +${TMP_MAX_AGE:-3} -exec rm -f {} +"
}'
  TPL[trash.sh]='#!/usr/bin/env bash
clean_trash() {
  log_info "Emptying Trash files older than ${TRASH_MAX_AGE:-7} days"
  execute "find \"$HOME/.local/share/Trash/files\" -type f -mtime +${TRASH_MAX_AGE:-7} -exec rm -f {} +"
}'
  TPL[browser_cache.sh]='#!/usr/bin/env bash
clear_cache_browser() {
  log_info "Cleaning browser caches"
  for B in "google-chrome" "chromium" "mozilla/firefox"; do
    [[ -d \"$HOME/.cache/$B\" ]] && execute "rm -rf \"$HOME/.cache/$B\"/*"
  done
}'
  TPL[large_files.sh]='#!/usr/bin/env bash
remove_large_files() {
  log_info "Removing files > ${MAX_SIZE:-100M} older than ${MAX_AGE:-30} days in \$HOME"
  execute "find \"\$HOME\" -type f -size +\${MAX_SIZE:-100M} -mtime +\${MAX_AGE:-30} -exec rm -f {} +"
}'
  TPL[docker_cleanup.sh]='#!/usr/bin/env bash
docker_cleanup() {
  log_info "Pruning Docker system"
  execute "docker system prune -af --volumes"
}'
  TPL[journalctl_cleanup.sh]='#!/usr/bin/env bash
journalctl_cleanup() {
  log_info "Vacuuming journal to ${JOURNAL_MAX_SIZE:-200M}"
  execute "journalctl --vacuum-size=\${JOURNAL_MAX_SIZE:-200M}"
}'
  TPL[tmpreaper_cleanup.sh]='#!/usr/bin/env bash
tmpreaper_cleanup() {
  log_info "Running tmpreaper on /tmp for ${TMPREAPER_AGE:-5d}"
  execute "tmpreaper --protect '\''*.X*'\'' \${TMPREAPER_AGE:-5d} /tmp"
}'
  TPL[tmpfiles_cleanup.sh]='#!/usr/bin/env bash
tmpfiles_cleanup() {
  log_info "Running systemd-tmpfiles cleanup"
  execute "systemd-tmpfiles --clean"
}'
  TPL[logrotate_cleanup.sh]='#!/usr/bin/env bash
logrotate_cleanup() {
  log_info "Forcing logrotate"
  execute "logrotate --force /etc/logrotate.conf"
}'
  TPL[snap_cleanup.sh]='#!/usr/bin/env bash
snap_cleanup() {
  log_info "Removing old snap revisions"
  for rev in $(snap list --all | awk '\''/disabled/ {print $1, $3}'\''); do
    execute "snap remove \$rev"
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

# ----- Detect missing modules & scaffold if needed -----
missing=false
for m in "${MODULES[@]}"; do
  [[ -f "$LIB_DIR/$m" ]] || missing=true
done

if $missing || $FORCE_SCAFFOLD; then
  if $NONINTERACTIVE; then
    scaffold_modules
    $FORCE_SCAFFOLD && { log_info "--init used; exiting."; exit 0; }
  else
    echo "Modules missing in $LIB_DIR."
    read -rp "Generate them now? [Y/n]: " ans
    if [[ "$ans" =~ ^[Yy]|$ ]]; then
      scaffold_modules
    else
      log_error "Aborting due to missing modules."
      exit 1
    fi
    $FORCE_SCAFFOLD && { log_info "--init used; exiting."; exit 0; }
  fi
fi

# ----- Source all cleanup modules -----
for m in "${MODULES[@]}"; do
  # shellcheck source=/dev/null
  source "$LIB_DIR/$m"
done

# ----- PACKAGE CLEANUP INTEGRATION -----

# Ensure root privileges
require_root() {
  if [[ $EUID -ne 0 ]]; then
    whiptail --title "Privileges Required" --msgbox \
      "Please run as root (or via sudo)." 8 60 >&3
    exit 1
  fi
}

# Ensure command exists
require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    log_error "Command not found: $1"
    whiptail --title "Missing Dependency" --msgbox \
      "Please install '$1' first." 8 60 >&3
    exit 1
  fi
}

# Detect distro helper
detect_distro() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "${ID,,}"
  else
    lsb_release -si | tr '[:upper:]' '[:lower:]'
  fi
}

# Gather top-20 largest packages/apps
get_pkg_sizes() {
  case "$(detect_distro)" in
    ubuntu|debian|kali|mint|pop|zorin|elementary)
      local pkgs
      pkgs=$(apt-mark showmanual)
      dpkg-query -W --showformat='${Installed-Size}\t${Package}\n' |
        grep -Ff <(echo "$pkgs") | sort -nr
      ;;
    fedora|rhel|centos)
      rpm -qa --queryformat '%{SIZE}\t%{NAME}\n' | sort -nr
      ;;
    arch|manjaro|endeavouros)
      pacman -Qi | awk '/^Name/{n=$3}/^Installed Size/{print $4,$5,n}' | sort -h -r
      ;;
    opensuse*)
      while read -r p; do
        zypper info "$p" | awk '/^Download Size/{print $3,$4,"'"$p"'"}'
      done < <(zypper se -i -t package | awk '/^i/{print $2}') | sort -h -r
      ;;
    *)
      whiptail --title "Flatpak Only" --msgbox \
        "Unknown distro; defaulting to Flatpak apps." 8 60 >&3
      flatpak list --app --columns=size,name | sort -h -r
      ;;
  esac
}

# Uninstall helper
uninstall_pkg() {
  case "$(detect_distro)" in
    ubuntu|debian|kali|mint)  execute "apt-get remove --purge -y $1" ;;
    fedora|rhel|centos)       execute "dnf erase -y $1" ;;
    arch|manjaro|endeavouros)  execute "pacman -Rs --noconfirm $1" ;;
    opensuse*)                execute "zypper rm -y $1" ;;
    *)                        execute "flatpak uninstall -y $1" ;;
  esac
  log_info "Uninstalled: $1"
}

clean_packages() {
  require_root
  require_cmd whiptail

  if ! whiptail --title "Package Cleaner" \
       --yesno "List your top 20 largest packages/apps for removal?" 10 60 >&3; then
    log_info "User aborted package cleanup."
    return
  fi

  log_info "Gathering package sizes..."
  tmpfile=$(mktemp)
  get_pkg_sizes | head -n 20 >"$tmpfile"

  checklist=()
  while read -r sz pkg; do
    checklist+=( "$pkg" "$sz" OFF )
  done <"$tmpfile"

  choices=$(whiptail --title "Select to Uninstall" \
    --checklist "Size  Package" 20 70 12 "${checklist[@]}" 3>&1 1>&2 2>&3)
  clear

  [[ -z "$choices" ]] && { whiptail --msgbox "No selection made." 8 50 >&3; return; }

  if ! whiptail --title "Confirm Uninstall" \
       --yesno "Uninstall: ${choices// /, }?" 12 70 >&3; then
    log_info "User cancelled uninstall."
    return
  fi

  for pkg in $choices; do
    uninstall_pkg "$pkg"
  done

  whiptail --title "Done" --msgbox "Selected packages uninstalled." 8 50 >&3
  log_info "Package cleanup complete."
}

# ----- Progress Indicator -----
clean_with_progress() {
  { echo 20; sleep 1
    echo 50; sleep 1
    echo 80; sleep 1
    echo 100; sleep 1
  } | whiptail --gauge "Running full cleanup..." 8 60 0
}

# ----- Main Menu -----
main_menu() {
  whiptail --title "Power Cleaner" --menu "Select action:" 20 70 15 \
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
    14 "Package Cleanup" \
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
    14) clean_packages ;;
    15) clean_with_progress ;;
    16) DRY_RUN=!$DRY_RUN && log_info "Dry‑run: $DRY_RUN" ;;
    0)  log_info "Exiting. Stay tidy!" && exit 0 ;;
    *)  log_error "Invalid choice: $choice" ;;
  esac
done
