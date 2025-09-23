#!/bin/bash
#
# NetSnmp - Debug Library
# Description: Contains functions for testing and troubleshooting.

# Tests SNMP connectivity to a single IP address.
# It tries all configured communities and shows verbose results.
test_snmp() {
    local ip="$1"
    if [[ -z "$ip" ]]; then
        log_error "No IP address provided for SNMP test."
        log_info "Usage: netsnmp --test-snmp <IP_ADDRESS>"
        return 1
    fi

    log_info "--- Testing SNMP Connectivity to: $ip ---"
    log_info "Communities to try: ${CONFIG[communities]}"
    echo

    local communities_to_try
    IFS=' ' read -r -a communities_to_try <<< "${CONFIG[communities]}"
    local success="false"

    for community in "${communities_to_try[@]}"; do
        echo "Trying community: '$community'..."
        # We use -Oqv to get just the value for a clean success check
        local result
        result=$(snmpget -v2c -c "$community" -t "${CONFIG[snmp_timeout]}" -Oqv "$ip" sysName.0 2>&1)
        local exit_code=$?

        if [[ $exit_code -eq 0 && -n "$result" && ! "$result" =~ "No Such Object" ]]; then
            echo -e "  \033[0;32mSUCCESS!\033[0m"
            echo "  - Response (sysName.0): $result"
            success="true"
            break # Stop after the first success
        else
            echo -e "  \033[0;31mFAILED.\033[0m"
            echo "  - Reason: $result (Exit code: $exit_code)"
        fi
        echo "----------------------------------------"
    done

    if [[ "$success" != "true" ]]; then
        log_error "All SNMP attempts failed for $ip."
        return 1
    fi
    return 0
}