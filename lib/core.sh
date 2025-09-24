#!/bin/bash
#
# NetSnmp - Core Library
# Description: Contains essential functions for configuration, logging, and utilities.

# --- Configuration Management ---
declare -A CONFIG

DEFAULT_CONFIG=(
    ["networks"]="192.168.1.0/24"
    ["communities"]="public"
    ["ping_timeout"]="1"
    ["snmp_timeout"]="2"
    ["scan_workers"]="20"
    ["cache_ttl"]="3600"
    ["enable_logging"]="true"
)

# Loads configuration from the file into the CONFIG array.
# REFACTOR: Hardened this function to be extremely reliable.
load_config() {
    # Initialize with defaults first
    for key in "${!DEFAULT_CONFIG[@]}"; do
        CONFIG["$key"]="${DEFAULT_CONFIG[$key]}"
    done

    if [[ ! -r "$CONFIG_FILE" ]]; then
        # Don't treat this as a fatal error, just log it. The script can
        # still run with default values, which is better than crashing.
        log_info "Configuration file not found or not readable at '$CONFIG_FILE'. Using defaults."
        return
    fi

    # Read the file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 1. Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^\s*# ]]; then
            continue
        fi

        # 2. Ensure the line contains an '='
        if [[ ! "$line" =~ = ]]; then
            continue
        fi

        # 3. Safely extract key and value
        local key
        key=$(echo "$line" | cut -d'=' -f1 | tr -d '[:space:]')
        local value
        value=$(echo "$line" | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')

        # 4. Check if the key is a valid setting we know about
        if [[ -v "DEFAULT_CONFIG[$key]" ]]; then
            CONFIG["$key"]="$value"
            log_debug "Config loaded: [$key] = [${CONFIG[$key]}]"
        fi
    done < "$CONFIG_FILE"
}

# Saves the current CONFIG array back to the configuration file.
save_config() {
    local tmp_file
    tmp_file=$(mktemp) || { log_error "Failed to create temp file for saving config."; return 1; }

    cat > "$tmp_file" <<- EOF
# NetSnmp Configuration File
# Generated on $(date) by the configuration wizard.

networks="${CONFIG[networks]}"
communities="${CONFIG[communities]}"

# --- Performance & Stealth Settings ---
ping_timeout="${CONFIG[ping_timeout]}"
snmp_timeout="${CONFIG[snmp_timeout]}"
scan_workers="${CONFIG[scan_workers]}"

# --- Caching ---
cache_ttl="${CONFIG[cache_ttl]}"

# --- Logging ---
enable_logging="${CONFIG[enable_logging]}"
EOF

    if [[ $EUID -eq 0 ]]; then
        install -m 644 "$tmp_file" "$CONFIG_FILE"
    else
        cp "$tmp_file" "$CONFIG_FILE"
    fi
    rm -f "$tmp_file"
    log_info "Configuration saved to $CONFIG_FILE"
}

# --- Logging Framework ---
log_msg() {
    local level="$1"
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    if [[ "$level" == "ERROR" ]]; then
        echo -e "\033[0;31m${message}\033[0m" >&2
    elif [[ "$QUIET" != "true" ]]; then
        echo "$message" >&2
    fi
    if [[ "${CONFIG[enable_logging]}" == "true" ]]; then
        echo "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_info()  { log_msg "INFO" "$*"; }
log_error() { log_msg "ERROR" "$*"; }
log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        log_msg "DEBUG" "$*"
    fi
}

# --- Utility Functions ---
is_command_available() {
    command -v "$1" &>/dev/null
}

export_for_subshells() {
    export CONFIG_FILE CACHE_FILE AP_CACHE_FILE LOG_FILE QUIET DEBUG VERBOSE
    export -A CONFIG
    export -f log_msg log_info log_error log_debug
    export -f is_command_available
    export -f get_device_details
    export -f scan_single_ip
}