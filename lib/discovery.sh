#!/bin/bash
#
# NetSnmp Library - Discovery Functions
#

discovery::resolve_snmp_details() {
    local ip="$1"
    local communities_str="${G_CONFIG[communities]}"
    local -a communities
    read -r -a communities <<< "$communities_str"

    local sysname_oid="1.3.6.1.2.1.1.5.0"
    local -a serial_oids=(
        "1.3.6.1.2.1.47.1.1.1.1.11.1"    # entPhysicalSerialNum
        "1.3.6.1.4.1.9.3.6.3.0"          # Cisco Product Serial
    )
    local all_oids="${sysname_oid} ${serial_oids[*]}"

    for community in "${communities[@]}"; do
        core::log_debug "Worker for ${ip} trying community '${community}'"
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
                core::log_debug "Success for ${ip}: ${hostname}"
                echo "${hostname}|${serial}"
                return 0
            fi
        fi
    done
    core::log_debug "No valid SNMP response from ${ip}."
    return 1
}

discovery::test_snmp_connectivity() {
    local ip="$1"; if [[ -z "$ip" ]]; then core::log_error "No IP address provided."; return 1; fi
    ui::print_header "Testing SNMP to: ${ip}"; ui::print_info "Communities: ${G_CONFIG[communities]}"; echo ""
    local communities_str="${G_CONFIG[communities]}"; local -a communities; read -r -a communities <<< "$communities_str"; local found=false
    for community in "${communities[@]}"; do
        echo -e "  Trying community: '${C_YELLOW}${community}${C_RESET}'..."
        local response; response=$(snmpget -v2c -c "${community}" -OQv -t "${G_CONFIG[snmp_timeout]}" -r 1 "${ip}" sysName.0 2>&1)
        local exit_code=$?
        if [[ ${exit_code} -eq 0 && -n "$response" && ! "$response" =~ "No Such" ]]; then
            ui::print_success "Response: ${response}"; found=true; break;
        else
            echo -e "    ${C_RED}Result:${C_RESET} Failed (Code: ${exit_code})"
        fi
    done
    echo ""; if [[ "$found" == "true" ]]; then ui::print_success "SNMP connectivity successful."; else ui::print_error "All SNMP attempts failed."; fi
}