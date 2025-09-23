#!/bin/bash
#
# NetSnmp Library - Core Functions
#
declare -A G_CONFIG; declare -A G_PATHS; G_VERBOSE=false; G_QUIET=false; G_DEBUG=false; VERSION="3.0.0"

core::bootstrap() {
    if [[ $EUID -eq 0 ]]; then
        G_PATHS[conf_dir]="/etc/netsnmp"; G_PATHS[cache_dir]="/var/cache/netsnmp"; G_PATHS[log_file]="/var/log/netsnmp.log";
    else
        G_PATHS[conf_dir]="${HOME}/.config/netsnmp"; G_PATHS[cache_dir]="${HOME}/.cache/netsnmp"; G_PATHS[log_file]="${HOME}/.cache/netsnmp.log";
    fi
    G_PATHS[config_file]="${G_PATHS[conf_dir]}/netsnmp.conf"
    G_PATHS[hosts_cache]="${G_PATHS[cache_dir]}/hosts.cache"
    G_PATHS[ap_cache]="${G_PATHS[cache_dir]}/ap.cache"
}

core::init() {
    core::load_config
}

core::load_config() {
    G_CONFIG=( ["subnets"]="192.168.1.0/24" ["communities"]="public" ["ping_timeout"]="1" ["snmp_timeout"]="2" ["scan_workers"]="25" ["cache_ttl"]="3600" ["enable_logging"]="true" ["scan_delay"]="20" ["discovery_protocols"]="cdp lldp" ["scan_mode"]="icmp" )
    if [[ ! -f "${G_PATHS[config_file]}" ]]; then return 0; fi
    while IFS='=' read -r key value; do
        [[ $key =~ ^\s*# ]] || [[ -z $key ]] && continue
        key=$(echo "$key" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        value=$(echo "$value" | sed -e 's/^[[:space:]]*//; s/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        if [[ -n "${G_CONFIG[$key]+_}" ]]; then G_CONFIG["$key"]="$value"; fi
    done < "${G_PATHS[config_file]}"
    core::log_debug "Config loaded. Scan mode is '${G_CONFIG[scan_mode]}'."
}

core::save_config() {
    mkdir -p "${G_PATHS[conf_dir]}"; local tmp_file; tmp_file=$(mktemp)
    local -a ordered_keys=( "subnets" "communities" "ping_timeout" "snmp_timeout" "scan_workers" "cache_ttl" "scan_delay" "enable_logging" "discovery_protocols" "scan_mode" )
    echo "# NetSnmp Configuration File" > "$tmp_file"; echo "# Generated on $(date)" >> "$tmp_file"; echo "" >> "$tmp_file"
    for key in "${ordered_keys[@]}"; do
        case "$key" in
            subnets) echo "# Networks to scan (space-separated: CIDR, ranges, single IPs)" >> "$tmp_file" ;;
            scan_delay) echo "# Delay in milliseconds between pings to reduce network noise (0 to disable)." >> "$tmp_file" ;;
            scan_mode) echo "# Scan strategy: \"icmp\" (ping first) or \"snmp\" (direct SNMP query)." >> "$tmp_file" ;;
        esac
        echo "${key}=\"${G_CONFIG[$key]}\"" >> "$tmp_file"; echo "" >> "$tmp_file"
    done
    mv "$tmp_file" "${G_PATHS[config_file]}"; if [[ $EUID -eq 0 ]]; then chmod 644 "${G_PATHS[config_file]}"; fi
}

core::check_config_context() {
    local system_config="/etc/netsnmp/netsnmp.conf"
    if [[ $EUID -ne 0 && -f "$system_config" && ! -f "${G_PATHS[config_file]}" ]]; then
        local original_command="netsnmp $*"; ui::print_warning_box "A system-wide configuration was found. To use it, you must run your command with 'sudo'.\n\n  Example: sudo ${original_command}\n"; exit 1
    fi
}

core::log() { [[ "$G_QUIET" == "true" ]] && return 0; local message="[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"; echo "$message" >&2; if [[ "${G_CONFIG[enable_logging]}" == "true" ]]; then echo "$message" >> "${G_PATHS[log_file]}" 2>/dev/null || true; fi; }
core::log_error() { local message="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"; echo "$message" >&2; if [[ "${G_CONFIG[enable_logging]}" == "true" ]]; then echo "$message" >> "${G_PATHS[log_file]}" 2>/dev/null || true; fi; }
core::log_debug() { [[ "$G_DEBUG" != "true" ]] && return 0; local timestamp; timestamp=$(date '+%H:%M:%S'); echo "[DEBUG ${timestamp}] $*" >&2; }
core::is_command_available() { command -v "$1" &>/dev/null; }