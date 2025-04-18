#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ----------------------------
# power_cleaner.sh v1.1
# Modular cleanup + interactive package removal
# ----------------------------

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$BASE_DIR/lib"
LOG_FILE="${LOGFILE:-/var/log/power_cleaner_$(date +'%Y%m%d_%H%M%S').log}"

MODULES=(
  "apt_cache.sh" "thumbnail_cache.sh" "old_logs.sh" "temp_files.sh"
  "trash.sh" "browser_cache.sh" "large_files.sh" "docker_cleanup.sh"
  "journalctl_cleanup.sh" "tmpreaper_cleanup.sh" "tmpfiles_cleanup.sh"
  "logrotate_cleanup.sh" "snap_cleanup.sh" "pkg_cleanup.sh"
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
# Error & Cleanup Traps
# ------------------------
cleanup() {
  log_info "Performing final cleanup."
}
trap cleanup EXIT INT ERR

# ----------------------------
# Scaffold Missing Modules
# ----------------------------
scaffold_modules() {
  log_info "Scaffolding modules into $LIB_DIR"
  mkdir -p "$LIB_DIR"  # safe directory creation :contentReference[oaicite:7]{index=7}

  declare -A TPL
  # … (other templates) …
  TPL[pkg_cleanup.sh]='#!/usr/bin/env bash
# Interactive large-package cleanup

detect_distro() {
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    echo "$ID"
  else
    lsb_release -si | tr '"'[:upper:]'"' '"'"[:lower:]'"'
  fi
}

get_pkg_sizes() {
  case "$(detect_distro)" in
    ubuntu|debian|kali)
      pkgs=$(apt-mark showmanual)
      dpkg-query -W --showformat="'"'${Installed-Size}\t${Package}\n'"'" |
        grep -Ff <(echo "$pkgs") | sort -rn
      ;;
    rpm*)
      rpm -qa --queryformat "%{SIZE}\t%{NAME}\n" | sort -rn
      ;;
    arch*)
      pacman -Qi | awk "/^Name/{n=\$3}/^Installed Size/{print \$4 \$5,n}" | sort -h -r
      ;;
    *)
      flatpak list --app --columns=size,name | sort -h -r
      ;;
  esac
}

clean_packages() {
  tmp=$(mktemp)
  get_pkg_sizes | head -n 20 >"$tmp"
  list=()
  while read -r sz pkg; do
    list+=("$pkg" "$sz" off)
  done <"$tmp"

  choices=$(dialog --clear --title "Large Packages" \
    --checklist "Select to uninstall:" 20 60 10 \
    "${list[@]}" 2>&1 >/dev/tty)
  clear
  [[ -z "$choices" ]] && { echo "No selection made."; return; }

  for pkg in $choices; do
    case "$(detect_distro)" in
      ubuntu|debian|kali) execute "sudo apt-get remove --purge -y $pkg" ;;
      fedora*)           execute "sudo dnf erase -y $pkg" ;;
      arch*)             execute "sudo pacman -Rs --noconfirm $pkg" ;;
      opensuse*)         execute "sudo zypper rm -y $pkg" ;;
      *)                 execute "flatpak uninstall -y $pkg" ;;
    esac
  done
  echo "Uninstalled selected packages."
}

# Write templates
  for m in "${MODULES[@]}"; do
    [[ -f "$LIB_DIR/$m" ]] || {
      echo "${TPL[$m]}" >"$LIB_DIR/$m"
      chmod +x "$LIB_DIR/$m"
    }
  done
}

# Initialize if modules missing
missing=false
for m in "${MODULES[@]}"; do
  [[ -f "$LIB_DIR/$m" ]] || missing=true
done
$missing && scaffold_modules

# Source all modules
for m in "${MODULES[@]}"; do
  # shellcheck source=/dev/null
  source "$LIB_DIR/$m"
done

# --------------------
# Full Cleanup Menu
# --------------------
clean_with_progress() {
  { echo 20; sleep 1; echo 50; sleep 1; echo 80; sleep 1; echo 100; } |
    whiptail --gauge "Running full cleanup..." 8 60 0
}

main_menu() {
  whiptail --title "Power Cleaner" --menu "Select action:" 18 70 12 \
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
    14 "Package Cleanup" \
    15 "Full Cleanup w/ Progress" \
    16 "Toggle Dry‑Run (Now: $DRY_RUN)" \
    0 "Exit" 3>&1 1>&2 2>&3
}

# -------------------
# Menu Loop Execution
# -------------------
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
    14) clean_packages ;;             # New package cleanup option
    15) clean_with_progress ;;
    16) DRY_RUN=!$DRY_RUN && log_info "Dry‑run: $DRY_RUN" ;;
    0) log_info "Exiting. Stay tidy!" && exit 0 ;;
    *) log_error "Invalid choice: $choice" ;;
  esac
done
