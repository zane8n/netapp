#!/bin/bash
#
# NetSnmp Scan Library
# Handles the actual network scanning logic.

# Scans a single host and prints results to stdout.
# Usage: scan::single_host <IP>
function scan::single_host() {
    local ip="$1"
    core::log "INFO" "Scanning single host: ${ip}"
    
    local result; result=$(scan::worker "$ip")
    if [[ -n "$result" ]]; then
        core::log "RAW" "✓ Host Found:"
        core::log "RAW" "  IP:       ${result%% *}"
        core::log "RAW" "  Hostname: $(echo "$result" | awk '{print $2}')"
        core::log "RAW" "  Serial:   $(echo "$result" | awk '{print $3}')"
    else
        core::log "WARN" "Host ${ip} is offline or not responding to SNMP."
    fi
}

# The core worker function for scanning a single IP.
# Returns "IP HOSTNAME SERIAL" on success, empty on failure.
# Usage: scan::worker <IP>
function scan::worker() {
    local ip="$1"
    
    # Use fping if available (faster), otherwise fallback to ping.
    if command -v fping &>/dev/null; then
        fping -c1 -t"${CONFIG[ping_timeout]}00" "$ip" &>/dev/null || return 1
    else
        ping -c1 -W"${CONFIG[ping_timeout]}" "$ip" &>/dev/null || return 1
    fi
    
    core::log "DEBUG" "Ping success for ${ip}, trying SNMP."

    for community in ${CONFIG[communities]}; do
        # Optimization: Query for hostname and serial number in a single request.
        local oids="sysName.0 1.3.6.1.2.1.47.1.1.1.1.11.1" # Standard Hostname and Serial OID
        local snmp_result; snmp_result=$(snmpget -v2c -c "$community" -Oqv -t "${CONFIG[snmp_timeout]}" "$ip" $oids 2>/dev/null)
        
        # Check if we got a valid response (not timeout or error).
        if [[ $? -eq 0 ]] && [[ -n "$snmp_result" ]]; then
            # The result will be multi-line, process it.
            local hostname; hostname=$(echo "$snmp_result" | head -n1 | tr -d '\r\n"')
            local serial; serial=$(echo "$snmp_result" | tail -n1 | tr -d '\r\n"')
            
            # Sanitize output. If serial is not found, it might echo the OID.
            [[ "$serial" == "No Such Instance"* ]] && serial=""

            echo "$ip $hostname $serial"
            return 0 # Success, stop trying communities.
        fi
    done

    return 1 # No SNMP response with any community.
}

# Scans a full network in parallel.
# Usage: scan::network <NETWORK_DEFINITION>
function scan::network() {
    local network="$1"
    core::log "VERBOSE" "Generating IP list for network: ${network}"
    
    local ip_list; ip_list=$(core::generate_ip_list "$network")
    [[ $? -ne 0 || -z "$ip_list" ]] && core::log "ERROR" "Failed to generate IPs for ${network}." && return 1

    local ip_count; ip_count=$(echo "$ip_list" | wc -l)
    core::log "INFO" "Scanning ${ip_count} IPs in ${network} with ${CONFIG[scan_workers]} workers..."

    # Export functions and variables needed by the subshells.
    export -f scan::worker core::log
    export -A CONFIG
    export LOG_LEVEL

    local counter=0
    echo "$ip_list" | while read -r ip; do
        # Run worker in the background.
        ( scan::worker "$ip" ) &
        
        # Simple parallel throttle.
        ((counter++))
        if (( counter % ${CONFIG[scan_workers]} == 0 )); then
            wait
        fi
    done
    wait # Wait for the last batch of jobs to finish.
}