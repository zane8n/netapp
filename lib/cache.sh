#!/bin/bash
#
# NetSnmp Library - Cache Functions
#

cache::is_valid() {
    local cache_file="${G_PATHS[hosts_cache]}"; if [[ ! -f "$cache_file" || ! -s "$cache_file" ]]; then core::log_debug "Cache invalid: Missing or empty."; return 1; fi
    local cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0) ))
    if [[ ${cache_age} -gt ${G_CONFIG[cache_ttl]} ]]; then core::log_debug "Cache invalid: Stale."; return 1; fi; return 0;
}

cache::clear() {
    ui::print_header "Clearing Cache"; local cache_files=("${G_PATHS[hosts_cache]}" "${G_PATHS[ap_cache]}")
    for file in "${cache_files[@]}"; do
        if [[ -f "$file" ]]; then rm -f "$file" && ui::print_success "Removed ${file}" || ui::print_error "Failed to remove ${file}."; fi
    done
}

cache::show_stats() {
    ui::print_header "Cache Information"; local cache_file="${G_PATHS[hosts_cache]}"; if [[ ! -f "$cache_file" ]]; then ui::print_error "Cache file not found."; return 1; fi
    local total_hosts; total_hosts=$(wc -l < "$cache_file" | tr -d ' '); local last_modified; last_modified=$(date -r "$cache_file"); local file_size; file_size=$(du -h "$cache_file" | cut -f1)
    local age_s=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file") )); local age_m=$(( age_s / 60 ))
    echo "  File Location:    ${cache_file}"; echo "  Total Devices:    ${total_hosts}"; echo "  File Size:        ${file_size}"; echo "  Last Updated:     ${last_modified} (${age_m} mins ago)"
    if cache::is_valid; then echo -e "  Status:           ${C_GREEN}Valid${C_RESET}"; else echo -e "  Status:           ${C_RED}Stale${C_RESET}"; fi
}

cache::search() {
    local pattern="$1"; local cache_file="${G_PATHS[hosts_cache]}"; if [[ ! -s "$cache_file" ]]; then ui::print_error "Cache is empty."; return 1; fi
    local results; if [[ -z "$pattern" ]]; then results=$(cat "$cache_file"); else results=$(grep -i "$pattern" "$cache_file"); fi
    local found_count; found_count=$(echo -n "$results" | wc -l | tr -d ' '); if [[ ${found_count} -eq 0 ]]; then ui::print_error "No devices found matching '${pattern}'."; return 1; fi
    ui::print_header "Search Results (${found_count} found)"; printf "%-18s %-40s %s\n" "IP ADDRESS" "HOSTNAME" "SERIAL NUMBER"; echo "------------------ ---------------------------------------- --------------------"
    echo "$results" | while read -r ip hostname serial; do hostname="${hostname//\"/}"; serial="${serial//\"/}"; printf "%-18s %-40s %s\n" "$ip" "$hostname" "$serial"; done
}

cache::search_aps() { ui::print_error "Feature not implemented yet."; }