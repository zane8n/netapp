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

    # OIDs to query
    # sysName is the standard for hostname.
    local sysname_oid="1.3.6.1.2.1.1.5.0"
    
    # A list of common OIDs for serial numbers across different vendors.
    local -a serial_oids=(
        "1.3.6.1.2.1.47.1.1.1.1.11.1"    # entPhysicalSerialNum (Standard)
        "1.3.6.1.4.1.9.3.6.3.0"          # Cisco Product Serial
        "1.3.6.1.4.1.9.5.1.2.19.0"       # Cisco Chassis Serial (Older)
        "1.3.6.1.4.1.11.2.36.1.1.2.9.0"  # HP/Aruba
    )
    
    local all_oids="${sysname_oid} ${serial_oids[*]}"

    for community in "${communities[@]}"; do
        core::log_debug "Querying IP ${ip} with community '${community}'"
        
        # -v2c: Use SNMP version 2c
        # -c:   Community string
        # -OQ:  Removes type identifiers from output (e.g., STRING:)
        # -t:   Timeout in seconds
        # -r:   Number of retries (set to 1 to reduce noise)
        local response
        response=$(snmpget -v2c -c "${community}" -OQ -t "${G_CONFIG[snmp_timeout]}" -r 1 "${ip}" ${all_oids} 2>/dev/null)
        
        # Check if we got any valid response at all
        if [[ $? -eq 0 && -n "$response" ]]; then
            local hostname=""
            local serial=""

            # Parse the multi-line response
            while read -r line; do
                # Extract hostname
                if [[ -z "$hostname" && "$line" == *"${sysname_oid}"* ]]; then
                    hostname=$(echo "$line" | cut -d' ' -f2- | sed 's/"//g')
                fi
                
                # Extract the first valid serial number found
                if [[ -z "$serial" ]]; then
                    for oid in "${serial_oids[@]}"; do
                        if [[ "$line" == *"$oid"* ]]; then
                            # Check for "No Such Object/Instance" which can appear in valid responses
                            if [[ ! "$line" =~ "No Such" ]]; then
                                serial=$(echo "$line" | cut -d' ' -f2- | sed 's/"//g')
                                break # Stop after finding the first one
                            fi
                        fi
                    done
                fi
            done <<< "$response"

            # If we successfully found a hostname, we consider it a success
            if [[ -n "$hostname" ]]; then
                core::log_debug "Success for ${ip}: Host=${hostname}, Serial=${serial:-N/A}"
                echo "${hostname}|${serial}"
                return 0
            fi
        fi
        # If the query fails or returns nothing, try the next community
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