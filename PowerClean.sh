#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------------------------------------------------
# power_cleaner.sh v1.9
# Ultimate distro-aware, language-aware, privacy-safe maintenance suite
# -------------------------------------------------------------------

VERSION="1.9.0"
SCRIPT_NAME="$(basename "$0")"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$BASE_DIR/lib"
LOG_FILE="${LOGFILE:-$HOME/.power_cleaner_runs.log}"

# ----- Logging & Crash Handling -----
log(){ echo "$(date +'%F %T') | $*" | tee -a "$LOG_FILE"; }
trap 'log "ERROR on line $LINENO"; exit 1' ERR

# ----- Detect Distro & PM -----
if [[ -f /etc/os-release ]]; then source /etc/os-release; fi
DISTRO_ID="${ID:-unknown}"
case "$DISTRO_ID" in
  debian|ubuntu|linuxmint|raspbian) PM=apt ;;  
  fedora|rhel|centos|rocky|almalinux) PM=dnf ;;  
  arch|manjaro) PM=pacman ;;  
  opensuse*|suse) PM=zypper ;;  
  alpine) PM=apk ;;  
  gentoo) PM=emerge ;;  
  *) PM="" ;;
esac

# ----- Initial State & Trends -----
INITIAL_FREE=$(df --output=avail / | tail -1)
CURRENT_FREE_H=$(df -h / | tail -1 | awk '{print $4}')
PREV_FREE=$(grep -h "Freed total:" "$LOG_FILE" | tail -1 | awk '{print $3}' | tr -d 'MGiBKB') || PREV_FREE=0

# ----- Startup Banner -----
echo "-------------------------------------------"
echo " Power Cleaner v$VERSION"
echo " Distro: ${NAME:-Unknown} ($DISTRO_ID), PM: ${PM:-none}"
echo " Free space: $CURRENT_FREE_H" 
echo " Previous freed: ${PREV_FREE:-none}" 
echo "-------------------------------------------"

# ----- Define Utility Functions -----
execute(){
  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] $*"
  else
    log "EXEC: $*"
    eval "$@"
  fi
}

offer_timer_setup(){
  read -rp "Set weekly automated cleanup via systemd-timer? [y/N]: " r
  if [[ "${r,,}" == "y" ]]; then
    cp "$0" "$HOME/.local/bin/power_cleaner"
    cat > "$HOME/.config/systemd/user/power_cleaner.timer" <<EOF
[Unit]
Description=Weekly PowerCleaner run
[Timer]
OnCalendar=weekly
Persistent=true
[Install]
WantedBy=timers.target
EOF
    systemctl --user enable --now power_cleaner.timer
    log "Scheduled weekly cleanup"
  fi
}

# ----- Scaffold Modules -----
scaffold_modules(){
  mkdir -p "$LIB_DIR"
  declare -A TPL
  # Core PM cleanup
  TPL[apt_cleanup.sh]='#!/usr/bin/env bash
clean_apt(){ execute "apt-get clean && apt-get autoclean && apt-get autoremove -y"; }'
  TPL[dnf_cleanup.sh]='#!/usr/bin/env bash
clean_dnf(){ execute "dnf clean all -y && dnf autoremove -y"; }'
  TPL[pacman_cleanup.sh]='#!/usr/bin/env bash
clean_pacman(){ execute "pacman -Sc --noconfirm && pacman -Rns --noconfirm \$(pacman -Qdtq || true)"; }'
  TPL[zypper_cleanup.sh]='#!/usr/bin/env bash
clean_zypper(){ execute "zypper clean --all && zypper rm -u -y"; }'
  TPL[apk_cleanup.sh]='#!/usr/bin/env bash
clean_apk(){ execute "apk cache clean && apk cache purge"; }'
  TPL[emerge_cleanup.sh]='#!/usr/bin/env bash
clean_emerge(){ execute "emerge --depclean --ask"; }'
  
  # Language caches
  TPL[cargo_cleanup.sh]='#!/usr/bin/env bash
clean_cargo(){ execute "cargo cache --autoclean"; }'
  TPL[gradle_cleanup.sh]='#!/usr/bin/env bash
clean_gradle(){ execute "find \$HOME/.gradle -type f -mtime +30 -delete"; }'
  TPL[pip_cleanup.sh]='#!/usr/bin/env bash
clean_pip(){ execute "pip cache purge"; }'
  TPL[npm_cleanup.sh]='#!/usr/bin/env bash
clean_npm(){ execute "npm cache clean --force"; }'
  TPL[yarn_cleanup.sh]='#!/usr/bin/env bash
clean_yarn(){ execute "yarn cache clean"; }'
  TPL[composer_cleanup.sh]='#!/usr/bin/env bash
clean_composer(){ execute "composer clear-cache"; }'
  
  # Log and privacy
  TPL[truncate_logs.sh]='#!/usr/bin/env bash
truncate_logs(){ find /var/log -type f -name "*.log" -exec truncate -s 0 {} +; }'
  TPL[bleachbit.sh]='#!/usr/bin/env bash
bleachbit_clean(){ execute "bleachbit --clean system.cache system.thumbnail system.trash system.tmp"; }'
  TPL[wipe_free.sh]='#!/usr/bin/env bash
wipe_free(){ echo Redacting free space...; execute "dd if=/dev/zero of=\$(mktemp -p /tmp wipe.XXXXXX) bs=1M || true"; rm -f /tmp/wipe.*; }'
  
  # Container cleanup
  TPL[docker_prune.sh]='#!/usr/bin/env bash
docker_cleanup(){ execute "docker system prune -af --volumes"; execute "docker volume prune -f"; }'
  TPL[podman_prune.sh]='#!/usr/bin/env bash
podman_cleanup(){ execute "podman system prune -af"; }'
  
  # Dev logs
  TPL[pm2_logs.sh]='#!/usr/bin/env bash
pm2_logs(){ find \$HOME/.pm2/logs -type f -exec truncate -s 0 {} +; }'
  
  # Duplicate and interactive
  TPL[dupe_rmlint.sh]='#!/usr/bin/env bash
duplicate_files(){ execute "rmlint --gui"; }'
  TPL[ncdu.sh]='#!/usr/bin/env bash
run_ncdu(){ exec ncdu /; }
'
  
  # Archive old logs
  TPL[archive_logs.sh]='#!/usr/bin/env bash
archive_logs(){ execute "tar czf \$HOME/var_logs_$(date +%Y%m%d).tar.gz /var/log"; find /var/log -type f -mtime +30 -delete; }'
  
  for m in "${!TPL[@]}"; do
    echo -e "${TPL[$m]}" > "$LIB_DIR/$m"
    chmod +x "$LIB_DIR/$m"
    log "Scaffolded $m"
  done
}
if [[ ! -d "$LIB_DIR" ]]; then
  scaffold_modules
fi

# ----- Source Modules Conditionally -----
source_modules=(
  "${PM}_cleanup.sh"
  "truncate_logs.sh"
  "archive_logs.sh"
  "bleachbit.sh"
  "wipe_free.sh"
  "docker_prune.sh"
  "podman_prune.sh"
  "pm2_logs.sh"
  "cargo_cleanup.sh"
  "gradle_cleanup.sh"
  "pip_cleanup.sh"
  "npm_cleanup.sh"
  "yarn_cleanup.sh"
  "composer_cleanup.sh"
  "dupe_rmlint.sh"
  "ncdu.sh"
)
for mod in "${source_modules[@]}"; do
  [[ -f "$LIB_DIR/$mod" ]] && source "$LIB_DIR/$mod"
done

# ----- Pre-backup & Trend -----
if [[ "${1:-}" == "--pre-backup" ]]; then
  log "Running pre-backup quick pass"
  suggest_caches
  truncate_logs
  clean_${PM}
  exit 0
fi

# ----- Offer Timer Setup -----
offer_timer_setup

# ----- Main Menu -----
main_menu(){
  whiptail --title "Power Cleaner v$VERSION" \
    --menu "Free: $CURRENT_FREE_H - Choose action:" 30 80 20 \
    1 "PM Cache Cleanup" \
    2 "Truncate System Logs" \
    3 "Archive & Cleanup /var/log" \
    4 "BleachBit Quick Clean" \
    5 "Wipe Free Space (privacy)" \
    6 "Container Cleanup (Docker/Podman)" \
    7 "PM2 Log Truncate" \
    8 "Language Caches" \
    9 "Duplicate File Finder" \
    10 "Interactive ncdu" \
    11 "Full Cleanup w/ Progress" \
    12 "Toggle Dry-Run ($DRY_RUN)" \
    0 "Exit" 3>&1 1>&2 2>&3
}

# ----- Loop -----
while true; do
  choice=$(main_menu)
  case $choice in
    1) clean_${PM};;
    2) truncate_logs;;
    3) archive_logs;;
    4) bleachbit_clean;;
    5) wipe_free;;
    6) docker_cleanup; podman_cleanup;;
    7) pm2_logs;;
    8) clean_cargo; clean_gradle; clean_pip; clean_npm; clean_yarn; clean_composer;;
    9) duplicate_files;;
    10) run_ncdu;;
    11) clean_with_progress;;
    12) DRY_RUN=!$DRY_RUN; log "Dry-run=$DRY_RUN";;
    0) log "Exiting. Freed total: $(df --output=avail / | tail -1)"; exit 0;;
    *) log "Invalid choice";;
  esac
done
