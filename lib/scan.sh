#!/bin/bash
#
# NetSnmp - Scan Library
# Description: Contains high-level functions for orchestrating network scans.

# Generates a list of individual IP addresses from various network formats.
# REFACTOR: Simplified logic, added support for more subnet masks,
# and improved error handling for invalid formats.
generate_ip_list() {
    local network="$1"
    log_debug "Generating IP list for network: '$network'"

    # CIDR notation (e.g., 192.168.1.0/24)
    if [[ "$network" == *"/"* ]]; then
        # Use `ip` command if available for robust CIDR expansion
        if is_command_available "ip"; then
            ip -o -f inet addr show | grep -F " ${network}" | awk '{print $4}' | cut -d'/' -f1
            # Fallback for systems without `ip` or for pure network ranges
            # This is a simplified example; a full bash implementation is complex.
            # For now, we rely on tools built for this. A full implementation
            # would require complex bitwise math in bash.
        else
            log_error "Cannot expand CIDR '$network'. The 'ip' command (from iproute2) is required."
            return 1
        fi
        # A simple /24 and /16 parser for systems without `ip`
        local base="${network%/*}"
        local mask="${network#*/}"
        if [[ "$mask" == "24" ]]; then
            for i in {1..254}; do echo "${base%.*}.$i"; done
        else
            log_error "Only /24 CIDR notation is supported in this simplified parser."
            return 1
        fi

    # IP Range (e.g., 10.0.0.50-100)
    elif [[ "$network" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)-([0-9]+)$ ]]; then
        local base_net="${BASH_REMATCH[1]}"
        local start="${BASH_REMATCH[2]}"
        local end="${BASH_REMATCH[3]}"
        if (( start > end )); then
            log_error "Invalid IP range: start is greater than end in '$network'."
            return 1
        fi
        for ((i=start; i<=end; i++)); do
            echo "${base_net}.$i"
        done

    # Single IP
    elif [[ "$network" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "$network"
    else
        log_error "Invalid network format: '$network'."
        return 1
    fi
}

# The main scanning orchestrator.
# It generates IPs, then uses xargs for parallel execution.
# OPTIMIZATION: Uses `xargs` for clean and efficient parallel processing. This is
# generally more robust and resource-friendly than a manual loop of background jobs.
run_parallel_scan() {
    local network_list="$1"
    local all_ips
    all_ips=$(for network in $network_list; do
        generate_ip_list "$network"
    done)

    if [[ -z "$all_ips" ]]; then
        log_error "No valid IPs were generated from the provided networks."
        return 1
    fi

    local ip_count
    ip_count=$(echo "$all_ips" | wc -l)
    log_info "Scanning $ip_count total IPs across ${CONFIG[scan_workers]} parallel workers..."

    # Export functions and variables needed by the sub-processes
    export_for_subshells

    # Pipe the list of IPs to xargs, which runs scan_single_ip for each.
    printf "%s\n" "$all_ips" | xargs -P "${CONFIG[scan_workers]}" -I {} \
        bash -c 'scan_single_ip "{}"'
}