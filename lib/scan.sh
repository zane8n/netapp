#!/bin/bash
#
# NetSnmp Library - Scan Function
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
        scan::generate_ip_list "$network"; return;
    fi
    
    local fping_cmd="fping"
    # Elevate fping if we are not root but can use sudo without a password
    if [[ $EUID -ne 0 ]] && command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
        core::log_debug "Attempting to use sudo for fping for better permissions."
        fping_cmd="sudo -n fping"
    fi

    local delay="${G_CONFIG[scan_delay]}"
    local timeout="${G_CONFIG[ping_timeout]}000"
    
    if [[ "${network}" == */* ]]; then
        $fping_cmd -a -g "${network}" -q -i "${delay}" -t "${timeout}" 2>/dev/null
    elif [[ "${network}" == *-* ]]; then
        local base_ip end_range start_ip end_ip
        base_ip="${network%-*}"; end_range="${network#*-}"
        start_ip="${base_ip}"; end_ip="${base_ip%.*}.${end_range}"
        $fping_cmd -a -g "${start_ip}" "${end_ip}" -q -i "${delay}" -t "${timeout}" 2>/dev/null
    else
        $fping_cmd -a "${network}" -q -i "${delay}" -t "${timeout}" 2>/dev/null
    fi
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
    
    # Get the community string ONCE before the loop.
    local community_string="${G_CONFIG[communities]}"

    while read -r ip; do
        # Execute each task in a new, fully-sourced bash shell.
        # Pass the IP and community string as direct, foolproof arguments ($1, $2).
        bash -c '
            # Source the libraries to build the environment
            source "${LIB_DIR}/core.sh"
            source "${LIB_DIR}/discovery.sh"

            # Call the discovery function with the arguments passed to this shell
            result=$(discovery::resolve_snmp_details "$1" "$2")
            
            if [[ -n "$result" ]]; then
                hostname=$(echo "$result" | cut -d"|" -f1)
                serial=$(echo "$result" | cut -d"|" -f2)
                echo "$1 \"$hostname\" \"$serial\""
            fi
        ' _ "$ip" "$community_string" & # The "_" is a placeholder for $0
        
        ((job_count++))
        if [[ ${job_count} -ge ${workers} ]]; then
            wait -n; ((job_count--));
        fi
    done
    wait
}

# --- Main Scan Functions ---

# Orchestrates a full cache rebuild.
scan::update_cache() {
    core::log "Starting network scan (mode: full rebuild)..."
    core::log "  Networks:    ${G_CONFIG[subnets]}"
    core::log "  Scan Mode:   ${G_CONFIG[scan_mode]}"

    local temp_cache_file; temp_cache_file=$(mktemp)
    
    # --- NEW: Branching logic based on scan_mode ---
    if [[ "${G_CONFIG[scan_mode]}" == "snmp" ]]; then
        # SNMP-only mode: skip ICMP, query all IPs directly.
        local all_ips_file; all_ips_file=$(mktemp)
        core::log "Phase 1: Generating full IP list for SNMP-only scan..."
        for network in ${G_CONFIG[subnets]}; do
            scan::generate_ip_list "${network}" >> "${all_ips_file}"
        done
        local total_ips; total_ips=$(wc -l < "$all_ips_file" | tr -d ' ')
        core::log "Generated ${total_ips} IPs to query."

        core::log "Phase 2: Querying SNMP on all generated IPs..."
        < "${all_ips_file}" scan::parallel_snmp_query > "${temp_cache_file}"
        rm "${all_ips_file}"
    else
        # ICMP mode (default): ping first, then query.
        local live_hosts_file; live_hosts_file=$(mktemp)
        core::log "Phase 1: Discovering live hosts via ICMP..."
        for network in ${G_CONFIG[subnets]}; do
            scan::_find_live_hosts "${network}" >> "${live_hosts_file}"
        done
        
        local live_host_count; live_host_count=$(wc -l < "${live_hosts_file}" | tr -d ' ')
        core::log "Found ${live_host_count} potentially live hosts."

        core::log "Phase 2: Querying SNMP on live hosts..."
        if [[ ${live_host_count} -gt 0 ]]; then
            < "${live_hosts_file}" scan::parallel_snmp_query > "${temp_cache_file}"
        fi
        rm "${live_hosts_file}"
    fi
    
    local total_found; total_found=$(wc -l < "${temp_cache_file}")
    
    mv "${temp_cache_file}" "${G_PATHS[hosts_cache]}"
    
    if [[ ${total_found} -gt 0 ]]; then
        core::log "Scan complete. Found ${total_found} devices with SNMP response."
        ui::print_success "Cache updated successfully."
    else
        core::log_error "Scan complete. No devices responded to SNMP."
        ui::show_troubleshooting_tips
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

# --- Neighbor Discovery Orchestration ---

# Task for a single switch discovery. Called by the parallel engine.
# It tries all configured protocols (e.g., cdp, then lldp).
scan::_discover_neighbors_task() {
    local switch_ip="$1"
    local switch_hostname="$2"
    
    local -a communities; read -r -a communities <<< "${G_CONFIG[communities]}"
    local -a protocols; read -r -a protocols <<< "${G_CONFIG[discovery_protocols]}"
    
    for protocol in "${protocols[@]}"; do
        for community in "${communities[@]}"; do
            core::log_debug "Querying ${switch_hostname} (${switch_ip}) for neighbors via ${protocol}..."
            
            local results
            if [[ "$protocol" == "cdp" ]]; then
                results=$(discovery::get_cdp_neighbors "$switch_ip" "$community")
            elif [[ "$protocol" == "lldp" ]]; then
                results=$(discovery::get_lldp_neighbors "$switch_ip" "$community")
            fi
            
            if [[ -n "$results" ]]; then
                local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                # Add switch info, protocol, and timestamp to each result line
                while read -r line; do
                    # Input format: IP|HOSTNAME|PLATFORM|PORT
                    # Output format: IP "HOSTNAME" "PLATFORM" SWITCH_IP "PORT" PROTOCOL "TIMESTAMP"
                    IFS='|' read -r ip host platform port <<< "$line"
                    echo "$ip \"$host\" \"$platform\" $switch_ip \"$port\" $protocol \"$timestamp\""
                done <<< "$results"
                return 0 # Success, don't try other protocols/communities
            fi
        done
    done
}
export -f scan::_discover_neighbors_task
export -f discovery::get_cdp_neighbors
export -f discovery::get_lldp_neighbors
export -A G_CONFIG

# Manages the parallel discovery process across all potential switches.
scan::update_ap_cache() {
    if [[ ! -s "${G_PATHS[hosts_cache]}" ]]; then
        ui::print_error "Hosts cache is empty. Run 'netsnmp --update' first."; return 1;
    fi

    ui::print_header "Starting Neighbor Discovery Scan"
    core::log "Protocols enabled: ${G_CONFIG[discovery_protocols]}"

    local temp_ap_cache; temp_ap_cache=$(mktemp)
    
    # Use a parallel job manager to query all switches
    local workers="${G_CONFIG[scan_workers]}"
    local job_count=0
    
    # Read switches from the main host cache
    while read -r switch_ip switch_hostname _; do
        # Heuristic: A device with a serial number is likely a switch/router
        # This avoids querying end-user PCs.
        scan::_discover_neighbors_task "$switch_ip" "$switch_hostname" &>> "$temp_ap_cache" &
        
        ((job_count++))
        if [[ ${job_count} -ge ${workers} ]]; then
            wait -n; ((job_count--));
        fi
    done < <(grep -v '""' "${G_PATHS[hosts_cache]}") # Only query devices with a serial number
    
    wait
    
    local total_found; total_found=$(wc -l < "$temp_ap_cache" | tr -d ' ')
    
    # Atomically replace the old AP cache
    mv "$temp_ap_cache" "${G_PATHS[ap_cache]}"
    
    ui::print_success "Discovery complete. Found ${total_found} neighbors."
    ui::print_info "Cache updated: ${G_PATHS[ap_cache]}"
    ui::print_info "View results with 'netsnmp --aps'."
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