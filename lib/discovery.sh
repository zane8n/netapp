#!/bin/bash
#
# NetSnmp Discovery Library
# Handles advanced discovery, like APs via CDP/LLDP.

# Updates the AP cache by querying switches for CDP neighbors.
function discovery::update_ap_cache() {
    if [[ ! -s "$CACHE_FILE" ]]; then
        core::log "ERROR" "Device cache is empty. Run 'netsnmp --update' first."
        return 1
    fi

    core::log "INFO" "Discovering APs via CDP from known switches..."
    
    local temp_aps; temp_aps=$(mktemp)

    # Find potential switches from the main cache (simple heuristic).
    # We grep for 'sw', 'rout', or devices that have a serial number.
    grep -Ei ' sw| rout| [^[:space:]]+$' "$CACHE_FILE" | while read -r line; do
        local switch_ip; switch_ip=$(echo "$line" | awk '{print $1}')
        core::log "VERBOSE" "Querying potential switch: ${switch_ip}"
        
        # Get neighbors and append them to the temp file.
        discovery::get_cdp_neighbors "$switch_ip" >> "$temp_aps" &
    done
    wait

    if [[ ! -s "$temp_aps" ]]; then
        core::log "INFO" "Discovery complete. No new APs found."
        rm -f "$temp_aps"
        return
    fi

    # Filter for APs, sort, and make unique.
    grep -Ei 'AP|Air' "$temp_aps" | sort -u > "$AP_CACHE_FILE"
    rm -f "$temp_aps"
    
    local total_aps; total_aps=$(wc -l < "$AP_CACHE_FILE" | tr -d ' ')
    core::log "INFO" "AP discovery complete. Found ${total_aps} APs."
    core::log "INFO" "AP cache updated: ${AP_CACHE_FILE}"
}

# Efficiently gets CDP neighbor info (IP, Hostname, Platform) from a single switch.
# This uses snmpbulkwalk for minimal network traffic.
function discovery::get_cdp_neighbors() {
    local switch_ip="$1"

    for community in ${CONFIG[communities]}; do
        # One single, efficient walk over the entire CDP cache table.
        local cdp_table; cdp_table=$(snmpbulkwalk -v2c -c "$community" -OQ -t "${CONFIG[snmp_timeout]}" "$switch_ip" 1.3.6.1.4.1.9.9.23.1.2.1.1 2>/dev/null)

        if [[ -n "$cdp_table" ]]; then
            # Process the entire table with a single awk command for performance.
            echo "$cdp_table" | awk '
                # OID suffixes: 4=address, 6=deviceID, 8=platform
                /1\.2\.1\.1\.4\./ { ips[$2] = $NF }
                /1\.2\.1\.1\.6\./ { hosts[$2] = $NF }
                /1\.2\.1\.1\.8\./ { platforms[$2] = $NF }
                
                END {
                    for (idx in hosts) {
                        # Convert hex IP to decimal if needed
                        if (ips[idx] ~ /^0x/) {
                            split(substr(ips[idx],3), octets, "");
                            ip_dec = sprintf("%d.%d.%d.%d",
                                             ("0x" octets[1] octets[2]), ("0x" octets[3] octets[4]),
                                             ("0x" octets[5] octets[6]), ("0x" octets[7] octets[8]));
                        } else {
                            ip_dec = ips[idx]; # Already decimal
                        }
                        
                        # Print if we have a valid-looking record
                        if (ip_dec && hosts[idx] && platforms[idx]) {
                            # Clean quotes from strings
                            gsub(/"/, "", hosts[idx]);
                            gsub(/"/, "", platforms[idx]);
                            print ip_dec, hosts[idx], platforms[idx];
                        }
                    }
                }
            '
            return 0 # Success
        fi
    done
    return 1 # Failure
}