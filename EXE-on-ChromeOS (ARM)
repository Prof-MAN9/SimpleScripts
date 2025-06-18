#!/bin/bash

#====================#
#   Pi-Apps Setup    #
#====================#

# Error handler
error() {
  echo -e "\e[91m[ERROR] $1\e[0m"
  exit 1
}

# Ensure script is run as root
if [[ "$EUID" -ne 0 ]]; then
  error "This script must be run as root. Please use: sudo ./script.sh"
fi

clear
echo -e "\e[96mStarting Pi-Apps installation script...\e[0m"
sleep 1

# Function to safely install via Pi-Apps
def_piapps_install() {
  local app="$1"
  echo -e "\n\e[94mInstalling $app via Pi-Apps...\e[0m"
  pi-apps install "$app" || error "Failed to install $app."
}

# Download and install Pi-Apps
if ! command -v pi-apps &>/dev/null; then
  echo -e "\n\e[94mInstalling Pi-Apps...\e[0m"
  wget -qO- https://raw.githubusercontent.com/Botspot/pi-apps/master/install | bash || error "Pi-Apps installation failed."
else
  echo -e "\e[93mPi-Apps is already installed. Skipping...\e[0m"
fi

# Install Wine, Box64, Box86
def_piapps_install wine
def_piapps_install box64
def_piapps_install box86

# Run uninstall analytics (optional)
SCRIPT_DIR="$(readlink -f "$(dirname "$0")")"
if [ -x "${SCRIPT_DIR}/api" ]; then
  "${SCRIPT_DIR}/api" shlink_link script uninstall || echo "Warning: Failed to run uninstall analytics."
fi

# Prompt to uninstall YAD (GUI toolkit)
if ! dpkg -s yad &>/dev/null && command -v zenity &>/dev/null; then
  zenity --title='Pi-Apps' --window-icon="${SCRIPT_DIR}/icons/logo.png" \
    --list --text="Do you want to uninstall YAD?" \
    --ok-label=Yes --cancel-label=No \
    --column=foo --hide-header 2>/dev/null && \
    "${SCRIPT_DIR}/etc/terminal-run" "sudo apt purge -y yad; echo -e '\nClosing in 5 seconds.'; sleep 5" "Uninstalling YAD"
fi

# Clean up Pi-Apps shortcuts
echo -e "\n\e[94mCleaning up Pi-Apps shortcuts...\e[0m"
rm -f ~/.local/share/applications/pi-apps.desktop
rm -f ~/.local/share/applications/pi-apps-settings.desktop
rm -f ~/.config/autostart/pi-apps-updater.desktop
rm -f ~/Desktop/pi-apps.desktop

# Remove CLI launcher
sudo rm -f /usr/local/bin/pi-apps

# Final Message
echo -e "\n\e[92mUninstallation complete. Only \$HOME/pi-apps still remains.\e[0m"
echo -e "\e[97mIf Pi-Apps didn’t work for you, please consider submitting a bug report:\e[0m"
echo -e "\e[96m--> https://github.com/Botspot\e[0m"
echo -e "\n\e[92mScript completed successfully.\e[0m"

exit 0
