#!/usr/bin/env bash

# ==============================================================================
# HashForge - A Powerful High-Performance Password Recovery Tool
# Version: 3.0 Pro (Optimized Edition)
# Creator: Prof_MAN
# Website: pm9.s.gy
# ==============================================================================

set -o pipefail

# ANSI Color and style definitions
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# File handles and configuration
OUT=$(mktemp)
AUTOCOMPLETE_LIST=$(mktemp)
STRUCTURAL_LIST=$(mktemp)
HASH_PID=""
WORDLIST_DIR="${HOME}/.hashforge/wordlists"
ROCKYOU_PATH="${WORDLIST_DIR}/rockyou.txt"
ROCKYOU_URL="https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt"

# Default configuration values
CLI_HASH=""
CLI_PARTIAL=""
CLI_WORDLIST=""
CLI_MODE=""
CLI_ATTACK=""
CLI_CHARSET="a"
CLI_WORKLOAD="3"
CLI_OUTPUT=""
CLI_RULE=""
CLI_FORCE=false
CLI_BENCHMARK=false
CLI_OPTIMIZED=true
CLI_POTFILE=true
CLI_AUTOCOMPLETE=true
CLI_STRUCTURAL=false

# Cleanup handler for exit and signals
cleanup() {
    # Restore cursor
    tput cnorm 2>/dev/null || printf "\033[?25h"
    if [[ -n "$HASH_PID" ]] && kill -0 "$HASH_PID" 2>/dev/null; then
        kill -9 "$HASH_PID" 2>/dev/null
    fi
    rm -f "$OUT" "$AUTOCOMPLETE_LIST" "$STRUCTURAL_LIST"
}
trap cleanup EXIT INT TERM

# Formatted printing helper
cecho() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Display ASCII Banner
show_banner() {
    echo -e "${CYAN}=================================================================${NC}"
    echo -e "${GREEN}    __  __           __    ______                              ${NC}"
    echo -e "${GREEN}   / / / /___ ______/ /_  / ____/___  _________ ____           ${NC}"
    echo -e "${GREEN}  / /_/ / __ `/ ___/ __ \/ /_  / __ \/ ___/ __ `/ _ \          ${NC}"
    echo -e "${GREEN} / __  / /_/ (__  ) / / / __/ / /_/ / /  / /_/ /  __/          ${NC}"
    echo -e "${GREEN}/_/ /_/\__,_/____/_/ /_/_/    \____/_/   \__, /\___/           ${NC}"
    echo -e "${GREEN}                                        /____/                 ${NC}"
    echo -e "${CYAN}=================================================================${NC}"
    echo -e "${BOLD} HashForge – High-Performance Password Recovery Tool${NC}"
    echo -e " Version  : ${YELLOW}3.0 Pro${NC}"
    echo -e " Creator  : ${YELLOW}Prof_MAN${NC}"
    echo -e " Website  : ${YELLOW}pm9.s.gy${NC}"
    echo -e "${CYAN}=================================================================${NC}"
    echo ""
}

# Display CLI Help / Usage
show_help() {
    show_banner
    echo -e "${BOLD}USAGE:${NC}"
    echo -e "  hashforge.sh [OPTIONS]\n"
    echo -e "${BOLD}OPTIONS:${NC}"
    echo -e "  ${GREEN}-h, --hash <HASH>${NC}         Target hash string to crack"
    echo -e "  ${GREEN}-p, --partial <PATTERN>${NC}   Partial password pattern ('*' for wildcards, e.g. 'adm*n', '1P***!')"
    echo -e "  ${GREEN}-w, --wordlist <PATH>${NC}     Wordlist file path (defaults to rockyou.txt)"
    echo -e "  ${GREEN}-m, --mode <MODE>${NC}         Hashcat hash type (0=MD5, 100=SHA1, 1000=NTLM, 1400=SHA256, 1700=SHA512)"
    echo -e "  ${GREEN}-a, --attack <MODE>${NC}       Attack mode: 0 (Dictionary), 3 (Mask), 6 (Hybrid Wordlist+Mask)"
    echo -e "  ${GREEN}-c, --charset <TYPE>${NC}      Charset for mask: a (all), l (lower), u (upper), d (digits), s (special), al (alphanumeric), or custom"
    echo -e "  ${GREEN}-W, --workload <1-4>${NC}      Hashcat workload profile (1=Low, 2=Default, 3=Performance, 4=Nightmare)"
    echo -e "  ${GREEN}-r, --rule <FILE>${NC}         Apply Hashcat rule file (e.g. best64.rule)"
    echo -e "  ${GREEN}-O, --optimized${NC}           Enable optimized OpenCL/CUDA kernels (-O) [Default: Enabled]"
    echo -e "  ${GREEN}--no-optimized${NC}            Disable kernel optimizations"
    echo -e "  ${GREEN}--no-potfile${NC}              Disable reading/writing Hashcat potfile"
    echo -e "  ${GREEN}--no-autocomplete${NC}         Skip dictionary pattern autocomplete"
    echo -e "  ${GREEN}-s, --structural${NC}          Force structural format attack (Digit + Uppercase + Word + Punctuation)"
    echo -e "  ${GREEN}-o, --output <FILE>${NC}       Save recovered password and details to file"
    echo -e "  ${GREEN}-f, --force${NC}               Force Hashcat execution (--force)"
    echo -e "  ${GREEN}-b, --benchmark${NC}           Run hardware hashcat benchmark"
    echo -e "  ${GREEN}--help${NC}                    Display this help message and exit"
    echo -e "  ${GREEN}-v, --version${NC}             Show version information\n"
    echo -e "${BOLD}SPEED OPTIMIZATIONS & FEATURES:${NC}"
    echo -e "  ${DIM}• Dictionary Pattern Autocomplete: Automatically resolves partial words (e.g. 'pass***' -> passwords) from rockyou.txt.${NC}"
    echo -e "  ${DIM}• Structural Pattern Detection: Detects formats like [Digit][Upper][Word][Punctuation] (e.g. 1Password!) for instant cracking.${NC}"
    echo -e "  ${DIM}• Kernel Optimization (-O): Up to 200% faster hash throughput.${NC}"
    echo -e "  ${DIM}• High-efficiency async telemetry dashboard with minimal CPU overhead.${NC}\n"
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo -e "  ${DIM}# Interactive mode:${NC}"
    echo -e "  ./hashforge.sh"
    echo -e "  ${DIM}# Dictionary autocomplete attack on partial password:${NC}"
    echo -e "  ./hashforge.sh -h 5d41402abc4b2a76b9719d911017c592 -p 'hel*o'"
    echo -e "  ${DIM}# Structural format pattern (Digit + Upper + Word + Punctuation):${NC}"
    echo -e "  ./hashforge.sh -h 5d41402abc4b2a76b9719d911017c592 -p '1A*****!' -s"
    echo -e "  ${DIM}# Mask attack on MD5 with specific digit charset:${NC}"
    echo -e "  ./hashforge.sh -h 5d41402abc4b2a76b9719d911017c592 -p 'admin***' -c d"
    echo ""
}

# Auto-detect hashcat mode based on hash length
detect_hash_mode() {
    local h="$1"
    local len=${#h}
    case "$len" in
        32)  echo "0" ;;     # MD5 (0) or NTLM (1000)
        40)  echo "100" ;;   # SHA1
        64)  echo "1400" ;;  # SHA256
        96)  echo "10800" ;; # SHA384
        128) echo "1700" ;;  # SHA512
        *)   echo "0" ;;     # Default to MD5
    esac
}

# Ensure Hashcat and necessary utilities are installed
ensure_dependencies() {
    local missing_pkgs=()
    command -v hashcat &>/dev/null || missing_pkgs+=("hashcat")
    command -v curl &>/dev/null || command -v wget &>/dev/null || missing_pkgs+=("curl")
    command -v gzip &>/dev/null || missing_pkgs+=("gzip")

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        cecho "$YELLOW" "[*] Installing missing dependencies: ${missing_pkgs[*]}..."
        if command -v sudo &>/dev/null; then
            sudo DEBIAN_FRONTEND=noninteractive apt update -y && sudo DEBIAN_FRONTEND=noninteractive apt install -y "${missing_pkgs[@]}"
        else
            DEBIAN_FRONTEND=noninteractive apt update -y && DEBIAN_FRONTEND=noninteractive apt install -y "${missing_pkgs[@]}"
        fi
    fi
}

# Ensure rockyou.txt wordlist is available
ensure_rockyou() {
    # 1. Check common system paths
    if [[ -f "/usr/share/wordlists/rockyou.txt" ]]; then
        ROCKYOU_PATH="/usr/share/wordlists/rockyou.txt"
        return 0
    elif [[ -f "/usr/share/wordlists/rockyou.txt.gz" ]]; then
        cecho "$YELLOW" "[*] Decompressing /usr/share/wordlists/rockyou.txt.gz..."
        if command -v sudo &>/dev/null; then
            sudo gzip -d -k /usr/share/wordlists/rockyou.txt.gz 2>/dev/null
        else
            gzip -d -k /usr/share/wordlists/rockyou.txt.gz 2>/dev/null
        fi
        if [[ -f "/usr/share/wordlists/rockyou.txt" ]]; then
            ROCKYOU_PATH="/usr/share/wordlists/rockyou.txt"
            return 0
        fi
    fi

    # 2. Check local cache directory
    if [[ -f "$ROCKYOU_PATH" && -s "$ROCKYOU_PATH" ]]; then
        return 0
    fi

    # 3. Download rockyou.txt
    mkdir -p "$WORDLIST_DIR"
    cecho "$CYAN" "[*] Downloading rockyou.txt wordlist (default wordlist)..."
    if command -v curl &>/dev/null; then
        curl -L --progress-bar "$ROCKYOU_URL" -o "$ROCKYOU_PATH"
    elif command -v wget &>/dev/null; then
        wget --show-progress -q -O "$ROCKYOU_PATH" "$ROCKYOU_URL"
    fi

    if [[ -f "$ROCKYOU_PATH" && -s "$ROCKYOU_PATH" ]]; then
        cecho "$GREEN" "[+] rockyou.txt ready: ${ROCKYOU_PATH}"
    else
        cecho "$RED" "[!] Warning: Failed to download rockyou.txt automatically."
    fi
}

# Hardware profiling and optimization
hardware_profile() {
    cecho "$CYAN" "[*] Detecting compute hardware & OpenCL/CUDA backend..."
    local dev_info
    dev_info=$(hashcat -I 2>/dev/null | grep -E "Device Name|Device Type" | head -n 4)
    if [[ -n "$dev_info" ]]; then
        echo -e "${DIM}${dev_info}${NC}"
    else
        echo -e "${DIM}Default CPU/OpenCL environment${NC}"
    fi
}

# ==============================================================================
# SMART ACCELERATION: Dictionary Autocomplete & Structural Detection
# ==============================================================================

# Check if pattern matches the structural password standard:
# e.g., 1st char digit, 2nd char uppercase, middle word/wildcards, last char punctuation
# Example patterns: "1A*****!", "3Badmin#", "9P***?", "1A*!"
detect_structural_pattern() {
    local pat="$1"
    if [[ ${#pat} -ge 4 ]]; then
        local first_char="${pat:0:1}"
        local second_char="${pat:1:1}"
        local last_char="${pat: -1}"

        local is_digit=false
        local is_upper=false
        local is_punct=false

        [[ "$first_char" =~ [0-9] || "$first_char" == "*" ]] && is_digit=true
        [[ "$second_char" =~ [A-Z] || "$second_char" == "*" ]] && is_upper=true
        [[ "$last_char" =~ [^a-zA-Z0-9] ]] && is_punct=true

        if [[ "$is_digit" == true && "$is_upper" == true && "$is_punct" == true ]]; then
            return 0
        fi
    fi
    return 1
}

# Build structural dictionary candidates based on [Digit][Upper][Word][Punctuation]
generate_structural_wordlist() {
    local pat="$1"
    local base_wordlist="$2"
    local out_file="$3"

    cecho "$CYAN" "[*] Structural password pattern detected ([Digit][Uppercase][Word][Punctuation])."
    cecho "$YELLOW" "[*] Building targeted structural dictionary..."

    local first_char="${pat:0:1}"
    local second_char="${pat:1:1}"
    local last_char="${pat: -1}"
    local middle_part="${pat:2:${#pat}-3}"

    # Extract middle candidate words from wordlist
    local regex_middle
    regex_middle=$(echo "$middle_part" | sed 's/\*/./g')
    
    local d_list=()
    if [[ "$first_char" == "*" ]]; then
        d_list=(0 1 2 3 4 5 6 7 8 9)
    else
        d_list=("$first_char")
    fi

    local u_list=()
    if [[ "$second_char" == "*" ]]; then
        u_list=({A..Z})
    else
        u_list=("$second_char")
    fi

    local p_list=()
    if [[ "$last_char" == "*" ]]; then
        p_list=('!' '@' '#' '$' '%' '^' '&' '*' '(' ')' '?' '-' '_' '+' '=')
    else
        p_list=("$last_char")
    fi

    # Find middle words from wordlist
    local mid_file
    mid_file=$(mktemp)
    
    if [[ -f "$base_wordlist" && -n "$regex_middle" ]]; then
        grep -E -i "^${regex_middle}$" "$base_wordlist" 2>/dev/null | head -n 5000 > "$mid_file"
    fi

    # If no exact length matches, use common base words
    if [[ ! -s "$mid_file" && -f "$base_wordlist" ]]; then
        head -n 2000 "$base_wordlist" > "$mid_file"
    fi

    # Synthesize candidates
    : > "$out_file"
    while IFS= read -r mid; do
        [[ -z "$mid" ]] && continue
        for d in "${d_list[@]}"; do
            for u in "${u_list[@]}"; do
                for p in "${p_list[@]}"; do
                    echo "${d}${u}${mid}${p}" >> "$out_file"
                done
            done
        done
    done < "$mid_file"

    rm -f "$mid_file"
    local count
    count=$(wc -l < "$out_file" 2>/dev/null || echo 0)
    cecho "$GREEN" "[+] Generated ${count} structural candidate passwords."
}

# Autocomplete incomplete word patterns from dictionary (e.g. "pass***" or "adm*n")
generate_autocomplete_wordlist() {
    local pat="$1"
    local base_wordlist="$2"
    local out_file="$3"

    local regex_pat
    # Convert wildcards '*' to '.'
    regex_pat=$(echo "$pat" | sed 's/\*/./g')

    cecho "$CYAN" "[*] Searching dictionary for words matching pattern: ${YELLOW}^${regex_pat}\$${NC}"
    
    if [[ -f "$base_wordlist" ]]; then
        # Use LC_ALL=C for fastest grep speed
        LC_ALL=C grep -E -i "^${regex_pat}$" "$base_wordlist" 2>/dev/null | sort -u | head -n 50000 > "$out_file"
    fi

    local count
    count=$(wc -l < "$out_file" 2>/dev/null || echo 0)
    if [[ "$count" -gt 0 ]]; then
        cecho "$GREEN" "[+] Found ${count} matching dictionary candidates for instant cracking!"
        return 0
    else
        cecho "$DIM" "[!] No direct dictionary word matches found for exact pattern length."
        return 1
    fi
}

# ==============================================================================
# Live Telemetry & Progress Dashboard (Optimized)
# ==============================================================================
run_with_live_stats() {
    local cmd=("$@")
    local start_time
    start_time=$(date +%s)

    # Hide cursor
    tput civis 2>/dev/null || printf "\033[?25l"

    "${cmd[@]}" >"$OUT" 2>&1 &
    HASH_PID=$!

    local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spin_idx=0

    echo -e "\n${BOLD}${CYAN}--- [ LIVE RECOVERY TELEMETRY ] ---${NC}"

    while kill -0 "$HASH_PID" 2>/dev/null; do
        local now
        now=$(date +%s)
        local elapsed=$(( now - start_time ))
        local elapsed_fmt
        elapsed_fmt=$(printf "%02d:%02d" $((elapsed/60)) $((elapsed%60)))

        # High-efficiency single awk pass for status metrics
        read -r progress speed eta < <(awk '
            /Speed\./ { speed=$(NF-1) " " $NF }
            /Progress\./ { 
                for(i=1;i<=NF;i++) {
                    if($i ~ /^\([0-9\.]+%\)$/) {
                        gsub(/[()]/,"",$i);
                        prog=$i;
                    }
                }
            }
            /Time\.Estimated\./ { 
                sub(/^[^:]+: */, "");
                eta=$0;
            }
            END { 
                printf "%s|%s|%s\n", (prog?prog:"0.0%"), (speed?speed:"Benchmarking..."), (eta?eta:"Calculating...")
            }
        ' FS=":" "$OUT" 2>/dev/null | tr '|' ' ')

        progress="${progress:-0.0%}"
        speed="${speed:-Benchmarking...}"
        eta="${eta:-Calculating...}"

        printf "\r${YELLOW}%s${NC} ${BOLD}Progress:${NC} ${GREEN}%-6s${NC} | ${BOLD}Speed:${NC} ${CYAN}%-14s${NC} | ${BOLD}Elapsed:${NC} %s | ${BOLD}ETA:${NC} %s \033[K" \
            "${spinner[spin_idx]}" "$progress" "$speed" "$elapsed_fmt" "$eta"

        spin_idx=$(( (spin_idx + 1) % ${#spinner[@]} ))
        sleep 0.5
    done

    wait "$HASH_PID"
    local exit_code=$?
    HASH_PID=""

    # Restore cursor
    tput cnorm 2>/dev/null || printf "\033[?25h"
    printf "\r\033[K" # Clear status line
    return $exit_code
}

# Extract cracked password
extract_cracked_password() {
    local target_hash="$1"
    local mode="$2"
    local result=""

    # 1. Check exact hash:plain from output stream
    result=$(grep -E "^${target_hash}:" "$OUT" 2>/dev/null | head -n 1 | cut -d':' -f2- | tr -d '\r')

    # 2. Query hashcat potfile / --show
    if [[ -z "$result" ]]; then
        result=$(hashcat -m "$mode" "$target_hash" --show --outfile-format=2 2>/dev/null | tr -d '\r' | sed '/^[[:space:]]*$/d' | head -n 1)
    fi

    # 3. Fallback scan non-status line output
    if [[ -z "$result" ]]; then
        local candidate
        candidate=$(grep -v -E "(Hashcat|Session|Status|Hardware|Time\.|Speed\.|Recovered|Progress|Rejected|Restore|Started|Stopped|Approaching|Candidates|Parsed|Bitmap|Rules|Watchdog|Guess|Device|OpenCL|CUDA|Backend|Host|Features|INFO|WARN|ATTENTION)" "$OUT" | tr -d '\r' | sed '/^[[:space:]]*$/d' | tail -n 1)
        if [[ "$candidate" =~ ":" ]]; then
            result=$(echo "$candidate" | cut -d':' -f2-)
        fi
    fi

    echo "$result"
}

# ==============================================================================
# CLI Argument Parsing
# ==============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--hash)
                CLI_HASH="$2"
                shift 2
                ;;
            -p|--partial)
                CLI_PARTIAL="$2"
                shift 2
                ;;
            -w|--wordlist)
                CLI_WORDLIST="$2"
                shift 2
                ;;
            -m|--mode)
                CLI_MODE="$2"
                shift 2
                ;;
            -a|--attack)
                CLI_ATTACK="$2"
                shift 2
                ;;
            -c|--charset)
                CLI_CHARSET="$2"
                shift 2
                ;;
            -W|--workload)
                CLI_WORKLOAD="$2"
                shift 2
                ;;
            -r|--rule)
                CLI_RULE="$2"
                shift 2
                ;;
            -O|--optimized)
                CLI_OPTIMIZED=true
                shift
                ;;
            --no-optimized)
                CLI_OPTIMIZED=false
                shift
                ;;
            --no-potfile)
                CLI_POTFILE=false
                shift
                ;;
            --no-autocomplete)
                CLI_AUTOCOMPLETE=false
                shift
                ;;
            -s|--structural)
                CLI_STRUCTURAL=true
                shift
                ;;
            -o|--output)
                CLI_OUTPUT="$2"
                shift 2
                ;;
            -f|--force)
                CLI_FORCE=true
                shift
                ;;
            -b|--benchmark)
                CLI_BENCHMARK=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "HashForge v3.0 Pro (Optimized Edition)"
                exit 0
                ;;
            *)
                cecho "$RED" "Unknown argument: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
}

# Draw a formatted terminal textbox
draw_textbox() {
    local title="$1"
    local prompt_text="$2"
    local hint="$3"

    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    printf "${CYAN}│${NC} ${BOLD}%-63s${NC}${CYAN}│${NC}\n" " $title"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
    printf "${CYAN}│${NC} %-63s${CYAN}│${NC}\n" " $prompt_text"
    if [[ -n "$hint" ]]; then
        printf "${CYAN}│${NC} ${DIM}%-63s${NC}${CYAN}│${NC}\n" " $hint"
    fi
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────┘${NC}"
}

# ==============================================================================
# Main Execution Flow
# ==============================================================================
parse_args "$@"

# Check dependencies
ensure_dependencies

# Handle Benchmark Flag
if [[ "$CLI_BENCHMARK" == true ]]; then
    show_banner
    cecho "$CYAN" "[*] Running Hashcat hardware performance benchmark..."
    hashcat -b
    exit 0
fi

# Ensure default wordlist
ensure_rockyou

# Interactive prompt if no hash is passed via CLI
if [[ -z "$CLI_HASH" ]]; then
    clear
    show_banner
    hardware_profile
    echo ""

    # Textbox 1: Incomplete / Half password
    draw_textbox "TEXTBOX 1/2: INCOMPLETE PASSWORD PATTERN" "Enter partial password (use * for missing characters):" "Examples: adm*n, pass***, 1P****!, or leave empty for full search"
    read -rp ">> " CLI_PARTIAL
    echo ""

    # Textbox 2: Full hash
    draw_textbox "TEXTBOX 2/2: FULL PASSWORD HASH" "Enter the full password hash to crack:" "Auto-detects MD5, SHA1, NTLM, SHA256, SHA512, etc."
    read -rp ">> " CLI_HASH
    echo ""
else
    show_banner
fi

# Trim inputs
CLI_HASH=$(echo "$CLI_HASH" | xargs)
CLI_PARTIAL=$(echo "$CLI_PARTIAL" | xargs)
CLI_WORDLIST=$(echo "${CLI_WORDLIST:-$ROCKYOU_PATH}" | xargs)

# Validate hash
if [[ -z "$CLI_HASH" ]]; then
    cecho "$RED" "[!] Error: Target hash is required."
    exit 1
fi

# Auto-detect hash mode if not specified
if [[ -z "$CLI_MODE" ]]; then
    CLI_MODE=$(detect_hash_mode "$CLI_HASH")
    # Quick NTLM prompt if length is 32 and running interactively
    if [[ "${#CLI_HASH}" -eq 32 && -t 0 && -z "$CLI_PARTIAL" ]]; then
        cecho "$DIM" "[?] 32-character hash detected. Default is MD5 (0). For NTLM use -m 1000."
    fi
fi

# Check Potfile first for instant zero-second recovery
if [[ "$CLI_POTFILE" == true ]]; then
    INSTANT_CHECK=$(hashcat -m "$CLI_MODE" "$CLI_HASH" --show --outfile-format=2 2>/dev/null | tr -d '\r' | sed '/^[[:space:]]*$/d' | head -n 1)
    if [[ -n "$INSTANT_CHECK" ]]; then
        echo -e "${GREEN}=================================================================${NC}"
        echo -e "${BOLD}${GREEN} [+] INSTANT POTFILE HIT! Password already recovered:${NC}"
        echo -e "     ${BOLD}${YELLOW}${INSTANT_CHECK}${NC}"
        echo -e "${GREEN}=================================================================${NC}"
        [[ -n "$CLI_OUTPUT" ]] && echo "${CLI_HASH}:${INSTANT_CHECK}" >> "$CLI_OUTPUT"
        exit 0
    fi
fi

# ==============================================================================
# Strategy Determination (Autocomplete vs Structural vs Mask vs Dictionary)
# ==============================================================================
FINAL_ATTACK_WORDLIST=""
FINAL_MASK=""
CUSTOM_CHARSET_OPT=()

# 1. Structural Pattern check (Digit + Upper + Word + Punctuation)
if [[ "$CLI_STRUCTURAL" == true || $(detect_structural_pattern "$CLI_PARTIAL"; echo $?) -eq 0 ]]; then
    cecho "$PURPLE" "[+] Structural pattern detected: [Digit] + [Uppercase] + [Word] + [Punctuation]"
    generate_structural_wordlist "$CLI_PARTIAL" "$CLI_WORDLIST" "$STRUCTURAL_LIST"
    if [[ -s "$STRUCTURAL_LIST" ]]; then
        CLI_ATTACK="0"
        FINAL_ATTACK_WORDLIST="$STRUCTURAL_LIST"
    fi
fi

# 2. Dictionary Autocomplete check if pattern contains '*'
if [[ -z "$FINAL_ATTACK_WORDLIST" && "$CLI_AUTOCOMPLETE" == true && -n "$CLI_PARTIAL" && "$CLI_PARTIAL" =~ \* ]]; then
    generate_autocomplete_wordlist "$CLI_PARTIAL" "$CLI_WORDLIST" "$AUTOCOMPLETE_LIST"
    if [[ -s "$AUTOCOMPLETE_LIST" ]]; then
        CLI_ATTACK="0"
        FINAL_ATTACK_WORDLIST="$AUTOCOMPLETE_LIST"
    fi
fi

# 3. Fallback to Mask Attack if partial pattern provided without autocomplete match
if [[ -z "$FINAL_ATTACK_WORDLIST" && -n "$CLI_PARTIAL" ]]; then
    CLI_ATTACK="3"
    MASK_SPEC="?a"

    case "$CLI_CHARSET" in
        l)  MASK_SPEC="?l" ;;
        u)  MASK_SPEC="?u" ;;
        d)  MASK_SPEC="?d" ;;
        s)  MASK_SPEC="?s" ;;
        al)
            CUSTOM_CHARSET_OPT=("-1" "?l?u?d")
            MASK_SPEC="?1"
            ;;
        h)
            CUSTOM_CHARSET_OPT=("-1" "0123456789abcdef")
            MASK_SPEC="?1"
            ;;
        a)
            MASK_SPEC="?a"
            ;;
        *)
            # User passed custom charset string (e.g. -c "abc123!@#")
            CUSTOM_CHARSET_OPT=("-1" "$CLI_CHARSET")
            MASK_SPEC="?1"
            ;;
    esac

    FINAL_MASK=$(echo "$CLI_PARTIAL" | sed "s/\*/${MASK_SPEC}/g")
fi

# Default fallback attack mode
if [[ -z "$CLI_ATTACK" ]]; then
    if [[ -n "$FINAL_MASK" ]]; then
        CLI_ATTACK="3"
    else
        CLI_ATTACK="0"
    fi
fi

# Construct Base Hashcat Command Array
HASHCAT_CMD=(
    "hashcat"
    "-m" "$CLI_MODE"
    "-a" "$CLI_ATTACK"
    "-w" "$CLI_WORKLOAD"
    "--status"
    "--status-timer=1"
)

# Apply Performance & Optimization Flags
if [[ "$CLI_OPTIMIZED" == true ]]; then
    HASHCAT_CMD+=("-O") # Enable optimized GPU/CPU OpenCL kernels
fi

if [[ "$CLI_POTFILE" == false ]]; then
    HASHCAT_CMD+=("--potfile-disable")
fi

if [[ "$CLI_FORCE" == true ]]; then
    HASHCAT_CMD+=("--force")
fi

if [[ -n "$CLI_RULE" && -f "$CLI_RULE" ]]; then
    HASHCAT_CMD+=("-r" "$CLI_RULE")
fi

if [[ ${#CUSTOM_CHARSET_OPT[@]} -gt 0 ]]; then
    HASHCAT_CMD+=("${CUSTOM_CHARSET_OPT[@]}")
fi

# Append Target Hash
HASHCAT_CMD+=("$CLI_HASH")

# Append Attack Inputs
if [[ "$CLI_ATTACK" == "3" ]]; then
    FINAL_MASK="${FINAL_MASK:-?a?a?a?a?a?a?a?a}"
    HASHCAT_CMD+=("$FINAL_MASK")
elif [[ "$CLI_ATTACK" == "0" ]]; then
    WORDLIST_TO_RUN="${FINAL_ATTACK_WORDLIST:-$CLI_WORDLIST}"
    if [[ ! -f "$WORDLIST_TO_RUN" ]]; then
        cecho "$RED" "[!] Error: Wordlist file not found: $WORDLIST_TO_RUN"
        exit 1
    fi
    HASHCAT_CMD+=("$WORDLIST_TO_RUN")
elif [[ "$CLI_ATTACK" == "6" ]]; then
    if [[ ! -f "$CLI_WORDLIST" ]]; then
        cecho "$RED" "[!] Error: Wordlist file not found: $CLI_WORDLIST"
        exit 1
    fi
    HASHCAT_CMD+=("$CLI_WORDLIST" "${FINAL_MASK:-?d?d?d?d}")
fi

# Attack Summary Card
echo -e "${CYAN}=================================================================${NC}"
echo -e "${BOLD} JOB CONFIGURATION:${NC}"
echo -e "  ${BOLD}Hash Target     :${NC} ${YELLOW}${CLI_HASH}${NC}"
echo -e "  ${BOLD}Hash Mode       :${NC} ${GREEN}${CLI_MODE}${NC}"
echo -e "  ${BOLD}Attack Mode     :${NC} ${GREEN}${CLI_ATTACK}${NC}"
[[ -n "$FINAL_MASK" ]] && echo -e "  ${BOLD}Mask Pattern    :${NC} ${GREEN}${FINAL_MASK}${NC}"
[[ "$CLI_ATTACK" == "0" ]] && echo -e "  ${BOLD}Active Wordlist :${NC} ${GREEN}${WORDLIST_TO_RUN}${NC}"
echo -e "  ${BOLD}Workload Profile:${NC} ${GREEN}${CLI_WORKLOAD}${NC}"
echo -e "  ${BOLD}Kernel Optimized:${NC} ${GREEN}${CLI_OPTIMIZED}${NC} (-O)"
echo -e "  ${BOLD}Potfile Cache   :${NC} ${GREEN}${CLI_POTFILE}${NC}"
[[ -n "$CLI_RULE" ]] && echo -e "  ${BOLD}Rule File       :${NC} ${GREEN}${CLI_RULE}${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Launch cracking session with Live Stats
run_with_live_stats "${HASHCAT_CMD[@]}"
EXIT_CODE=$?

# Extract result
CRACKED=$(extract_cracked_password "$CLI_HASH" "$CLI_MODE")

# Fallback: If autocomplete list finished without hit, try full mask attack as backup
if [[ -z "$CRACKED" && -n "$FINAL_ATTACK_WORDLIST" && -n "$CLI_PARTIAL" ]]; then
    cecho "$YELLOW" "\n[*] Autocomplete wordlist completed. Launching full mask sweep fallback..."
    MASK_SPEC="?a"
    FINAL_MASK=$(echo "$CLI_PARTIAL" | sed "s/\*/${MASK_SPEC}/g")
    
    FALLBACK_CMD=(
        "hashcat"
        "-m" "$CLI_MODE"
        "-a" "3"
        "-w" "$CLI_WORKLOAD"
        "--status"
        "--status-timer=1"
    )
    [[ "$CLI_OPTIMIZED" == true ]] && FALLBACK_CMD+=("-O")
    [[ "$CLI_POTFILE" == false ]] && FALLBACK_CMD+=("--potfile-disable")
    [[ "$CLI_FORCE" == true ]] && FALLBACK_CMD+=("--force")
    FALLBACK_CMD+=("$CLI_HASH" "$FINAL_MASK")

    run_with_live_stats "${FALLBACK_CMD[@]}"
    EXIT_CODE=$?
    CRACKED=$(extract_cracked_password "$CLI_HASH" "$CLI_MODE")
fi

# Display Result Summary Card
echo ""
if [[ -n "$CRACKED" ]]; then
    echo -e "${GREEN}=================================================================${NC}"
    echo -e "${BOLD}${GREEN} [+] SUCCESS! Password Successfully Recovered:${NC}"
    echo -e "     ${BOLD}${YELLOW}${CRACKED}${NC}"
    echo -e "${GREEN}=================================================================${NC}"

    # Export result if output flag is specified
    if [[ -n "$CLI_OUTPUT" ]]; then
        echo "${CLI_HASH}:${CRACKED}" >> "$CLI_OUTPUT"
        cecho "$CYAN" "[+] Result saved to: ${CLI_OUTPUT}"
    fi
else
    echo -e "${RED}=================================================================${NC}"
    echo -e "${BOLD}${RED} [-] Recovery session finished: Password not cracked.${NC}"
    echo -e "${RED}=================================================================${NC}"

    if [[ $EXIT_CODE -ne 0 && $EXIT_CODE -ne 1 ]]; then
        echo -e "\n${YELLOW}[!] Hashcat Diagnostic Output:${NC}"
        grep -E "(Error|Token length|No devices|Separator|Cannot|failed|Unsupported|Invalid)" "$OUT" | head -n 6
    fi
fi

exit 0