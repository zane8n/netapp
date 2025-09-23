#!/bin/bash
#
# NetSnmp Library - Discovery Function
# Description: Handles all direct SNMP communication and data parsing.
#

# --- Core SNMP Functions ---

# Resolves device details (hostname and serial number) for a single IP.
# This function is optimized to query multiple OIDs in a single snmpget call,
# which is significantly more efficient and less noisy than multiple calls.
#
# $1: The IP address to query.

# Returns: A pipe-separated string "HOSTNAME|SERIAL" on success, empty on failure.
discovery::resolve_snmp_details() {
    local ip="$1"
    local communities_str="${G_CONFIG[communities]}"
    local -a communities
    read -r -a communities <<< "$communities_str"

    # OIDs to query in a single, efficient request
    local sysname_oid="1.3.6.1.2.1.1.5.0"
    local -a serial_oids=(
        "1.3.6.1.2.1.47.1.1.1.1.11.1"    # entPhysicalSerialNum
        "1.3.6.1.4.1.9.3.6.3.0"          # Cisco Product Serial
    )
    local all_oids="${sysname_oid} ${serial_oids[*]}"

    for community in "${communities[@]}"; do
        core::log_debug "Querying IP ${ip} with community '${community}'"
        local response
        response=$(snmpget -v2c -c "${community}" -OQ -t "${G_CONFIG[snmp_timeout]}" -r 1 "${ip}" ${all_oids} 2>/dev/null)
        
        if [[ $? -eq 0 && -n "$response" ]]; then
            local hostname=""; local serial=""
            while read -r line; do
                if [[ -z "$hostname" && "$line" == *"${sysname_oid}"* ]]; then
                    hostname=$(echo "$line" | cut -d' ' -f2- | sed 's/"//g')
                fi
                if [[ -z "$serial" && ! "$line" =~ "No Such" ]]; then
                    for oid in "${serial_oids[@]}"; do
                        if [[ "$line" == *"$oid"* ]]; then
                            serial=$(echo "$line" | cut -d' ' -f2- | sed 's/"//g'); break;
                        fi
                    done
                fi
            done <<< "$response"

            if [[ -n "$hostname" ]]; then
                core::log_debug "Success for ${ip}: Host=${hostname}, Serial=${serial:-N/A}"
                echo "${hostname}|${serial}"
                return 0
            fi
        fi
    done

    core::log_debug "No valid SNMP response from ${ip} with any community."
    return 1
}


# --- Diagnostic Functions ---

# Tests SNMP connectivity against a single IP address for diagnostic purposes.
# This function is more verbose than the main discovery function.
#
# $1: The IP address to test.
discovery::test_snmp_connectivity() {
    local ip="$1"
    if [[ -z "$ip" ]]; then
        core::log_error "No IP address provided for SNMP test."; return 1;
    fi
    
    ui::print_header "Testing SNMP Connectivity to: ${ip}"
    ui::print_info "Using communities: ${G_CONFIG[communities]}"
    echo ""
    
    local communities_str="${G_CONFIG[communities]}"
    local -a communities
    read -r -a communities <<< "$communities_str"
    local found=false
    
    for community in "${communities[@]}"; do
        echo -e "  Trying community: '${C_YELLOW}${community}${C_RESET}'..."
        
        # We query sysName (hostname) as a basic test
        local response
        response=$(snmpget -v2c -c "${community}" -OQv -t "${G_CONFIG[snmp_timeout]}" -r 1 "${ip}" sysName.0 2>&1)
        local exit_code=$?
        
        if [[ ${exit_code} -eq 0 && -n "$response" && ! "$response" =~ "No Such" ]]; then
            ui::print_success "Response received: ${response}"
            found=true
            break
        else
            echo -e "    ${C_RED}Result:${C_RESET} Failed (Code: ${exit_code}, Response: ${response})"
        fi
    done
    
    echo ""
    if [[ "$found" == "true" ]]; then
        ui::print_success "SNMP connectivity successful."
    else
        ui::print_error "All SNMP attempts failed."
    fi
}

# --- Neighbor Discovery (CDP - Cisco Discovery Protocol) ---

# Gathers all CDP neighbor data from a switch using a single, efficient snmpwalk.
# $1: The IP address of the switch to query.
# $2: The SNMP community to use.
# Returns: A structured list of neighbors, one per line.
# Format: "IP|HOSTNAME|PLATFORM|PORT"
discovery::get_cdp_neighbors() {
    local switch_ip="$1"
    local community="$2"
    
    # This single OID root contains all neighbor info: names, IPs, platforms, ports.
    local cdp_mib_root="1.3.6.1.4.1.9.9.23.1.2.1.1"
    
    local cdp_data
    cdp_data=$(snmpwalk -v2c -c "${community}" -Oq -t "${G_CONFIG[snmp_timeout]}" -r 1 "${switch_ip}" "${cdp_mib_root}" 2>/dev/null)

    if [[ -z "$cdp_data" ]]; then return 1; fi

    declare -A neighbors
    while read -r line; do
        # OID Format: ...mib_root.TYPE.IF_INDEX.DEVICE_INDEX VALUE
        if [[ "$line" =~ \.([0-9]+)\.([0-9]+)\.([0-9]+)[[:space:]]+(.*) ]]; then
            local type="${BASH_REMATCH[1]}"
            local key="${BASH_REMATCH[2]}.${BASH_REMATCH[3]}" # Key is the interface+device index
            local value="${BASH_REMATCH[4]//\"/}" # Raw value, quotes removed
            
            case "$type" in
                # 4 => cdpCacheAddress
                4)
                    # CDP address is often a hex string that needs conversion
                    hex_ip=$(echo "$value" | tr -d ' ' | cut -c1-8)
                    if [[ ${#hex_ip} -eq 8 ]]; then
                        neighbors["$key.ip"]=$(printf "%d.%d.%d.%d" "0x${hex_ip:0:2}" "0x${hex_ip:2:2}" "0x${hex_ip:4:2}" "0x${hex_ip:6:2}")
                    fi
                    ;;
                # 6 => cdpCacheDeviceID (Hostname)
                6) neighbors["$key.hostname"]="$value" ;;
                # 7 => cdpCacheVersion (Platform/OS Info)
                7) neighbors["$key.platform"]="$value" ;;
                # 8 => cdpCachePlatform (Hardware Model) - often better than version
                8) neighbors["$key.platform"]="$value" ;;
                # 5 => cdpCacheDevicePort
                5) neighbors["$key.port"]="$value" ;;
            esac
        fi
    done <<< "$cdp_data"
    
    # Process the collected data
    for key in "${!neighbors[@]}"; do
        if [[ "$key" == *.ip ]]; then
            local base_key="${key%.ip}"
            echo "${neighbors[$base_key.ip]}|${neighbors[$base_key.hostname]}|${neighbors[$base_key.platform]}|${neighbors[$base_key.port]}"
        fi
    done
}

# --- Neighbor Discovery (LLDP - Link Layer Discovery Protocol) ---

# Gathers all LLDP neighbor data from a switch using a single, efficient snmpwalk.
# $1: The IP address of the switch to query.
# $2: The SNMP community to use.
# Returns: A structured list of neighbors, one per line.
# Format: "IP|HOSTNAME|PLATFORM|PORT"
discovery::get_lldp_neighbors() {
    local switch_ip="$1"
    local community="$2"
    
    # OID roots for LLDP data
    local lldp_sysname_root="1.0.8802.1.1.2.1.4.1.1.5"
    local lldp_sysdesc_root="1.0.8802.1.1.2.1.4.1.1.6"
    local lldp_port_root="1.0.8802.1.1.2.1.4.1.1.7"
    local lldp_ip_root="1.0.8802.1.1.2.1.4.2.1.3" # Management Address
    
    local lldp_data
    lldp_data=$(snmpwalk -v2c -c "${community}" -Oq -t "${G_CONFIG[snmp_timeout]}" -r 1 "${switch_ip}" 1.0.8802.1.1.2.1.4 2>/dev/null)

    if [[ -z "$lldp_data" ]]; then return 1; fi
    
    declare -A neighbors
    while read -r line; do
        # OID Format: ...protocol_root.TIME_MARK.LOCAL_PORT.NEIGHBOR_INDEX ... VALUE
        if [[ "$line" =~ \.([0-9]+)\.([0-9]+)\.([0-9]+)[[:space:]]+(.*) ]]; then
            local key="${BASH_REMATCH[2]}.${BASH_REMATCH[3]}" # Key is local port + neighbor index
            local value="${BASH_REMATCH[4]//\"/}"
            
            # The OID tells us what kind of data this is
            if [[ "$line" == *"$lldp_sysname_root"* ]]; then neighbors["$key.hostname"]="$value"; fi
            if [[ "$line" == *"$lldp_sysdesc_root"* ]]; then neighbors["$key.platform"]="$value"; fi
            if [[ "$line" == *"$lldp_port_root"* ]]; then neighbors["$key.port"]="$value"; fi
            if [[ "$line" == *"$lldp_ip_root"* && "$value" =~ ^[0-9] ]]; then
                 # LLDP can return IPs in various formats, we just grab the first valid-looking one
                 neighbors["$key.ip"]="$value"
            fi
        fi
    done <<< "$lldp_data"
    
    # Process the collected data
    for key in "${!neighbors[@]}"; do
        if [[ "$key" == *.ip ]]; then
            local base_key="${key%.ip}"
            echo "${neighbors[$base_key.ip]}|${neighbors[$base_key.hostname]}|${neighbors[$base_key.platform]}|${neighbors[$base_key.port]}"
        fi
    done
}
