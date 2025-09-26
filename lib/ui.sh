#!/bin/bash
#
# NetSnmp UI Library
# Handles all user-facing output and interaction.

# Displays the main help message.
function ui::show_help() {
    cat << EOF
NetSnmp v${VERSION} - Network Device Discovery Tool

Usage: netsnmp [OPTIONS] [PATTERN]

COMMANDS & OPTIONS:
  [pattern]            Search cache for devices matching pattern. If no
                       pattern, lists all discovered devices.

  -u, --update         Scan configured networks and update the device cache.
  --discover-aps       Discover Access Points via CDP/LLDP from known switches.
  
  -i, --info           Show cache status and statistics.
  -c, --clear          Clear all cached discovery data.
  --wizard             Run the interactive configuration wizard.

  -s, --scan <IP>      Scan a single IP address for immediate results.
  -S, --networks "..." Override configured networks for a one-time scan.
  -C, --communities "..." Override configured SNMP communities for a one-time scan.

  -h, --help           Show this help message.
  -v, --verbose        Enable verbose output for more operational details.
  -vv, --debug         Enable debug mode with shell tracing (very noisy).

EXAMPLES:
  netsnmp --update                  # Scan and build the device cache.
  netsnmp switch                    # Find all devices with 'switch' in their name.
  netsnmp --discover-aps            # Find APs connected to discovered switches.
  netsnmp -s 192.168.1.1            # Check a single device now.
EOF
}

# Runs the interactive configuration wizard.
function ui::run_config_wizard() {
    core::log "RAW" "--- NetSnmp Configuration Wizard ---"
    
    core::log "RAW" "\nEnter networks to scan (space-separated)."
    core::log "RAW" "Formats: 192.168.1.0/24, 10.0.0.1-100, 172.16.1.50"
    read -rp "Networks [${CONFIG[subnets]}]: " CONFIG[subnets]

    core::log "RAW" "\nEnter SNMP communities to try (space-separated)."
    read -rp "Communities [${CONFIG[communities]}]: " CONFIG[communities]

    core::save_config # Function from core.sh

    core::log "INFO" "Configuration saved to ${CONFIG_DIR}/netsnmp.conf"
    core::log "INFO" "Run 'netsnmp --update' to begin scanning."
}

# Displays information and statistics about the cache files.
function ui::show_info() {
    core::log "RAW" "--- Cache Information ---"
    
    if [[ -f "$CACHE_FILE" ]]; then
        local total_hosts; total_hosts=$(wc -l < "$CACHE_FILE" | tr -d ' ')
        local last_mod; last_mod=$(stat -c %y "$CACHE_FILE")
        core::log "RAW" "Device Cache:    ${CACHE_FILE}"
        core::log "RAW" "  - Total Devices:   ${total_hosts}"
        core::log "RAW" "  - Last Updated:    ${last_mod%.*}"
    else
        core::log "RAW" "Device Cache: Not yet created. Run 'netsnmp --update'."
    fi

    if [[ -f "$AP_CACHE_FILE" ]]; then
        local total_aps; total_aps=$(wc -l < "$AP_CACHE_FILE" | tr -d ' ')
        local ap_last_mod; ap_last_mod=$(stat -c %y "$AP_CACHE_FILE")
        core::log "RAW" "AP Cache:        ${AP_CACHE_FILE}"
        core::log "RAW" "  - Total APs:       ${total_aps}"
        core::log "RAW" "  - Last Updated:    ${ap_last_mod%.*}"
    else
        core::log "RAW" "AP Cache: Not yet created. Run 'netsnmp --discover-aps'."
    fi

    echo ""
    if cache::is_valid; then # Function from cache.sh
        core::log "INFO" "Device cache is valid (within TTL)."
    else
        core::log "WARN" "Device cache is stale or missing. Consider running 'netsnmp --update'."
    fi
}