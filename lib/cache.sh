#!/bin/bash
#
# NetSnmp Library - Cache Function
# Description: Manages all cache operations like reading, writing, and searching.
#

# --- Cache Validation and State ---

# Checks if the cache is present, non-empty, and not expired.
# Returns 0 if valid, 1 otherwise.
cache::is_valid() {
    local cache_file="${G_PATHS[hosts_cache]}"
    if [[ ! -f "$cache_file" || ! -s "$cache_file" ]]; then
        core::log_debug "Cache invalid: File does not exist or is empty."
        return 1
    fi
    
    local cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0) ))
    local cache_ttl="${G_CONFIG[cache_ttl]}"
    
    if [[ ${cache_age} -gt ${cache_ttl} ]]; then
        core::log_debug "Cache invalid: Stale (age: ${cache_age}s > ttl: ${cache_ttl}s)."
        return 1
    fi
    
    core::log_debug "Cache is valid."
    return 0
}

# Deletes all cache files.
cache::clear() {
    ui::print_header "Clearing Cache"
    local cache_files=("${G_PATHS[hosts_cache]}" "${G_PATHS[ap_cache]}")
    for file in "${cache_files[@]}"; do
        if [[ -f "$file" ]]; then
            if rm -f "$file"; then
                ui::print_success "Removed ${file}"
            else
                ui::print_error "Failed to remove ${file}. Check permissions."
                return 1
            fi
        else
            ui::print_info "Cache file not found, skipping: ${file}"
        fi
    done
}


# --- Cache Information and Display ---

# Shows detailed statistics about the cache.
cache::show_stats() {
    ui::print_header "Cache Information"
    local cache_file="${G_PATHS[hosts_cache]}"
    
    if [[ ! -f "$cache_file" ]]; then
        ui::print_error "Cache file does not exist: ${cache_file}"
        ui::print_info "Run 'netsnmp --update' to create it."
        return 1
    fi
    
    local total_hosts; total_hosts=$(wc -l < "$cache_file" | tr -d ' ')
    local last_modified; last_modified=$(date -r "$cache_file")
    local file_size; file_size=$(du -h "$cache_file" | cut -f1)
    local age_s=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file") ))
    local age_m=$(( age_s / 60 ))
    
    echo "  File Location:    ${cache_file}"
    echo "  Total Devices:    ${total_hosts}"
    echo "  File Size:        ${file_size}"
    echo "  Last Updated:     ${last_modified} (${age_m} minutes ago)"
    
    if cache::is_valid; then
        echo -e "  Status:           ${C_GREEN}Valid${C_RESET}"
    else
        echo -e "  Status:           ${C_RED}Stale / Expired${C_RESET}"
    fi
    
    if [[ ${total_hosts} -gt 0 ]]; then
        ui::print_header "First 5 Entries"
        head -5 "$cache_file" | while read -r ip host serial; do
            echo "  → ${ip} (${host//\"/})"
        done
    fi
}

# Searches the cache for a given pattern.
# $1: The search pattern. If empty, lists all devices.
cache::search() {
    local pattern="$1"
    local cache_file="${G_PATHS[hosts_cache]}"

    if [[ ! -s "$cache_file" ]]; then
        ui::print_error "Cache is empty. Cannot perform search."; return 1;
    fi

    local results
    if [[ -z "$pattern" ]]; then
        results=$(cat "$cache_file")
    else
        # Case-insensitive search across the entire line
        results=$(grep -i "$pattern" "$cache_file")
    fi
    
    local found_count; found_count=$(echo "$results" | wc -l | tr -d ' ')

    if [[ ${found_count} -eq 0 ]]; then
        ui::print_error "No devices found matching '${pattern}'."
        return 1
    fi
    
    ui::print_header "Search Results (${found_count} found)"
    printf "%-18s %-40s %s\n" "IP ADDRESS" "HOSTNAME" "SERIAL NUMBER"
    echo "------------------ ---------------------------------------- --------------------"
    
    echo "$results" | while read -r ip hostname serial; do
        # Clean quotes for display
        hostname="${hostname//\"/}"
        serial="${serial//\"/}"
        printf "%-18s %-40s %s\n" "$ip" "$hostname" "$serial"
    done
}


# --- Cache Modification ---

# Merges new scan results into the existing cache for incremental updates.
# $1: Path to a temporary file containing new scan results.
cache::merge_updates() {
    local results_file="$1"
    local cache_file="${G_PATHS[hosts_cache]}"
    
    if [[ ! -s "$results_file" ]]; then
        core::log "Incremental scan found no responsive devices to update."; return 0;
    fi
    
    local new_count=0
    local updated_count=0
    
    # Create the cache file if it doesn't exist
    touch "$cache_file"
    
    while read -r ip hostname serial; do
        # Check if the IP address already exists in the cache (use -q for quiet)
        if grep -q "^${ip} " "$cache_file"; then
            # IP exists, so update the line in place with sed.
            # Using a temporary extension for macOS compatibility.
            sed -i.bak "s|^${ip} .*|${ip} ${hostname} ${serial}|" "$cache_file"
            ((updated_count++))
        else
            # IP is new, so append it to the cache.
            echo "${ip} ${hostname} ${serial}" >> "$cache_file"
            ((new_count++))
        fi
    done < "$results_file"
    
    # Clean up sed backup file
    rm -f "${cache_file}.bak"
    
    core::log "Incremental scan merge complete."
    ui::print_success "Added ${new_count} new devices and updated ${updated_count} existing devices."
}

# --- AP Cache Functions ---

# Searches and displays the AP/neighbor cache.
# $1: The search pattern. If empty, lists all devices.
cache::search_aps() {
    local pattern="$1"
    local cache_file="${G_PATHS[ap_cache]}"

    if [[ ! -s "$cache_file" ]]; then
        ui::print_error "Neighbor cache is empty. Run 'netsnmp --discover-aps' first."; return 1;
    fi

    local results;
    if [[ -z "$pattern" ]]; then
        results=$(cat "$cache_file")
    else
        results=$(grep -i "$pattern" "$cache_file")
    fi
    
    local found_count; found_count=$(echo "$results" | wc -l | tr -d ' ')
    if [[ ${found_count} -eq 0 ]]; then
        ui::print_error "No neighbors found matching '${pattern}'."; return 1;
    fi
    
    ui::print_header "Neighbor Discovery Results (${found_count} found)"
    printf "%-18s %-30s %-18s %-25s %s\n" "NEIGHBOR IP" "HOSTNAME" "CONNECTED TO" "PORT" "PROTOCOL"
    echo "------------------ ------------------------------ ------------------ ------------------------- --------"
    
    echo "$results" | while read -r ip host platform switch_ip port protocol timestamp; do
        # Clean quotes for display
        host="${host//\"/}"; port="${port//\"/}"
        printf "%-18s %-30s %-18s %-25s %s\n" "$ip" "$host" "$switch_ip" "$port" "$protocol"
    done
}