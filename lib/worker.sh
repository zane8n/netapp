#!/bin/bash
#
# NetSnmp - Worker Library
# Description: Contains the atomic functions that perform the work on a single IP.
# This is what gets called in parallel by the scan orchestrator.

# Retrieves key details (sysName, sysDescr, serial) from a device via SNMP.
# OPTIMIZATION / STEALTH: This is a major improvement. Instead of multiple `snmpget`
# calls, it uses a single `snmpwalk` to retrieve a block of useful MIBs at once.
# This results in ONE query per community instead of many, making it faster and stealthier.
get_device_details() {
    local ip="$1"
    local -A details=( [ip]="$ip" [name]="" [serial]="" [descr]="" [mac]="" )

    # OIDs for key information
    local sys_name_oid="1.3.6.1.2.1.1.5.0"
    local sys_descr_oid="1.3.6.1.2.1.1.1.0"
    # Common serial number OIDs for various vendors
    local serial_oids=(
        "1.3.6.1.2.1.47.1.1.1.1.11.1" # entPhysicalSerialNum
        "1.3.6.1.4.1.9.3.6.3.0"      # Cisco
    )
    # MAC address via ifPhysAddress for the first interface
    local mac_oid="1.3.6.1.2.1.2.2.1.6.1"

    local communities_to_try
    IFS=' ' read -r -a communities_to_try <<< "${CONFIG[communities]}"

    for community in "${communities_to_try[@]}"; do
        # Combine all OIDs into a single snmpget call for maximum efficiency
        local all_oids=("$sys_name_oid" "$sys_descr_oid" "${serial_oids[@]}" "$mac_oid")
        local snmp_output
        snmp_output=$(snmpget -v2c -c "$community" -t "${CONFIG[snmp_timeout]}" -Oqvn "$ip" "${all_oids[@]}" 2>/dev/null)

        if [[ -n "$snmp_output" ]]; then
            # We got a response, parse it
            mapfile -t values <<< "$snmp_output"
            details[name]="${values[0]}"
            details[descr]="${values[1]}"
            details[mac]="${values[${#values[@]}-1]}" # MAC is always last

            # Find the first valid serial number from the response
            for i in $(seq 2 $((${#serial_oids[@]} + 1)) ); do
                if [[ -n "${values[$i]}" && "${values[$i]}" != "noSuchObject" && "${values[$i]}" != "noSuchInstance" ]]; then
                    details[serial]="${values[$i]}"
                    break
                fi
            done
            
            # If we found a name, we can stop trying communities
            if [[ -n "${details[name]}" ]]; then
                # Output in a consistent "ip|name|serial|mac|description" format
                echo "${details[ip]}|${details[name]}|${details[serial]}|${details[mac]}|${details[descr]}"
                return 0
            fi
        fi
    done

    return 1 # No valid SNMP response
}

# Pings and then gets SNMP details for a single IP address.
# This function is designed to be called by a parallel processor like xargs.
scan_single_ip() {
    local ip="$1"
    log_debug "Worker: Starting scan for $ip"

    # STEALTH: Use a fast, single-packet ping. `fping` is preferred if available
    # as it's designed for scanning and is more efficient.
    if is_command_available "fping"; then
        fping -c1 -t"${CONFIG[ping_timeout]}00" "$ip" &>/dev/null
    else
        ping -c1 -W"${CONFIG[ping_timeout]}" "$ip" &>/dev/null
    fi

    if [[ $? -eq 0 ]]; then
        log_debug "Worker: Ping success for $ip. Querying SNMP..."
        local details
        details=$(get_device_details "$ip")
        if [[ $? -eq 0 ]]; then
            log_debug "Worker: SNMP success for $ip."
            # The output from get_device_details is already formatted for the cache
            echo "$details"
            return 0
        else
            log_debug "Worker: Ping success, but no SNMP response for $ip."
        fi
    else
        log_debug "Worker: No ping response from $ip."
    fi

    return 1
}