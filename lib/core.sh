#!/bin/bash
#
# NetSnmp - Core Library
# Description: Contains essential functions for configuration, logging, and utilities.

# --- Configuration Management ---

# Declare CONFIG as an associative array to hold all settings.
declare -A CONFIG

# Default configuration values. These are overwritten by the config file.
DEFAULT_CONFIG=(
    ["networks"]=""
    ["communities"]="public"
    ["ping_timeout"]="1"
    ["snmp_timeout"]="2"
    ["scan_workers"]="20"
    ["cache_ttl"]="3600"
    ["enable_logging"]="true"
)

# Loads configuration from the file into the CONFIG array.
# REFACTOR: This function is now robust. It handles missing files, trims whitespace,
# removes quotes, and ignores comments/empty lines gracefully.
load_config() {
    # Initialize with defaults first
    for key in "${!DEFAULT_CONFIG[@]}"; do
        CONFIG["$key"]="${DEFAULT_CONFIG[$key]}"
    done

    if [[ ! -f "$CONFIG_FILE" ]]; then
        if [[ -t 1 ]]; then
            log_error "Configuration file not found at '$CONFIG_FILE'."
            log_info "Please create it or run 'sudo netsnmp --wizard'."
        fi
        return 1
    fi

    # Process only valid, non-commented lines from the config file
    while IFS= read -r line; do
        # Use cut to safely separate key and value
        local key
        key=$(echo "$line" | cut -d '=' -f 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        local value
        value=$(echo "$line" | cut -d '=' -f 2- | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')

        # Store in config array only if the key is a valid/known setting
        if [[ -n "$key" && -v "DEFAULT_CONFIG[$key]" ]]; then
            CONFIG["$key"]="$value"
            log_debug "Config loaded: [$key] = [${CONFIG[$key]}]"
        fi
    done < <(grep -v '^\s*#' "$CONFIG_FILE" | grep '=') # Read from a process substitution that pre-filters the file

    log_debug "Configuration loading complete."
}

# Saves the current CONFIG array back to the configuration file.
save_config() {
    # Use a temporary file to prevent corruption on write error
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

    # Move temp file into place. Use sudo if needed.
    if [[ $EUID -eq 0 ]]; then
        install -m 644 "$tmp_file" "$CONFIG_FILE"
    else
        # This case is rare (user running wizard without sudo), but handle it.
        cp "$tmp_file" "$CONFIG_FILE"
    fi
    rm -f "$tmp_file"
    log_info "Configuration saved to $CONFIG_FILE"
}

# --- Logging Framework ---
# REFACTOR: Centralized and improved logging. Now handles permissions checks
# and respects the QUIET flag.

log_msg() {
    local level="$1"
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"

    # Errors and informational messages go to stderr to not interfere with stdout data.
    if [[ "$level" == "ERROR" ]]; then
        echo -e "\033[0;31m${message}\033[0m" >&2
    elif [[ "$QUIET" != "true" ]]; then
        # All standard logs now go to stderr.
        echo "$message" >&2
    fi

    # File logging remains the same.
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

# Checks if a command is available in the system's PATH.
is_command_available() {
    command -v "$1" &>/dev/null
}

# Exports necessary variables and functions for subshells (used in parallel scanning).
export_for_subshells() {
    export CONFIG_FILE CACHE_FILE AP_CACHE_FILE LOG_FILE QUIET DEBUG
    export -A CONFIG
    export -f log_msg log_info log_error log_debug
    export -f is_command_available
    export -f get_device_details # From scan.sh
    export -f scan_single_ip      # From worker.sh
}