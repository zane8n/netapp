#!/bin/bash
#
# NetSnmp Library - Scan Functions
#
scan::generate_ip_list() {
    local network_string="$1"; core::log_debug "Generating IP list for: ${network_string}"
    if [[ "${network_string}" == */24 ]]; then
        local base_ip; base_ip=$(echo "${network_string}" | cut -d'/' -f1 | sed 's/\.[0-9]*$//'); for i in {1..254}; do echo "${base_ip}.${i}"; done
    elif [[ "${network_string}" == *-* ]]; then
        local base_ip end_range start_octet base_network; base_ip="${network_string%-*}"; end_range="${network_string#*-}"; start_octet="${base_ip##*.}"; base_network="${base_ip%.*}"
        if ! [[ "${start_octet}" =~ ^[0-9]+$ && "${end_range}" =~ ^[0-9]+$ && ${start_octet} -le ${end_range} && ${end_range} -le 254 ]]; then core::log_error "Invalid IP range: ${network_string}"; return 1; fi
        seq "${start_octet}" "${end_range}" | while read -r i; do echo "${base_network}.${i}"; done
    elif [[ "${network_string}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then echo "${network_string}";
    else core::log_error "Unsupported network format: ${network_string}"; return 1; fi
}

scan::_find_live_hosts() {
    local network="$1"; core::log_debug "Finding live hosts in ${network}..."; if ! core::is_command_available "fping"; then scan::generate_ip_list "$network"; return; fi
    local fping_cmd="fping"; if [[ $EUID -ne 0 ]] && command -v sudo >/dev/null && sudo -n true 2>/dev/null; then core::log_debug "Using sudo for fping."; fping_cmd="sudo -n fping"; fi
    local delay="${G_CONFIG[scan_delay]}"; local timeout="${G_CONFIG[ping_timeout]}000"
    if [[ "${network}" == */* ]]; then $fping_cmd -a -g "${network}" -q -i "${delay}" -t "${timeout}" 2>/dev/null;
    elif [[ "${network}" == *-* ]]; then local base_ip end_range start_ip end_ip; base_ip="${network%-*}"; end_range="${network#*-}"; start_ip="${base_ip}"; end_ip="${base_ip%.*}.${end_range}"; $fping_cmd -a -g "${start_ip}" "${end_ip}" -q -i "${delay}" -t "${timeout}" 2>/dev/null;
    else $fping_cmd -a "${network}" -q -i "${delay}" -t "${timeout}" 2>/dev/null; fi
}

scan::parallel_snmp_query() {
    local workers="${G_CONFIG[scan_workers]}"
    local worker_script="${LIB_DIR}/worker.sh"
    if [[ ! -x "$worker_script" ]]; then core::log_error "Worker script is not executable: ${worker_script}"; return 1; fi
    xargs -I {} -P "${workers}" bash "$worker_script" {}
}

scan::update_cache() {
    core::log "Starting network scan (mode: full rebuild)..."
    core::log "  Networks:    ${G_CONFIG[subnets]}"; core::log "  Scan Mode:   ${G_CONFIG[scan_mode]}"
    local temp_cache_file; temp_cache_file=$(mktemp)
    if [[ "${G_CONFIG[scan_mode]}" == "snmp" ]]; then
        local all_ips_file; all_ips_file=$(mktemp)
        core::log "Phase 1: Generating full IP list for SNMP-only scan..."
        for network in ${G_CONFIG[subnets]}; do scan::generate_ip_list "${network}" >> "${all_ips_file}"; done
        local total_ips; total_ips=$(wc -l < "$all_ips_file" | tr -d ' '); core::log "Generated ${total_ips} IPs to query."
        core::log "Phase 2: Querying SNMP on all generated IPs..."
        < "${all_ips_file}" scan::parallel_snmp_query > "${temp_cache_file}"; rm "${all_ips_file}"
    else
        local live_hosts_file; live_hosts_file=$(mktemp)
        core::log "Phase 1: Discovering live hosts via ICMP..."
        for network in ${G_CONFIG[subnets]}; do scan::_find_live_hosts "${network}" >> "${live_hosts_file}"; done
        local live_host_count; live_host_count=$(wc -l < "${live_hosts_file}" | tr -d ' '); core::log "Found ${live_host_count} potentially live hosts."
        core::log "Phase 2: Querying SNMP on live hosts..."
        if [[ ${live_host_count} -gt 0 ]]; then < "${live_hosts_file}" scan::parallel_snmp_query > "${temp_cache_file}"; fi
        rm "${live_hosts_file}"
    fi
    local total_found; total_found=$(wc -l < "$temp_cache_file" | tr -d ' ')
    mv "${temp_cache_file}" "${G_PATHS[hosts_cache]}"
    if [[ ${total_found} -gt 0 ]]; then core::log "Scan complete. Found ${total_found} devices."; ui::print_success "Cache updated."; else
        core::log_error "Scan complete. No devices responded to SNMP."; ui::show_troubleshooting_tips; fi
}

scan::update_cache_incremental() { ui::print_error "Feature not implemented yet."; }
scan::update_ap_cache() { ui::print_error "Feature not implemented yet."; }
scan::scan_single_host() { ui::print_error "Feature not implemented yet."; }
scan::test_ip_generation() { ui::print_error "Feature not implemented yet."; }
scan::test_functionality() { ui::print_error "Feature not implemented yet."; }