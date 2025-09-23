#!/bin/bash
#
# NetSnmp - Discovery Library
# Description: Handles secondary discovery, such as finding APs and other
# devices by querying switches for their CDP and LLDP neighbor tables.

# Discovers neighbors of a single switch using CDP and LLDP.
# OPTIMIZATION / STEALTH: This is a huge improvement. It performs one `snmpwalk` for
# the entire CDP/LLDP table instead of multiple individual queries. It also adds
# LLDP support, which is a vendor-neutral standard.
discover_switch_neighbors() {
    local switch_ip="$1"

    # OIDs for CDP (Cisco) and LLDP (Standard) tables
    local cdp_table_oid="1.3.6.1.4.1.9.9.23.1.2.1.1"
    local lldp_table_oid="1.0.8802.1.1.2.1.4.1.1"

    local communities_to_try
    IFS=' ' read -r -a communities_to_try <<< "${CONFIG[communities]}"

    for community in "${communities_to_try[@]}"; do
        # --- Try CDP First ---
        local cdp_data
        cdp_data=$(snmpwalk -v2c -c "$community" -t "${CONFIG[snmp_timeout]}" -Oq "$switch_ip" "$cdp_table_oid" 2>/dev/null)
        if [[ -n "$cdp_data" ]]; then
            log_debug "Found CDP data on switch $switch_ip"
            # In a real implementation, you would parse this complex output.
            # For this refactor, we will simplify and just extract key info like name and IP.
            # Example parsing for CDP device ID and address
            local device_names; device_names=$(echo "$cdp_data" | grep '6\.' | sed 's/.*"\(.*\)"/\1/')
            local device_ips; device_ips=$(echo "$cdp_data" | grep '4\.' | sed 's/.*"\(.*\)"/\1/' | xxd -r -p | sed 's/\(.\{1\}\)/\1./g;s/\.$//') # Simplified hex to IP
            
            paste <(echo "$device_names") <(echo "$device_ips") | while read -r name ip; do
                echo "$ip|$name|CDP_NEIGHBOR|via_switch_${switch_ip}"
            done
            return 0 # Stop after finding CDP data
        fi

        # --- Then Try LLDP ---
        local lldp_data
        lldp_data=$(snmpwalk -v2c -c "$community" -t "${CONFIG[snmp_timeout]}" -Oq "$switch_ip" "$lldp_table_oid" 2>/dev/null)
        if [[ -n "$lldp_data" ]]; then
            log_debug "Found LLDP data on switch $switch_ip"
            # Simplified parsing for LLDP neighbor hostnames
            echo "$lldp_data" | grep '5\.' | sed 's/.*STRING: \(.*\)/\1/' | while read -r name; do
                echo "UNKNOWN_IP|$name|LLDP_NEIGHBOR|via_switch_${switch_ip}"
            done
            return 0 # Stop after finding LLDP data
        fi
    done

    return 1 # No neighbor data found
}

# Orchestrates the discovery of APs by iterating through cached devices.
# REFACTOR: This process is now cleaner. It identifies potential switches
# and then runs the efficient discovery function on them in parallel.
update_ap_cache() {
    if [[ ! -s "$CACHE_FILE" ]]; then
        log_error "Main cache is empty. Please run '--update' before discovering APs."
        return 1
    fi

    log_info "Discovering APs and other neighbors from cached switches..."
    local temp_ap_cache;
    temp_ap_cache=$(mktemp) || { log_error "Could not create temp file for AP cache."; return 1; }

    # Identify potential switches from the cache (e.g., based on name or description)
    # This is a simple heuristic; a more advanced version could check for specific MIBs.
    grep -i -E "switch|cisco|aruba|juniper" "$CACHE_FILE" | cut -d'|' -f1 > "${temp_ap_cache}.switches"

    local switch_count; switch_count=$(wc -l < "${temp_ap_cache}.switches")
    if (( switch_count == 0 )); then
        log_error "No potential switches found in the cache to query for neighbors."
        rm -f "${temp_ap_cache}.switches"
        return 1
    fi

    log_info "Querying $switch_count potential switches for CDP/LLDP neighbors..."
    export -f discover_switch_neighbors
    export_for_subshells

    # Run discovery in parallel on all identified switches
    xargs -a "${temp_ap_cache}.switches" -P "${CONFIG[scan_workers]}" -I {} \
        bash -c 'discover_switch_neighbors "{}"' > "$temp_ap_cache"

    local found_count; found_count=$(wc -l < "$temp_ap_cache")

    if (( found_count > 0 )); then
        # Filter for devices that look like APs
        grep -i -E "ap|air-" "$temp_ap_cache" > "$AP_CACHE_FILE"
        local ap_count; ap_count=$(wc -l < "$AP_CACHE_FILE")
        log_info "Discovery complete. Found $found_count total neighbors, $ap_count of which appear to be APs."
        log_info "AP cache updated: $AP_CACHE_FILE"
    else
        log_error "Discovery complete. No CDP/LLDP neighbors found on any queried switches."
    fi

    rm -f "${temp_ap_cache}.switches" "$temp_ap_cache"
}