#!/usr/bin/env bash
# piapps-exe-setup.sh  v1.0
# Safer Pi-Apps installer + app installer + cleanup
set -euo pipefail
IFS=$'\n\t'

VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_PIAPPS="${HOME}/pi-apps"
MANAGE_SCRIPT="${HOME_PIAPPS}/manage"
LOGFILE="${LOGFILE:-$HOME/.piapps_install.log}"

# CLI flags
DRY_RUN=false
VERIFY=false
AUTO_YES=false
VERBOSE=false

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [--verify] [--dry-run] [--yes] [--verbose] [-h|--help]

  --verify    Show what would run (non-destructive checks).
  --dry-run   Print commands instead of executing.
  --yes       Assume "yes" to prompts.
  --verbose   More verbose logging.
  -h, --help  Show this help.
USAGE
  exit 0
}

# parse args
while (( $# )); do
  case "$1" in
    --verify) VERIFY=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) AUTO_YES=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

# Logging helpers
log()  { printf '%s | %s\n' "$(date +'%F %T')" "$*" | tee -a "$LOGFILE"; }
dbg()  { $VERBOSE && printf 'DBG: %s\n' "$*" | tee -a "$LOGFILE"; }
err()  { printf '\e[91m[ERROR]\e[0m %s\n' "$*" | tee -a "$LOGFILE" >&2; }
note() { printf '\e[96m%s\e[0m\n' "$*"; }

trap 'err "Script failed at line $LINENO"; exit 1' ERR
trap 'log "Interrupted"; exit 1' INT TERM

# Exec helper (respects dry-run / verify)
_execute() {
  local cmd="$*"
  if $VERIFY; then
    log "VERIFY: would run: $cmd"
    return 0
  fi
  if $DRY_RUN; then
    log "DRY-RUN: $cmd"
    return 0
  fi
  log "RUN: $cmd"
  bash -c "$cmd"
}

# Check a command exists
require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Required command not found: $1"
    return 1
  fi
  return 0
}

# Download helper (wget preferred, curl fallback)
download_and_exec_sh() {
  local url="$1"
  # download to temp and run via bash
  local tmp
  tmp="$(mktemp -t piapps_installer.XXXXXX.sh)"
  if command -v wget >/dev/null 2>&1; then
    _execute "wget -qO \"$tmp\" \"$url\""
  elif command -v curl >/dev/null 2>&1; then
    _execute "curl -fsSL \"$url\" -o \"$tmp\""
  else
    err "Neither wget nor curl is available to download: $url"
    return 1
  fi
  if $VERIFY || $DRY_RUN; then
    log "Installer downloaded to: $tmp (verify/dry-run mode; not executing)"
    return 0
  fi
  # run installer in a subshell to avoid polluting environment
  _execute "bash \"$tmp\""
  rm -f "$tmp" || true
  return 0
}

# Check architecture to avoid installing incompatible packages
arch_supported_for_box() {
  local arch
  arch="$(uname -m || true)"
  dbg "Detected arch: $arch"
  case "$arch" in
    aarch64|arm64|armv7l|armv6l) return 0 ;;
    *) return 1 ;;
  esac
}

# Idempotent pi-apps installer
install_pi_apps_if_missing() {
  if command -v pi-apps >/dev/null 2>&1 || [[ -x "$MANAGE_SCRIPT" ]]; then
    note "pi-apps already installed (skipping installation)."
    return 0
  fi

  note "pi-apps not found. Installing pi-apps..."
  # official upstream installer
  local installer_url="https://raw.githubusercontent.com/Botspot/pi-apps/master/install"
  download_and_exec_sh "$installer_url" || { err "Failed to install pi-apps"; return 1; }
  note "pi-apps installer requested. installation may require a shell restart (verify by checking ~/pi-apps)."
}

# Install a pi-apps app safely (tries manage script then pi-apps CLI)
piapps_install() {
  local app="$1"
  note "Installing '$app' via pi-apps..."
  if [[ -x "$MANAGE_SCRIPT" ]]; then
    _execute "\"$MANAGE_SCRIPT\" install \"$app\"" || err "manage install returned non-zero for $app"
  elif command -v pi-apps >/dev/null 2>&1; then
    _execute "pi-apps install \"$app\"" || err "pi-apps install returned non-zero for $app"
  else
    err "No pi-apps installer found to install '$app' (run installer first)."
    return 1
  fi
  # crude check: app folder exists under ~/pi-apps/apps/<app>
  if [[ -d "${HOME_PIAPPS}/apps/${app}" ]]; then
    dbg "Detected ${HOME_PIAPPS}/apps/${app}"
  else
    dbg "Warning: ${HOME_PIAPPS}/apps/${app} not present after install (this may be normal for some installers)."
  fi
}

# Remove helper that asks for sudo when needed
safe_remove_file() {
  local path="$1"
  if [[ -e "$path" ]]; then
    if [[ "$path" == /* ]]; then
      # system path, require sudo
      if $VERIFY || $DRY_RUN; then
        log "Would remove system file: $path"
      else
        if [[ $EUID -ne 0 ]]; then
          if ! $AUTO_YES; then
            read -rp "Remove system file $path (requires sudo)? [y/N]: " ans
            [[ "${ans,,}" != "y" ]] && { log "Skipping $path"; return 0; }
          fi
        fi
        _execute "sudo rm -f \"$path\"" || err "Failed to remove $path"
      fi
    else
      _execute "rm -f \"$path\"" || err "Failed to remove $path"
    fi
  else
    dbg "File not found (skipping): $path"
  fi
}

# Main flow
note "Starting pi-apps exe install/setup script (v $VERSION). Check log: $LOGFILE"

if $VERIFY; then
  note "VERIFY mode: no destructive changes will be performed."
fi
if $DRY_RUN; then
  note "DRY-RUN mode: commands will be printed but not executed."
fi

# 1) install pi-apps if needed
install_pi_apps_if_missing

# 2) install required runtime apps (only when arch is supported for box86/64)
APPS_TO_INSTALL=( "Wine" )
# box64/box86 only on supported arch
if arch_supported_for_box; then
  APPS_TO_INSTALL+=( "Box64" "Box86" )
else
  note "Box64/Box86 skipped: unsupported CPU architecture on this host."
fi

for a in "${APPS_TO_INSTALL[@]}"; do
  piapps_install "$a"
done

# 3) optional analytics/uninstall hook if provided
SCRIPT_DIR="$(dirname "$(realpath "$0" 2>/dev/null || echo "$PWD")")"
if [[ -x "${SCRIPT_DIR}/api" ]]; then
  note "Running installer analytics hook (optional)..."
  _execute "\"${SCRIPT_DIR}/api\" shlink_link script uninstall" || dbg "Analytics hook failed (non-fatal)"
fi

# 4) prompt/uninstall YAD (GUI toolkit) if present and zenity available
if dpkg -s yad &>/dev/null 2>&1 && command -v zenity >/dev/null 2>&1; then
  if $VERIFY || $DRY_RUN; then
    log "Would prompt to uninstall YAD (verify/dry-run mode)."
  else
    if $AUTO_YES; then
      note "Auto-confirm: uninstalling yad"
      _execute "sudo apt purge -y yad"
    else
      if zenity --question --title="Pi-Apps" --text="Do you want to uninstall YAD?"; then
        _execute "sudo apt purge -y yad"
        note "Uninstalled YAD (requested)."
      else
        note "Left YAD installed (user declined)."
      fi
    fi
  fi
fi

# 5) Clean up Pi-Apps shortcuts - only remove if they belong to pi-apps (exist)
note "Cleaning up pi-apps shortcuts and launcher (if present)..."
safe_remove_file "$HOME/.local/share/applications/pi-apps.desktop"
safe_remove_file "$HOME/.local/share/applications/pi-apps-settings.desktop"
safe_remove_file "$HOME/.config/autostart/pi-apps-updater.desktop"
safe_remove_file "$HOME/Desktop/pi-apps.desktop"

# Remove system-wide CLI if present
safe_remove_file "/usr/local/bin/pi-apps"

# 6) final messaging
note "Cleanup complete. The folder $HOME_PIAPPS (if present) was left intact."
note "If pi-apps didn't work for you, consider opening a bug at: https://github.com/Botspot"
log "Script finished successfully."

exit 0
