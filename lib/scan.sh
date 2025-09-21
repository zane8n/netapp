#!/bin/bash
#
# NetSnmp Library - Scan Functions
# Description: Handles network scanning, IP generation, and host discovery.
#

# --- IP Generation ---

scan::generate_ip_list() {
    local network_string="$1"
    core::log_debug "Generating IP list for: ${network_string}"
    
    if [[ "${network_string}" == */24 ]]; then
        local base_ip
        base_ip=$(echo "${network_string}" | cut -d'/' -f1 | sed 's/\.[0-9]*$//')
        for i in {1..254}; do echo "${base_ip}.${i}"; done
    elif [[ "${network_string}" == *-* ]]; then
        local base_ip end_range start_octet base_network
        base_ip="${network_string%-*}"; end_range="${network_string#*-}"
        start_octet="${base_ip##*.}"; base_network="${base_ip%.*}"
        if ! [[ "${start_octet}" =~ ^[0-9]+$ && "${end_range}" =~ ^[0-9]+$ && ${start_octet} -le ${end_range} && ${end_range} -le 254 ]]; then
            core::log_error "Invalid IP range format: ${network_string}"; return 1
        fi
        seq "${start_octet}" "${end_range}" | while read -r i; do echo "${base_network}.${i}"; done
    elif [[ "${network_string}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "${network_string}"
    else
        core::log_error "Unsupported network format: ${network_string}"; return 1
    fi
}

# --- Host Scanning ---

# Efficiently finds live hosts in a network using fping.
scan::_find_live_hosts() {
    local network="$1"
    core::log_debug "Finding live hosts in ${network}..."

    if ! core::is_command_available "fping"; then
        core::log_debug "fping not found, falling back to scanning all IPs individually."
        scan::generate_ip_list "$network"
        return
    fi
    
    # -a: show alive hosts, -g: generate from network, -q: quiet
    # -i: interval between pings in ms (stealth), -t: timeout in ms
    local delay="${G_CONFIG[scan_delay]}"
    local timeout="${G_CONFIG[ping_timeout]}000"
    
    fping -a -g "${network}" -q -i "${delay}" -t "${timeout}" 2>/dev/null
}


# Task for a single SNMP query. Called by the parallel engine.
scan::_snmp_query_task() {
    local ip="$1"
    core::log_debug "Querying SNMP for IP: $ip"
    
    # This now calls the optimized multi-OID query function
    local result
    result=$(discovery::resolve_snmp_details "$ip")
    
    if [[ -n "$result" ]]; then
        # Result format is "HOSTNAME|SERIAL"
        local hostname serial
        hostname=$(echo "$result" | cut -d'|' -f1)
        serial=$(echo "$result" | cut -d'|' -f2)
        echo "$ip \"$hostname\" \"$serial\""
    fi
}
# Export the task and dependencies for sub-shells
export -f scan::_snmp_query_task
export -f discovery::resolve_snmp_details
export -f core::log_debug
export -A G_CONFIG

# --- Parallel Scan Engine ---

# A robust, pure Bash parallel job manager.
# Feeds a list of IPs to the SNMP query task.
scan::parallel_snmp_query() {
    local workers="${G_CONFIG[scan_workers]}"
    local job_count=0
    
    # Read IPs from standard input
    while read -r ip; do
        # Launch the task in the background
        scan::_snmp_query_task "$ip" &
        
        ((job_count++))
        # When the number of jobs reaches the worker limit, wait for any job to finish
        if [[ ${job_count} -ge ${workers} ]]; then
            wait -n # Waits for the next job to terminate
            ((job_count--))
        fi
    done
    
    # Wait for all remaining background jobs to complete
    wait
}

# --- Main Scan Functions ---

# Orchestrates a full cache rebuild.
scan::update_cache() {
    local custom_networks="${1:-${G_CONFIG[subnets]}}"
    local custom_communities="${2:-${G_CONFIG[communities]}}"

    if [[ -z "$custom_networks" || -z "$custom_communities" ]]; then
        core::log_error "Config incomplete. No networks or communities defined."; return 1;
    fi
    
    core::log "Starting network scan (mode: full rebuild)..."
    core::log "  Networks:    ${custom_networks}"
    core::log "  Workers:     ${G_CONFIG[scan_workers]}"

    local temp_cache_file; temp_cache_file=$(mktemp)
    
    G_CONFIG[subnets]="$custom_networks"
    G_CONFIG[communities]="$custom_communities"
    export G_CONFIG

    # Stage 1: Discover all live hosts across all networks
    local live_hosts_file; live_hosts_file=$(mktemp)
    core::log "Phase 1: Discovering live hosts via ICMP..."
    for network in ${G_CONFIG[subnets]}; do
        scan::_find_live_hosts "${network}" >> "${live_hosts_file}"
    done
    
    local live_host_count; live_host_count=$(wc -l < "${live_hosts_file}")
    core::log "Found ${live_host_count} potentially live hosts."

    # Stage 2: Query SNMP on live hosts in parallel
    core::log "Phase 2: Querying SNMP on live hosts..."
    if [[ ${live_host_count} -gt 0 ]]; then
        < "${live_hosts_file}" scan::parallel_snmp_query > "${temp_cache_file}"
    fi
    
    rm "${live_hosts_file}"
    local total_found; total_found=$(wc -l < "${temp_cache_file}")
    
    # Atomically replace the old cache with the new one
    mv "${temp_cache_file}" "${G_PATHS[hosts_cache]}"
    
    if [[ ${total_found} -gt 0 ]]; then
        core::log "Scan complete. Found ${total_found} devices with SNMP response."
        ui::print_success "Cache updated successfully."
    else
        core::log_error "Scan complete. No devices responded to SNMP."; ui::show_troubleshooting_tips
    fi
}

# Performs an incremental update of the cache.
scan::update_cache_incremental() {
    core::log "Starting network scan (mode: incremental)..."
    
    # This follows the same scan logic as a full update
    # The key difference is how the results are merged into the cache
    local temp_results; temp_results=$(mktemp)
    
    G_CONFIG[subnets]="${1:-${G_CONFIG[subnets]}}"
    G_CONFIG[communities]="${2:-${G_CONFIG[communities]}}"
    export G_CONFIG

    local live_hosts_file; live_hosts_file=$(mktemp)
    core::log "Phase 1: Discovering live hosts..."
    for network in ${G_CONFIG[subnets]}; do
        scan::_find_live_hosts "${network}" >> "${live_hosts_file}"
    done
    
    core::log "Phase 2: Querying SNMP..."
    < "${live_hosts_file}" scan::parallel_snmp_query > "${temp_results}"
    rm "${live_hosts_file}"
    
    # Merge results into the main cache
    cache::merge_updates "${temp_results}"
    rm "${temp_results}"
}

# Placeholder for AP discovery
scan::update_ap_cache() {
    ui::print_error "AP discovery feature is not yet fully implemented."
}

# --- Standalone and Test Functions ---

scan::scan_single_host() {
    local ip="$1"
    if [[ -z "$ip" ]]; then
        core::log_error "No IP address provided."; return 1;
    fi

    ui::print_header "Scanning Single Host: $ip"
    local result; result=$(scan::_snmp_query_task "$ip")

    if [[ -n "$result" ]]; then
        local hostname serial
        hostname=$(echo "$result" | cut -d'"' -f2)
        serial=$(echo "$result" | cut -d'"' -f4)
        echo "  Status:      Online (SNMP Response)"
        echo "  Hostname:    ${hostname}"
        echo "  Serial:      ${serial:-Not Found}"
    else
        # If SNMP fails, try a simple ping
        if ping -c1 -W1 "$ip" &>/dev/null; then
            echo "  Status:      Online (Ping OK, no SNMP)"
        else
            echo "  Status:      Offline"
        fi
    fi
}

scan::test_ip_generation() {
    local network="$1"
    if [[ -z "$network" ]]; then
        core::log_error "No network provided."; return 1;
    fi
    ui::print_header "Testing IP Generation for: $network"
    local ip_list; ip_list=$(scan::generate_ip_list "$network")
    if [[ -n "$ip_list" ]]; then
        echo "$ip_list"
        echo ""; ui::print_success "Total IPs generated: $(echo "$ip_list" | wc -l)"
    else
        ui::print_error "Failed to generate IP list."
    fi
}

scan::test_functionality() {
    # This function remains useful and unchanged.
    ui::print_header "Testing Scan Functionality"
    echo "1. Checking dependencies...";
    core::is_command_available "snmpget" && echo "   [✓] snmpget: Found" || echo "   [✗] snmpget: Not Found"
    core::is_command_available "fping" && echo "   [✓] fping:   Found (High Performance)" || echo "   [!] fping:   Not Found (Reduced Performance)"
    echo -e "\n2. Checking configuration..."
    [[ -n "${G_CONFIG[subnets]}" ]] && echo "   [✓] Networks:    Configured" || echo "   [✗] Networks:    Not configured"
    [[ -n "${G_CONFIG[communities]}" ]] && echo "   [✓] Communities: Configured" || echo "   [✗] Communities: Not configured"
    echo -e "\n3. Checking permissions..."
    touch "${G_PATHS[cache_dir]}/.perm_test" 2>/dev/null && { echo "   [✓] Cache Write: OK"; rm "${G_PATHS[cache_dir]}/.perm_test"; } || echo "   [✗] Cache Write: Failed"
}