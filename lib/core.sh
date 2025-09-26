#!/bin/bash
#
# NetSnmp Core Library
# Handles configuration, logging, and global definitions.

# --- Global Definitions ---
readonly VERSION="2.0.0"
readonly AUTHOR="Network Tools Team (Refactored)"
readonly LICENSE="GPL-3.0"

# Set default paths. These are adjusted for user-level execution.
CONFIG_DIR="/etc/netsnmp"
CACHE_DIR="/var/cache/netsnmp"
LOG_FILE="/var/log/netsnmp.log"
CACHE_FILE="" 
AP_CACHE_FILE=""

declare -A CONFIG
LOG_LEVEL="NORMAL" # Levels: NORMAL, VERBOSE, DEBUG

# --- Core Functions ---

# Sets the global log level.
# Usage: core::set_log_level "DEBUG"
function core::set_log_level() {
    LOG_LEVEL="$1"
    if [[ "$LOG_LEVEL" == "DEBUG" ]]; then
        set -x # Enable shell tracing.
    fi
}

# Initializes paths and loads configuration. This must be run first.
function core::init_config() {
    # Adjust paths for non-root users.
    if [[ $EUID -ne 0 ]]; then
        CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/netsnmp"
        CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/netsnmp"
        LOG_FILE="${CACHE_DIR}/netsnmp.log"
    fi

    # Define global cache file paths.
    CACHE_FILE="${CACHE_DIR}/hosts.cache"
    AP_CACHE_FILE="${CACHE_DIR}/aps.cache"

    mkdir -p "$CONFIG_DIR" "$CACHE_DIR"

    # Load configuration from file or prompt for wizard if it's missing.
    if [[ ! -f "${CONFIG_DIR}/netsnmp.conf" ]]; then
        core::log "INFO" "Configuration not found. Launching wizard."
        ui::run_config_wizard # This function is in ui.sh
    fi
    
    core::load_config
}

# Loads configuration from file into the CONFIG associative array.
function core::load_config() {
    local config_file="${CONFIG_DIR}/netsnmp.conf"
    
    # Set default values.
    CONFIG=(
        ["subnets"]=""
        ["communities"]="public"
        ["ping_timeout"]="1"
        ["snmp_timeout"]="2"
        ["scan_workers"]="20"
        ["cache_ttl"]="3600"
        ["enable_logging"]="true"
    )

    [[ ! -f "$config_file" ]] && return # Return if no config file, defaults are set.
    
    # Read the config file line by line, safely.
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^\s*# ]] || [[ -z "$key" ]] && continue # Skip comments/empty lines.
        
        # Trim whitespace from key and quotes/whitespace from value.
        key=$(echo "$key" | tr -d '[:space:]')
        value=$(echo "$value" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//;s/^'\''//;s/'\''.*$//')
        
        # Only update keys that exist in our default list.
        [[ -v "CONFIG[$key]" ]] && CONFIG["$key"]="$value"
    done < "$config_file"
    
    core::log "DEBUG" "Config loaded: subnets='${CONFIG[subnets]}', workers='${CONFIG[scan_workers]}'"
}

# Saves the current configuration from the CONFIG array to the file.
function core::save_config() {
    local config_file="${CONFIG_DIR}/netsnmp.conf"
    core::log "INFO" "Saving configuration to ${config_file}"
    
    # Atomic write using a temporary file.
    local tmp_file; tmp_file=$(mktemp)

    cat > "$tmp_file" << EOF
# NetSnmp configuration file. Generated on $(date)
subnets="${CONFIG[subnets]}"
communities="${CONFIG[communities]}"
ping_timeout="${CONFIG[ping_timeout]}"
snmp_timeout="${CONFIG[snmp_timeout]}"
scan_workers="${CONFIG[scan_workers]}"
cache_ttl="${CONFIG[cache_ttl]}"
enable_logging="${CONFIG[enable_logging]}"
EOF

    mv "$tmp_file" "$config_file"
    [[ $EUID -eq 0 ]] && chmod 644 "$config_file"
}

# --- Utility Functions ---

# Generates a list of IP addresses from various network formats.
# Change: This function was added from the original script.
function core::generate_ip_list() {
    local network="$1"
    
    # CIDR notation (e.g., 192.168.1.0/24)
    if [[ "$network" == *"/"* ]]; then
        # Simple /24 support for now, as in original.
        if [[ "${network##*/}" == "24" ]]; then
            local base="${network%.*.*}"
            for i in {1..254}; do echo "${base}.${i}"; done
        else
            core::log "ERROR" "Only /24 subnet masks are currently supported."
            return 1
        fi
    # IP Range (e.g., 192.168.1.1-100)
    elif [[ "$network" == *"-"* ]]; then
        local base_ip="${network%-*}"
        local end_range="${network#*-}"
        local start_octet="${base_ip##*.}"
        local base_prefix="${base_ip%.*}"
        
        if ! [[ "$start_octet" =~ ^[0-9]+$ && "$end_range" =~ ^[0-9]+$ && "$start_octet" -le "$end_range" ]]; then
             core::log "ERROR" "Invalid IP range format: $network"
             return 1
        fi
        
        for i in $(seq "$start_octet" "$end_range"); do
            echo "${base_prefix}.${i}"
        done
    # Single IP
    else
        echo "$network"
    fi
}


# --- Logging ---
# Generic logging function with levels.
# Usage: core::log "LEVEL" "Message"
function core::log() {
    local level="$1" message="$2" timestamp
    timestamp=$(date '+%F %T')

    case "$level" in
        DEBUG)   [[ "$LOG_LEVEL" != "DEBUG" ]] && return;;
        VERBOSE) [[ "$LOG_LEVEL" != "VERBOSE" ]] && [[ "$LOG_LEVEL" != "DEBUG" ]] && return ;;
    esac

    # All messages except RAW output go to stderr.
    if [[ "$level" != "RAW" ]]; then
        echo "[${timestamp}] [${level}] ${message}" >&2
    else
        echo "${message}"
    fi

    if [[ "${CONFIG[enable_logging]}" == "true" ]] && [[ "$level" != "RAW" ]]; then
        touch "$LOG_FILE" 2>/dev/null || true
        echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE" 2>/dev/null || true
    fi
}