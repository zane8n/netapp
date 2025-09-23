#!/bin/bash
#
# NetSnmp - UI Library
# Description: Handles all user-facing output, including help text,
# information displays, and the configuration wizard.

# Displays the main help message.
# REFACTOR: Rewritten to be clearer, more organized, and concise.
show_help() {
    cat << EOF
NetSnmp v${VERSION} - A low-noise network discovery and inventory tool.

Usage:
  netsnmp [COMMAND] [OPTIONS] [PATTERN]

Commands:
  --update              Scan networks defined in the config and update the cache.
  --discover-aps        Discover APs and other devices via switches in the cache.
  search [pattern]      Search the cache for a device (default action if no command).

Cache & Information:
  -i, --info            Show cache statistics and status.
  -c, --clear           Clear all discovery caches.
  --aps [pattern]       Show discovered APs from the AP cache.
  --serials [pattern]   Show devices with a discovered serial number.

Configuration & System:
  --wizard              Run the interactive configuration wizard.
  --config              Display the current configuration.
  -h, --help            Show this help message.
  --version             Show tool version.

Advanced Scanning:
  -S, --networks "..."  Override configured networks for a single scan.
  -C, --communities "..." Override configured SNMP communities for a single scan.

Debugging:
  -v, --verbose         Enable verbose output.
  -vv, --debug          Enable debug output with shell command tracing.
  --test-snmp <IP>      Test SNMP connectivity to a single device.

Examples:
  sudo netsnmp --update                 # Update the main device cache.
  sudo netsnmp --discover-aps           # Discover APs connected to cached switches.
  netsnmp switch-core-01                # Search for a device by name or IP.
  netsnmp --aps cisco                   # Find all Cisco APs.
EOF
}

# Displays statistics and information about the cache.
# REFACTOR: Provides more useful and readable information.
show_info() {
    echo "--- NetSnmp Cache Information ---"
    if [[ ! -f "$CACHE_FILE" || ! -s "$CACHE_FILE" ]]; then
        log_error "Main device cache is empty or does not exist."
        log_info "Run 'sudo netsnmp --update' to build it."
        return 1
    fi

    local total_hosts; total_hosts=$(wc -l < "$CACHE_FILE")
    local last_mod; last_mod=$(stat -c %y "$CACHE_FILE")
    local age_sec; age_sec=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
    local age_min=$(( age_sec / 60 ))

    echo "Main Device Cache: $CACHE_FILE"
    echo "  - Total Devices: $total_hosts"
    echo "  - Last Updated:  $last_mod ($age_min minutes ago)"

    if [[ "$age_sec" -gt "${CONFIG[cache_ttl]}" ]]; then
        log_error "  - Status: Stale (older than TTL of ${CONFIG[cache_ttl]}s). Please run --update."
    else
        echo -e "  - Status: \033[0;32mValid\033[0m"
    fi
    echo ""

    if [[ -f "$AP_CACHE_FILE" && -s "$AP_CACHE_FILE" ]]; then
        local ap_hosts; ap_hosts=$(wc -l < "$AP_CACHE_FILE")
        local ap_last_mod; ap_last_mod=$(stat -c %y "$AP_CACHE_FILE")
        echo "AP & CDP/LLDP Cache: $AP_CACHE_FILE"
        echo "  - Total Devices: $ap_hosts"
        echo "  - Last Updated:  $ap_last_mod"
    else
        log_info "AP cache is empty. Run 'sudo netsnmp --discover-aps' after an update."
    fi
}

# Displays the currently loaded configuration.
show_config() {
    echo "--- Current Configuration ---"
    echo "Loaded from: $CONFIG_FILE"
    echo
    for key in "${!CONFIG[@]}"; do
        printf "  %-18s: %s\n" "$key" "${CONFIG[$key]}"
    done
}

# Runs the interactive configuration wizard.
# REFACTOR: Prompts are clearer and provide better examples.
run_config_wizard() {
    echo "╔══════════════════════════════════════════════════╗"
    echo "║             NetSnmp Configuration Wizard         ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo
    log_info "This wizard will help you create a configuration file."
    log_info "Press [Enter] to accept the default value in brackets."
    echo

    # Prompt for networks
    echo "Enter the networks to scan, separated by spaces."
    echo "Examples: 192.168.1.0/24 10.10.0.50-100"
    read -p "Networks [${CONFIG[networks]}]: " user_networks
    CONFIG[networks]="${user_networks:-${CONFIG[networks]}}"

    # Prompt for communities
    echo
    echo "Enter the SNMP communities to try, separated by spaces."
    read -p "Communities [${CONFIG[communities]}]: " user_communities
    CONFIG[communities]="${user_communities:-${CONFIG[communities]}}"

    # Save the configuration
    save_config
}