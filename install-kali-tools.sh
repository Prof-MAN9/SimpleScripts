#!/usr/bin/env bash

set -Eeuo pipefail
trap 'log "Error on line $LINENO. Exiting."; exit 1' ERR

LOGFILE="/var/log/kali-tools-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

TOOLS=(
  nmap masscan ipscan netscan openvas \
  metasploit-framework nessus burpsuite owasp-zap \
  john aircrack-ng hydra medusa thc-hydra \
  w3af beef sqlmap wifite reaver \
  setoolkit phishing-tank steghide truecrypt \
  wireshark tcpdump tshark meterpreter \
  cobaltstrike empire immunity-debugger x64dbg \
  binaryninja recon-ng dnsrecon \
  nmap-scripts splunk elasticsearch logstash kibana \
  weevil rainbowcrack phishing-frenzy hashcat \
  kismet ettercap idapro maltego \
  parrotsec blackarch
)

log "Starting installation of ${#TOOLS[@]} tools..."

# Ensure we have up-to-date package lists
apt-get update -y

install_tool() {
  local pkg="$1"
  if dpkg -s "$pkg" &> /dev/null; then
    log "Already installed: $pkg"
  else
    log "Installing: $pkg"
    if ! apt-get install -y "$pkg"; then
      log "Failed to install: $pkg"
    fi
  fi
}

for tool in "${TOOLS[@]}"; do
  install_tool "$tool"
done

log "Installation complete."
