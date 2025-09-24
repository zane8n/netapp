#!/bin/bash
#
# NetSnmp - Scan Library
# Description: Contains high-level functions for orchestrating network scans.

# Generates a list of individual IP addresses from various network formats.
# REFACTOR: Removed faulty CIDR logic and strengthened the pure bash parsers.
generate_ip_list() {
    local network="$1"
    log_debug "Generating IP list for network: '$network'"

    # CIDR notation (e.g., 192.168.1.0/24)
    if [[ "$network" == *"/"* ]]; then
        local base="${network%/*}"
        local mask="${network#*/}"
        # This parser is intentionally simple and only supports the most common /24 case.
        if [[ "$mask" == "24" && "$base" =~ ^([0-9]{1,3}\.){2}[0-9]{1,3}\.0$ ]]; then
            local prefix="${base%.*}"
            for i in {1..254}; do
                echo "${prefix}.$i"
            done
        else
            log_error "Invalid or unsupported CIDR format: '$network'. Only /24 subnets ending in .0 are supported."
            return 1
        fi

    # IP Range (e.g., 10.0.0.50-100)
    elif [[ "$network" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)-([0-9]+)$ ]]; then
        local base_net="${BASH_REMATCH[1]}"
        local start="${BASH_REMATCH[2]}"
        local end="${BASH_REMATCH[3]}"
        if (( start > 254 || end > 254 || start == 0 || end == 0 || start > end )); then
            log_error "Invalid IP range: '$network'. Octets must be 1-254 and start <= end."
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
# REFACTOR: Replaced xargs with a highly compatible and transparent bash job control loop.
# This makes debugging worker failures impossible to ignore.
run_parallel_scan() {
    local network_list="$1"
    local all_ips
    all_ips=$(for network in $network_list; do generate_ip_list "$network"; done)

    if [[ -z "$all_ips" ]]; then
        log_error "No valid IPs were generated. Please check your config for typos in the network ranges."
        return 1
    fi

    local ip_count
    ip_count=$(echo "$all_ips" | wc -l)
    log_info "Scanning $ip_count total IPs across ${CONFIG[scan_workers]} parallel workers..."

    # Export all necessary functions and variables for the sub-processes.
    export_for_subshells

    # --- Parallel Execution via Bash Job Control (Batch Method) ---
    local counter=0
    while read -r ip; do
        # Skip any empty lines that might have been generated
        [[ -z "$ip" ]] && continue

        # Run the worker function in the background for each IP.
        # Any errors from scan_single_ip will now print directly to your screen.
        scan_single_ip "$ip" &

        ((counter++))

        # When we reach the batch size, wait for all jobs in the current batch
        # to finish before starting the next one. This is simple and reliable.
        if (( counter % ${CONFIG[scan_workers]} == 0 )); then
            wait
            log_debug "Finished a batch of ${CONFIG[scan_workers]} workers."
        fi
    done <<< "$all_ips"

    # Final wait for any remaining jobs in the last, incomplete batch.
    wait
    log_debug "All scan workers have completed."
}