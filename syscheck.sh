#!/usr/bin/env bash
# SysCheck.sh  v1.0.0
# Comprehensive system health report: CPU, memory, disk, SMART, temps, services, network
# Usage: ./SysCheck.sh [--json] [--watch N] [--no-color] [--output FILE] [-h|--help]
set -euo pipefail
IFS=$'\n\t'

VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"

# ─────────────────────────────────────────────
# CLI flags
# ─────────────────────────────────────────────
OPT_JSON=false
OPT_WATCH=0          # 0 = run once; N = loop every N seconds
OPT_COLOR=true
OPT_OUTPUT=""        # path to save report, empty = stdout only
OPT_SECTIONS=""      # comma-separated subset, empty = all

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [OPTIONS]

System health report: CPU, memory, disk, temperatures, SMART, services, network.

Options:
  --json              Output machine-readable JSON instead of the pretty report.
  --watch N           Refresh every N seconds (like watch mode, Ctrl-C to stop).
  --no-color          Disable ANSI colour output.
  --output FILE       Save report to FILE in addition to stdout.
  --sections LIST     Comma-separated list of sections to run.
                      Available: cpu,memory,disk,smart,temps,services,network,security,processes
  -h, --help          Show this help.
  -v, --version       Show version.

Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME --sections cpu,memory,disk
  $SCRIPT_NAME --watch 10
  $SCRIPT_NAME --json --output /tmp/health.json
USAGE
  exit 0
}

while (( $# )); do
  case "$1" in
    --json)        OPT_JSON=true; shift ;;
    --no-color)    OPT_COLOR=false; shift ;;
    --watch)       OPT_WATCH="${2:?'--watch requires a value'}"; shift 2 ;;
    --output)      OPT_OUTPUT="${2:?'--output requires a path'}"; shift 2 ;;
    --sections)    OPT_SECTIONS="${2:?'--sections requires a value'}"; shift 2 ;;
    -h|--help)     usage ;;
    -v|--version)  echo "$SCRIPT_NAME v$VERSION"; exit 0 ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

# ─────────────────────────────────────────────
# Colour palette (degrades gracefully)
# ─────────────────────────────────────────────
if $OPT_COLOR && [[ -t 1 ]]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_RED='\033[0;31m'
  C_BRED='\033[1;31m'
  C_YEL='\033[0;33m'
  C_BYEL='\033[1;33m'
  C_GRN='\033[0;32m'
  C_BGRN='\033[1;32m'
  C_CYN='\033[0;36m'
  C_BCYN='\033[1;36m'
  C_MAG='\033[0;35m'
  C_BMAG='\033[1;35m'
  C_WHT='\033[1;37m'
  C_BLU='\033[0;34m'
  C_BBLU='\033[1;34m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_BRED='' C_YEL='' C_BYEL=''
  C_GRN='' C_BGRN='' C_CYN='' C_BCYN='' C_MAG='' C_BMAG='' C_WHT=''
  C_BLU='' C_BBLU=''
fi

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
has()   { command -v "$1" >/dev/null 2>&1; }
pad()   { printf '%-*s' "$1" "$2"; }  # left-pad to width
rpad()  { printf '%*s'  "$1" "$2"; }  # right-pad (right-align)

# Severity colouring: ok / warn / crit / info
colour_level() {
  local level="$1" text="$2"
  case "$level" in
    ok)   printf "${C_BGRN}%s${C_RESET}" "$text" ;;
    warn) printf "${C_BYEL}%s${C_RESET}" "$text" ;;
    crit) printf "${C_BRED}%s${C_RESET}" "$text" ;;
    info) printf "${C_BCYN}%s${C_RESET}" "$text" ;;
    dim)  printf "${C_DIM}%s${C_RESET}"  "$text" ;;
    *)    printf "%s" "$text" ;;
  esac
}

# Section header
section_header() {
  local title="$1" icon="${2:-●}"
  local line
  line="$(printf '─%.0s' {1..60})"
  printf "\n${C_BBLU}%s${C_RESET}\n" "$line"
  printf " ${C_BMAG}%s${C_RESET}  ${C_BOLD}${C_WHT}%s${C_RESET}\n" "$icon" "$title"
  printf "${C_BBLU}%s${C_RESET}\n" "$line"
}

# Key-value row (with optional bar)
kv() {
  local key="$1" val="$2" level="${3:-}"
  local col_key="${C_CYN}${key}${C_RESET}"
  if [[ -n "$level" ]]; then
    printf "  %-28b %b\n" "$col_key" "$(colour_level "$level" "$val")"
  else
    printf "  %-28b %s\n" "$col_key" "$val"
  fi
}

# ASCII progress bar (0-100 percentage, width)
bar() {
  local pct="$1" width="${2:-30}" level="${3:-ok}"
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar_str=""
  bar_str+="$(printf '█%.0s' $(seq 1 $filled 2>/dev/null || true))"
  bar_str+="$(printf '░%.0s' $(seq 1 $empty  2>/dev/null || true))"
  colour_level "$level" "$bar_str"
  printf " ${C_DIM}%3d%%${C_RESET}" "$pct"
}

# Threshold helper → returns level string
threshold() {
  local val="$1" warn="$2" crit="$3"
  if   (( val >= crit )); then echo "crit"
  elif (( val >= warn )); then echo "warn"
  else echo "ok"
  fi
}

# Section guard
section_enabled() {
  [[ -z "$OPT_SECTIONS" ]] && return 0
  local s
  IFS=',' read -ra s <<< "$OPT_SECTIONS"
  local sec
  for sec in "${s[@]}"; do
    [[ "$sec" == "$1" ]] && return 0
  done
  return 1
}

# JSON accumulator
declare -A JSON_DATA=()
json_add() { JSON_DATA["$1"]="$2"; }
json_dump() {
  printf '{\n'
  local first=true
  local k
  for k in "${!JSON_DATA[@]}"; do
    $first || printf ',\n'
    printf '  "%s": %s' "$k" "${JSON_DATA[$k]}"
    first=false
  done
  printf '\n}\n'
}

# ─────────────────────────────────────────────
# OUTPUT SINK
# ─────────────────────────────────────────────
# We tee to a file if --output is set
REPORT_LINES=()
print_line() { printf "%b\n" "$@"; }  # used for raw print; captured by tee at end

# Accumulate output so we can optionally write to file
REPORT_BUFFER=""
exec_with_capture() { "$@" 2>&1; }

# ─────────────────────────────────────────────
# SECTION: System Overview
# ─────────────────────────────────────────────
section_overview() {
  section_header "System Overview" "🖥"

  local hostname os_name kernel arch uptime_s uptime_hr
  hostname="$(hostname -f 2>/dev/null || hostname)"
  arch="$(uname -m)"
  kernel="$(uname -r)"
  uptime_s="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)"
  uptime_hr="$(printf '%dd %dh %dm' \
    $(( uptime_s/86400 )) \
    $(( (uptime_s%86400)/3600 )) \
    $(( (uptime_s%3600)/60 )))"

  # OS name
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    os_name="$(. /etc/os-release && echo "${PRETTY_NAME:-$NAME}")"
  else
    os_name="$(uname -s)"
  fi

  local load1 load5 load15
  read -r load1 load5 load15 _ < /proc/loadavg

  # CPU count
  local ncpu
  ncpu="$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo)"

  kv "Hostname"    "$hostname"
  kv "OS"          "$os_name"
  kv "Kernel"      "$kernel ($arch)"
  kv "Uptime"      "$uptime_hr"
  kv "Load avg"    "${load1} / ${load5} / ${load15}  (1m / 5m / 15m)"
  kv "CPU threads" "$ncpu"

  # Date/time
  kv "Report time" "$(date '+%Y-%m-%d %H:%M:%S %Z')"

  json_add "hostname" "\"$hostname\""
  json_add "os"       "\"$os_name\""
  json_add "kernel"   "\"$kernel\""
  json_add "uptime_s" "$uptime_s"
  json_add "load_1m"  "$load1"
}

# ─────────────────────────────────────────────
# SECTION: CPU
# ─────────────────────────────────────────────
section_cpu() {
  section_enabled cpu || return 0
  section_header "CPU" "⚙"

  # CPU model
  local model
  model="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
  kv "Model" "$model"

  # Core/thread count
  local phys_cores threads sockets
  phys_cores="$(grep '^core id' /proc/cpuinfo | sort -u | wc -l)"
  threads="$(grep -c '^processor' /proc/cpuinfo)"
  sockets="$(grep '^physical id' /proc/cpuinfo | sort -u | wc -l)"
  [[ "$sockets" -eq 0 ]] && sockets=1
  kv "Topology"  "${sockets} socket(s), ${phys_cores} core(s), ${threads} thread(s)"

  # CPU frequency (if available)
  if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
    local freq_khz freq_ghz
    freq_khz="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)"
    freq_ghz="$(awk "BEGIN{printf \"%.2f\", $freq_khz/1000000}")"
    local max_khz max_ghz
    max_khz="$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || echo $freq_khz)"
    max_ghz="$(awk "BEGIN{printf \"%.2f\", $max_khz/1000000}")"
    kv "Frequency" "${freq_ghz} GHz  (max ${max_ghz} GHz)"
  fi

  # Governor
  if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
    local gov
    gov="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
    kv "Governor" "$gov"
  fi

  # CPU usage via /proc/stat (sample over 200ms)
  local cpu_pct level
  cpu_pct="$(_cpu_usage_pct)"
  level="$(threshold "$cpu_pct" 70 90)"
  printf "  %-28b %b\n" "${C_CYN}Usage (instant)${C_RESET}" "$(bar "$cpu_pct" 30 "$level")"

  # Per-core load from /proc/loadavg vs nproc
  local load1 ncpu load_pct load_level
  read -r load1 _ < /proc/loadavg
  ncpu="$(nproc)"
  load_pct="$(awk "BEGIN{p=int($load1/$ncpu*100); print (p>100?100:p)}")"
  load_level="$(threshold "$load_pct" 70 90)"
  printf "  %-28b %b\n" "${C_CYN}Normalised load${C_RESET}" "$(bar "$load_pct" 30 "$load_level")"

  # Context switches / interrupts
  if [[ -f /proc/stat ]]; then
    local ctxt intr
    ctxt="$(grep '^ctxt ' /proc/stat | awk '{print $2}')"
    intr="$(grep '^intr '  /proc/stat | awk '{print $2}')"
    kv "Ctx switches (total)" "$ctxt"
    kv "Interrupts (total)"   "$intr"
  fi

  # Virtualization
  local virt=""
  if has systemd-detect-virt; then
    virt="$(systemd-detect-virt 2>/dev/null || true)"
  elif [[ -f /proc/cpuinfo ]] && grep -qi 'hypervisor' /proc/cpuinfo; then
    virt="hypervisor (unknown)"
  fi
  [[ -n "$virt" && "$virt" != "none" ]] && kv "Virtualisation" "$(colour_level warn "$virt")" || true

  json_add "cpu_model"   "\"$model\""
  json_add "cpu_threads" "$threads"
  json_add "cpu_usage"   "$cpu_pct"
}

_cpu_usage_pct() {
  # Diff /proc/stat over 200ms
  local s1 s2
  s1="$(grep '^cpu ' /proc/stat)"
  sleep 0.2
  s2="$(grep '^cpu ' /proc/stat)"

  awk -v s1="$s1" -v s2="$s2" '
  BEGIN {
    n = split(s1, a); split(s2, b)
    idle1=a[5]+a[6]; total1=0; for(i=2;i<=n;i++) total1+=a[i]
    idle2=b[5]+b[6]; total2=0; for(i=2;i<=n;i++) total2+=b[i]
    d_idle  = idle2  - idle1
    d_total = total2 - total1
    pct = (d_total > 0) ? int((d_total - d_idle) * 100 / d_total) : 0
    print pct
  }'
}

# ─────────────────────────────────────────────
# SECTION: Memory
# ─────────────────────────────────────────────
section_memory() {
  section_enabled memory || return 0
  section_header "Memory" "💾"

  local total avail free buffers cached swap_total swap_free
  total="$(     awk '/^MemTotal:/     {print $2}' /proc/meminfo)"
  avail="$(     awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
  free="$(      awk '/^MemFree:/      {print $2}' /proc/meminfo)"
  buffers="$(   awk '/^Buffers:/      {print $2}' /proc/meminfo)"
  cached="$(    awk '/^Cached:/       {print $2}' /proc/meminfo)"
  swap_total="$(awk '/^SwapTotal:/    {print $2}' /proc/meminfo)"
  swap_free="$( awk '/^SwapFree:/     {print $2}' /proc/meminfo)"

  # Human-readable
  hr_kb() { awk "BEGIN{v=$1; if(v>=1048576) printf \"%.1f GiB\",v/1048576; else printf \"%.0f MiB\",v/1024}"; }

  local used=$(( total - avail ))
  local used_pct=$(( used * 100 / total ))
  local level
  level="$(threshold "$used_pct" 75 90)"

  kv "Total"     "$(hr_kb $total)"
  kv "Available" "$(colour_level ok "$(hr_kb $avail)")" ok
  kv "Used"      "$(hr_kb $used)"
  printf "  %-28b %b\n" "${C_CYN}Usage${C_RESET}" "$(bar "$used_pct" 30 "$level")"
  kv "Buffers"   "$(hr_kb $buffers)"
  kv "Cached"    "$(hr_kb $cached)"

  # Swap
  if [[ "$swap_total" -gt 0 ]]; then
    local swap_used=$(( swap_total - swap_free ))
    local swap_pct=$(( swap_used * 100 / swap_total ))
    local swap_level
    swap_level="$(threshold "$swap_pct" 40 70)"
    kv "Swap total" "$(hr_kb $swap_total)"
    printf "  %-28b %b\n" "${C_CYN}Swap usage${C_RESET}" "$(bar "$swap_pct" 30 "$swap_level")"
    if [[ $swap_pct -ge 40 ]]; then
      printf "  ${C_BYEL}  ⚠  Elevated swap usage may indicate memory pressure.${C_RESET}\n"
    fi
  else
    kv "Swap" "$(colour_level warn "none configured")"
  fi

  # OOM killer activity
  if has dmesg; then
    local oom_count
    oom_count="$(dmesg --notime 2>/dev/null | grep -c 'oom-killer\|Out of memory' || true)"
    if [[ "$oom_count" -gt 0 ]]; then
      kv "OOM events (boot)" "$(colour_level crit "$oom_count kills since boot")"
    else
      kv "OOM events (boot)" "$(colour_level ok "none")"
    fi
  fi

  # Huge pages
  local hp_total hp_free
  hp_total="$(awk '/^HugePages_Total:/ {print $2}' /proc/meminfo)"
  hp_free="$( awk '/^HugePages_Free:/  {print $2}' /proc/meminfo)"
  [[ "$hp_total" -gt 0 ]] && kv "Huge pages" "${hp_free}/${hp_total} free"

  json_add "mem_total_kb"  "$total"
  json_add "mem_avail_kb"  "$avail"
  json_add "mem_used_pct"  "$used_pct"
  json_add "swap_total_kb" "$swap_total"
}

# ─────────────────────────────────────────────
# SECTION: Disk
# ─────────────────────────────────────────────
section_disk() {
  section_enabled disk || return 0
  section_header "Disk Usage" "💿"

  local json_mounts="["
  local first_mount=true

  # Iterate real filesystems (skip tmpfs/devtmpfs/overlay/squashfs unless root)
  while IFS= read -r line; do
    local fs mount fstype size used avail pct_str pct
    fs="$(    echo "$line" | awk '{print $1}')"
    fstype="$(echo "$line" | awk '{print $2}')"
    size="$(  echo "$line" | awk '{print $3}')"
    used="$(  echo "$line" | awk '{print $4}')"
    avail="$( echo "$line" | awk '{print $5}')"
    pct_str="$(echo "$line" | awk '{print $6}')"
    mount="$( echo "$line" | awk '{print $7}')"

    # Skip pseudo filesystems
    case "$fstype" in
      tmpfs|devtmpfs|devfs|sysfs|proc|cgroup*|overlay|squashfs|efivarfs|securityfs|pstore)
        # Keep only root if it's an overlay (container)
        [[ "$mount" == "/" && "$fstype" == "overlay" ]] || continue ;;
    esac

    pct="${pct_str/\%/}"
    local level
    level="$(threshold "$pct" 75 90)"

    printf "  ${C_CYN}%-20s${C_RESET} %-8s %-6s used / %-6s total  %b\n" \
      "$mount" "[$fstype]" "$used" "$size" "$(bar "$pct" 20 "$level")"

    if [[ "$pct" -ge 90 ]]; then
      printf "    ${C_BRED}  ✗  CRITICAL: only %s free${C_RESET}\n" "$avail"
    elif [[ "$pct" -ge 75 ]]; then
      printf "    ${C_BYEL}  ⚠  Warning: only %s free${C_RESET}\n" "$avail"
    fi

    $first_mount || json_mounts+=","
    json_mounts+="{\"mount\":\"$mount\",\"pct\":$pct,\"avail\":\"$avail\"}"
    first_mount=false

  done < <(df -hT --output=source,fstype,size,used,avail,pcent,target 2>/dev/null | tail -n +2)

  json_mounts+="]"
  json_add "mounts" "$json_mounts"

  # inode usage — only flag if concerning
  printf "\n  ${C_DIM}Inode usage:${C_RESET}\n"
  df -i 2>/dev/null | tail -n +2 | while read -r fs inodes iused ifree ipct mount; do
    local ipct_n="${ipct/\%/}"
    if [[ "$ipct_n" =~ ^[0-9]+$ ]] && (( ipct_n >= 70 )); then
      local ilevel
      ilevel="$(threshold "$ipct_n" 70 90)"
      printf "    %-20s inodes %s used  %b\n" \
        "$mount" "$ipct" "$(bar "$ipct_n" 15 "$ilevel")"
    fi
  done || true

  # Top 5 disk consumers in /home and /var (if accessible)
  for scan_dir in /home /var /tmp; do
    [[ -d "$scan_dir" ]] || continue
    printf "\n  ${C_DIM}Top consumers in %s:${C_RESET}\n" "$scan_dir"
    du -sh "${scan_dir}"/* 2>/dev/null | sort -hr | head -5 | \
      awk '{printf "    %s  %s\n", $1, $2}' || true
  done
}

# ─────────────────────────────────────────────
# SECTION: Temperatures
# ─────────────────────────────────────────────
section_temps() {
  section_enabled temps || return 0
  section_header "Temperatures" "🌡"

  local found_any=false

  # --- sensors (lm-sensors) ---
  if has sensors; then
    found_any=true
    printf "  ${C_DIM}(via lm-sensors)${C_RESET}\n"
    sensors 2>/dev/null | while IFS= read -r line; do
      local temp_c level colour
      if [[ "$line" =~ ([0-9]+\.[0-9]+)°C ]]; then
        temp_c="${BASH_REMATCH[1]%%.*}"
        level="$(threshold "$temp_c" 70 85)"
        case "$level" in
          ok)   colour="$C_BGRN" ;;
          warn) colour="$C_BYEL" ;;
          crit) colour="$C_BRED" ;;
        esac
        printf "  ${colour}%s${C_RESET}\n" "$line"
      else
        printf "  ${C_DIM}%s${C_RESET}\n" "$line"
      fi
    done
  fi

  # --- /sys thermal zones ---
  if ls /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1 | grep -q .; then
    found_any=true
    printf "\n  ${C_DIM}(via /sys thermal zones)${C_RESET}\n"
    for f in /sys/class/thermal/thermal_zone*/temp; do
      local zone_dir zone_type temp_raw temp_c level
      zone_dir="$(dirname "$f")"
      zone_type="$(cat "${zone_dir}/type" 2>/dev/null || echo "unknown")"
      temp_raw="$(cat "$f" 2>/dev/null || echo 0)"
      temp_c=$(( temp_raw / 1000 ))
      level="$(threshold "$temp_c" 70 85)"
      printf "  %-30s %b\n" "$zone_type" "$(colour_level "$level" "${temp_c}°C")"
    done
  fi

  # --- hwmon (direct kernel hwmon) ---
  if ls /sys/class/hwmon/hwmon*/temp*_input 2>/dev/null | head -1 | grep -q .; then
    found_any=true
    printf "\n  ${C_DIM}(via hwmon)${C_RESET}\n"
    for f in /sys/class/hwmon/hwmon*/temp*_input; do
      local hwmon_dir label temp_c level
      hwmon_dir="$(dirname "$f")"
      local fname="${f##*/}"
      local lfile="${hwmon_dir}/${fname/_input/_label}"
      label="$(cat "$lfile" 2>/dev/null || basename "$hwmon_dir")/${fname/_input/}"
      temp_raw="$(cat "$f" 2>/dev/null || echo 0)"
      temp_c=$(( temp_raw / 1000 ))
      [[ "$temp_c" -gt 0 ]] || continue
      level="$(threshold "$temp_c" 70 85)"
      printf "  %-30s %b\n" "$label" "$(colour_level "$level" "${temp_c}°C")"
    done
  fi

  $found_any || printf "  ${C_DIM}No temperature sensors found (try: sudo apt install lm-sensors && sensors-detect)${C_RESET}\n"
}

# ─────────────────────────────────────────────
# SECTION: SMART Disk Health
# ─────────────────────────────────────────────
section_smart() {
  section_enabled smart || return 0
  section_header "Disk Health (SMART)" "🔍"

  if ! has smartctl; then
    printf "  ${C_DIM}smartctl not found. Install: sudo apt install smartmontools${C_RESET}\n"
    return 0
  fi

  # Find block devices (non-partition)
  local devices=()
  while IFS= read -r dev; do
    devices+=("$dev")
  done < <(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1}')

  if [[ ${#devices[@]} -eq 0 ]]; then
    printf "  ${C_DIM}No block devices found.${C_RESET}\n"
    return 0
  fi

  for dev in "${devices[@]}"; do
    printf "\n  ${C_BOLD}${C_WHT}%s${C_RESET}\n" "$dev"

    local smart_out
    if ! smart_out="$(sudo smartctl -H -A -i "$dev" 2>&1)"; then
      printf "    ${C_DIM}Could not read SMART data (needs root or device not supported)${C_RESET}\n"
      continue
    fi

    # Overall health
    local health
    health="$(echo "$smart_out" | grep -i 'SMART overall-health' | awk -F: '{print $2}' | tr -d ' ')"
    if [[ "$health" == "PASSED" ]]; then
      kv "  Overall health" "$(colour_level ok "PASSED ✓")"
    elif [[ -n "$health" ]]; then
      kv "  Overall health" "$(colour_level crit "$health ✗")"
    fi

    # Device info
    local model fw serial
    model="$(echo "$smart_out"  | grep '^Device Model'   | head -1 | cut -d: -f2 | sed 's/^ *//')"
    fw="$(   echo "$smart_out"  | grep '^Firmware'        | head -1 | cut -d: -f2 | sed 's/^ *//')"
    serial="$(echo "$smart_out" | grep '^Serial Number'   | head -1 | cut -d: -f2 | sed 's/^ *//')"
    [[ -n "$model"  ]] && kv "  Model"           "$model"
    [[ -n "$fw"     ]] && kv "  Firmware"         "$fw"
    [[ -n "$serial" ]] && kv "  Serial"           "$serial"

    # Key SMART attributes
    declare -A ATTR_NAMES=(
      [5]="Reallocated Sectors"
      [9]="Power On Hours"
      [187]="Uncorrectable Errors"
      [188]="Command Timeout"
      [190]="Airflow Temp"
      [194]="Temperature"
      [197]="Pending Sectors"
      [198]="Offline Uncorrectable"
      [199]="UDMA CRC Errors"
    )
    while IFS= read -r attr_line; do
      local id name val raw
      id="$(echo "$attr_line" | awk '{print $1}')"
      val="$(echo "$attr_line" | awk '{print $4}')"
      raw="$(echo "$attr_line" | awk '{print $NF}')"
      name="${ATTR_NAMES[$id]:-}"
      [[ -z "$name" ]] && continue

      # Flag concerning values
      local a_level="ok"
      case "$id" in
        5|187|197|198)
          [[ "$raw" -gt 0 ]] && a_level="crit" || a_level="ok" ;;
        194|190)
          [[ "$raw" -gt 60 ]] && a_level="warn"
          [[ "$raw" -gt 75 ]] && a_level="crit" ;;
      esac

      printf "  %-30s %b\n" \
        "  ${C_CYN}${name}${C_RESET}" \
        "$(colour_level "$a_level" "val=${val}, raw=${raw}")"
    done < <(echo "$smart_out" | awk 'NR>5 && /^[[:space:]]*[0-9]/{print}')

    # NVMe support
    if echo "$smart_out" | grep -qi 'NVMe'; then
      local nvme_out
      nvme_out="$(sudo smartctl -A "$dev" 2>/dev/null || true)"
      local media_errors crit_warn
      media_errors="$(echo "$nvme_out" | grep 'Media and Data Integrity Errors' | awk '{print $NF}')"
      crit_warn="$(   echo "$nvme_out" | grep 'Critical Warning'                | awk '{print $NF}')"
      [[ -n "$media_errors" ]] && kv "  NVMe Media Errors"   "$(colour_level "${media_errors:-0}" "crit" "$media_errors")"
      [[ -n "$crit_warn"    ]] && kv "  NVMe Critical Warn"  \
        "$(colour_level "$([ "$crit_warn" = "0x00" ] && echo ok || echo crit)" "$crit_warn")"
    fi
  done
}

# ─────────────────────────────────────────────
# SECTION: Network
# ─────────────────────────────────────────────
section_network() {
  section_enabled network || return 0
  section_header "Network" "🌐"

  # Interface table
  printf "  ${C_DIM}%-16s %-8s %-20s %-20s %-10s %-10s${C_RESET}\n" \
    "Interface" "State" "IPv4" "IPv6" "RX" "TX"

  local json_ifaces="["
  local first_if=true

  while IFS= read -r line; do
    local iface state ipv4 ipv6 rx_b tx_b rx_h tx_h
    iface="$(echo "$line" | awk '{print $1}' | tr -d :)"
    [[ "$iface" =~ ^(lo|docker[0-9]|veth|br-|virbr) ]] && continue

    # State
    state="$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null || echo "unknown")"

    # IPs
    ipv4="$(ip -4 addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1 || echo "")"
    ipv6="$(ip -6 addr show "$iface" 2>/dev/null | grep 'inet6' | grep -v 'fe80' | awk '{print $2}' | head -1 || echo "")"

    # Traffic counters (bytes)
    rx_b="$(cat "/sys/class/net/${iface}/statistics/rx_bytes" 2>/dev/null || echo 0)"
    tx_b="$(cat "/sys/class/net/${iface}/statistics/tx_bytes" 2>/dev/null || echo 0)"
    rx_h="$(awk "BEGIN{v=$rx_b; if(v>1073741824) printf \"%.1fG\",v/1073741824; else if(v>1048576) printf \"%.1fM\",v/1048576; else printf \"%.0fK\",v/1024}")"
    tx_h="$(awk "BEGIN{v=$tx_b; if(v>1073741824) printf \"%.1fG\",v/1073741824; else if(v>1048576) printf \"%.1fM\",v/1048576; else printf \"%.0fK\",v/1024}")"

    local state_col
    case "$state" in
      up)      state_col="$(colour_level ok "$state")" ;;
      down)    state_col="$(colour_level crit "$state")" ;;
      *)       state_col="$(colour_level warn "$state")" ;;
    esac

    printf "  %-16s %-18b %-20s %-20s %-10s %-10s\n" \
      "$iface" "$state_col" "${ipv4:--}" "${ipv6:--}" "$rx_h" "$tx_h"

    $first_if || json_ifaces+=","
    json_ifaces+="{\"iface\":\"$iface\",\"state\":\"$state\",\"ipv4\":\"${ipv4:-}\",\"tx_bytes\":$tx_b,\"rx_bytes\":$rx_b}"
    first_if=false

  done < <(ip link show 2>/dev/null | awk '/^[0-9]+:/{print}')

  json_ifaces+="]"
  json_add "interfaces" "$json_ifaces"

  # DNS
  printf "\n"
  local dns_servers
  dns_servers="$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | tr '\n' ' ')"
  kv "DNS servers" "${dns_servers:-(none found)}"

  # Default gateway
  local gw
  gw="$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)"
  kv "Default gateway" "${gw:-(none)}"

  # Connectivity probe
  printf "\n  ${C_DIM}Connectivity:${C_RESET}\n"
  local probe_hosts=("8.8.8.8" "1.1.1.1")
  for host in "${probe_hosts[@]}"; do
    if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
      printf "  %-28s %b\n" "  ping $host" "$(colour_level ok "reachable")"
    else
      printf "  %-28s %b\n" "  ping $host" "$(colour_level warn "unreachable")"
    fi
  done

  # Open listening ports (requires ss or netstat)
  printf "\n  ${C_DIM}Listening ports (IPv4/6):${C_RESET}\n"
  if has ss; then
    ss -tlnp 2>/dev/null | awk 'NR>1 && /LISTEN/{printf "    %-30s %s\n", $4, $NF}' | head -20
  elif has netstat; then
    netstat -tlnp 2>/dev/null | awk 'NR>2 && /LISTEN/{printf "    %-30s %s\n", $4, $NF}' | head -20
  else
    printf "    ${C_DIM}(install iproute2 or net-tools for port listing)${C_RESET}\n"
  fi

  # Active established connections count
  local conn_count
  conn_count="$(ss -tn state established 2>/dev/null | tail -n +2 | wc -l || echo "?")"
  printf "\n"
  kv "Established connections" "$conn_count"
}

# ─────────────────────────────────────────────
# SECTION: Systemd Services
# ─────────────────────────────────────────────
section_services() {
  section_enabled services || return 0
  section_header "Systemd Services" "⚡"

  if ! has systemctl; then
    printf "  ${C_DIM}systemd not available${C_RESET}\n"
    return 0
  fi

  # Failed units
  local failed_units
  failed_units="$(systemctl --failed --no-pager --no-legend 2>/dev/null | grep -v '^$' || true)"

  if [[ -z "$failed_units" ]]; then
    kv "Failed units" "$(colour_level ok "none ✓")"
  else
    kv "Failed units" "$(colour_level crit "$(echo "$failed_units" | wc -l) FAILED ✗")"
    echo "$failed_units" | while IFS= read -r unit; do
      printf "    ${C_BRED}%s${C_RESET}\n" "$unit"
    done
  fi

  # Service counts
  local active_count inactive_count
  active_count="$(systemctl list-units --type=service --state=active --no-legend 2>/dev/null | wc -l)"
  inactive_count="$(systemctl list-units --type=service --state=inactive --no-legend 2>/dev/null | wc -l)"
  kv "Active services"   "$active_count"
  kv "Inactive services" "$inactive_count"

  # Last 5 boot-time failures from journal
  if has journalctl; then
    printf "\n  ${C_DIM}Recent error/critical journal entries:${C_RESET}\n"
    journalctl -p err..crit --no-pager --no-hostname -n 10 --output=short-iso 2>/dev/null \
      | head -12 \
      | while IFS= read -r jline; do
          printf "  ${C_RED}%s${C_RESET}\n" "$jline"
        done || true
  fi

  # systemd-analyze blame (top 5 slowest units)
  if has systemd-analyze; then
    printf "\n  ${C_DIM}Top 5 slowest boot units:${C_RESET}\n"
    systemd-analyze blame 2>/dev/null | head -5 | \
      awk '{printf "    %-12s %s\n", $1, $2}' || true
  fi

  json_add "failed_services" "$(echo "$failed_units" | wc -l)"
}

# ─────────────────────────────────────────────
# SECTION: Top Processes
# ─────────────────────────────────────────────
section_processes() {
  section_enabled processes || return 0
  section_header "Top Processes" "📊"

  # Top 8 by CPU
  printf "  ${C_DIM}By CPU:${C_RESET}\n"
  printf "  ${C_DIM}%-7s %-8s %-6s %-6s %s${C_RESET}\n" "PID" "USER" "%CPU" "%MEM" "COMMAND"
  ps aux --sort=-%cpu 2>/dev/null | awk 'NR>1 && NR<=9 {printf "  %-7s %-8s %-6s %-6s %s\n", $1, $2, $3, $4, $11}' || true

  # Top 8 by MEM
  printf "\n  ${C_DIM}By Memory:${C_RESET}\n"
  printf "  ${C_DIM}%-7s %-8s %-6s %-6s %s${C_RESET}\n" "PID" "USER" "%CPU" "%MEM" "COMMAND"
  ps aux --sort=-%mem 2>/dev/null | awk 'NR>1 && NR<=9 {printf "  %-7s %-8s %-6s %-6s %s\n", $1, $2, $3, $4, $11}' || true

  # Total process count
  local total_procs
  total_procs="$(ps aux 2>/dev/null | tail -n +2 | wc -l)"
  printf "\n"
  kv "Total processes" "$total_procs"

  # Zombie count
  local zombies
  zombies="$(ps aux 2>/dev/null | awk '$8 ~ /^Z/ {count++} END {print count+0}')"
  if [[ "$zombies" -gt 0 ]]; then
    kv "Zombie processes" "$(colour_level warn "$zombies")"
  else
    kv "Zombie processes" "$(colour_level ok "0")"
  fi
}

# ─────────────────────────────────────────────
# SECTION: Security Snapshot
# ─────────────────────────────────────────────
section_security() {
  section_enabled security || return 0
  section_header "Security Snapshot" "🔒"

  # Last 5 failed SSH logins
  printf "  ${C_DIM}Recent failed SSH logins:${C_RESET}\n"
  if [[ -r /var/log/auth.log ]]; then
    grep -i 'failed\|invalid' /var/log/auth.log 2>/dev/null | tail -5 | \
      awk '{printf "  %s\n", $0}' || true
  elif has journalctl; then
    journalctl _COMM=sshd --no-pager --no-hostname -n 5 2>/dev/null | \
      grep -i 'failed\|invalid' | \
      awk '{printf "  %s\n", $0}' || true
  else
    printf "    ${C_DIM}(unable to read auth log)${C_RESET}\n"
  fi

  # Users with UID 0 (root equiv)
  printf "\n  ${C_DIM}UID 0 accounts:${C_RESET}\n"
  local root_users
  root_users="$(awk -F: '$3==0{print $1}' /etc/passwd)"
  echo "$root_users" | while IFS= read -r u; do
    [[ -z "$u" ]] && continue
    if [[ "$u" != "root" ]]; then
      printf "    ${C_BRED}⚠  %s has UID 0 (investigate!)${C_RESET}\n" "$u"
    else
      printf "    ${C_BGRN}✓  %s${C_RESET}\n" "$u"
    fi
  done

  # Passwordless sudo entries
  printf "\n  ${C_DIM}NOPASSWD sudo entries:${C_RESET}\n"
  grep -r 'NOPASSWD' /etc/sudoers /etc/sudoers.d/ 2>/dev/null | \
    grep -v '^#' | head -5 | \
    awk '{printf "    \033[93m%s\033[0m\n", $0}' || \
    printf "    ${C_BGRN}none found${C_RESET}\n"

  # World-writable directories (quick scan of key paths)
  printf "\n  ${C_DIM}World-writable dirs (key paths, non-sticky):${C_RESET}\n"
  local ww_count=0
  while IFS= read -r ww; do
    printf "    ${C_BYEL}%s${C_RESET}\n" "$ww"
    (( ww_count++ )) || true
  done < <(find /etc /usr /bin /sbin -maxdepth 2 -type d \
    -perm -o+w ! -perm -1000 2>/dev/null | head -10)
  [[ "$ww_count" -eq 0 ]] && printf "    ${C_BGRN}none found${C_RESET}\n"

  # SSH root login check
  printf "\n"
  if [[ -r /etc/ssh/sshd_config ]]; then
    local permit_root
    permit_root="$(grep -i '^PermitRootLogin' /etc/ssh/sshd_config | awk '{print $2}' | head -1)"
    case "${permit_root,,}" in
      no|prohibit-password|without-password)
        kv "SSH PermitRootLogin" "$(colour_level ok "${permit_root:-no}")" ;;
      yes)
        kv "SSH PermitRootLogin" "$(colour_level crit "yes ← RISKY")" ;;
      *)
        kv "SSH PermitRootLogin" "$(colour_level warn "not set (default may vary)")" ;;
    esac
  fi

  # UFW / firewalld / iptables status
  if has ufw; then
    local ufw_status
    ufw_status="$(sudo ufw status 2>/dev/null | head -1 | awk '{print $NF}')"
    kv "UFW firewall" "$(colour_level "$([ "$ufw_status" = "active" ] && echo ok || echo warn)" "${ufw_status:-unknown}")"
  elif has firewall-cmd; then
    local fw_state
    fw_state="$(sudo firewall-cmd --state 2>/dev/null || echo "unknown")"
    kv "firewalld" "$(colour_level "$([ "$fw_state" = "running" ] && echo ok || echo warn)" "$fw_state")"
  elif has iptables; then
    local ipt_rules
    ipt_rules="$(sudo iptables -L --line-numbers 2>/dev/null | grep -vc '^$' || echo 0)"
    kv "iptables rules" "$ipt_rules lines"
  fi

  # Auto-updates
  if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
    local autoup
    autoup="$(grep 'Unattended-Upgrade' /etc/apt/apt.conf.d/20auto-upgrades | head -1 | grep -o '"[0-9]*"' | tr -d '"')"
    if [[ "$autoup" == "1" ]]; then
      kv "Unattended upgrades" "$(colour_level ok "enabled")"
    else
      kv "Unattended upgrades" "$(colour_level warn "disabled")"
    fi
  fi
}

# ─────────────────────────────────────────────
# SECTION: Updates Available
# ─────────────────────────────────────────────
section_updates() {
  section_enabled updates || return 0
  section_header "Pending Updates" "📦"

  if has apt-get; then
    local count
    count="$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst ' || echo 0)"
    local sec_count
    sec_count="$(apt-get -s upgrade 2>/dev/null | grep '^Inst.*security' | wc -l || echo 0)"
    if [[ "$count" -gt 0 ]]; then
      kv "APT upgradable" "$(colour_level warn "$count packages")"
      [[ "$sec_count" -gt 0 ]] && kv "  Security updates" "$(colour_level crit "$sec_count critical")"
    else
      kv "APT upgradable" "$(colour_level ok "up to date")"
    fi
  elif has dnf; then
    local dnf_count
    dnf_count="$(dnf check-update --quiet 2>/dev/null | grep -vc '^$' || echo "?")"
    kv "DNF updates" "$dnf_count pending"
  elif has pacman; then
    if has checkupdates; then
      local pac_count
      pac_count="$(checkupdates 2>/dev/null | wc -l || echo "?")"
      kv "Pacman updates" "$pac_count pending"
    fi
  fi
}

# ─────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────
print_banner() {
  printf "${C_BBLU}"
  cat <<'BANNER'
  ███████╗██╗   ██╗███████╗ ██████╗██╗  ██╗███████╗ ██████╗██╗  ██╗
  ██╔════╝╚██╗ ██╔╝██╔════╝██╔════╝██║  ██║██╔════╝██╔════╝██║ ██╔╝
  ███████╗ ╚████╔╝ ███████╗██║     ███████║█████╗  ██║     █████╔╝
  ╚════██║  ╚██╔╝  ╚════██║██║     ██╔══██║██╔══╝  ██║     ██╔═██╗
  ███████║   ██║   ███████║╚██████╗██║  ██║███████╗╚██████╗██║  ██╗
  ╚══════╝   ╚═╝   ╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝
BANNER
  printf "${C_RESET}"
  printf "  ${C_DIM}System Health Check  v%s   |   %s${C_RESET}\n\n" \
    "$VERSION" "$(date '+%Y-%m-%d %H:%M:%S')"
}

# ─────────────────────────────────────────────
# MAIN RUN
# ─────────────────────────────────────────────
run_all_sections() {
  $OPT_JSON || print_banner

  section_overview
  section_cpu
  section_memory
  section_disk
  section_temps
  section_smart
  section_network
  section_services
  section_processes
  section_security
  section_updates

  if $OPT_JSON; then
    json_dump
    return
  fi

  # Footer
  local line
  line="$(printf '─%.0s' {1..60})"
  printf "\n${C_BBLU}%s${C_RESET}\n" "$line"
  printf "  ${C_DIM}Report complete. Run with ${C_RESET}${C_BOLD}--help${C_RESET}${C_DIM} to see available options.${C_RESET}\n"
  printf "${C_BBLU}%s${C_RESET}\n\n" "$line"
}

# Output-to-file wrapper
if [[ -n "$OPT_OUTPUT" ]]; then
  # Strip ANSI for file output
  run_all_sections | tee >(sed 's/\x1b\[[0-9;]*m//g' > "$OPT_OUTPUT")
  printf "\n${C_DIM}Report saved to: %s${C_RESET}\n" "$OPT_OUTPUT"
elif [[ "$OPT_WATCH" -gt 0 ]]; then
  while true; do
    clear
    run_all_sections
    printf "  ${C_DIM}Refreshing in %ds … (Ctrl-C to stop)${C_RESET}\n" "$OPT_WATCH"
    sleep "$OPT_WATCH"
  done
else
  run_all_sections
fi
