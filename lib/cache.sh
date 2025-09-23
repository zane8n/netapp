#!/bin/bash
#
# NetSnmp - Cache Library
# Description: Manages all interactions with the cache files, including
# updates, searches, and cleaning.

# Checks if the main device cache is present and not stale.
is_cache_valid() {
    [[ -s "$CACHE_FILE" ]] && \
    (( $(date +%s) - $(stat -c %Y "$CACHE_FILE") < ${CONFIG[cache_ttl]:-3600} ))
}

# Updates the main device cache by running a parallel scan.
# REFACTOR: This function is now a high-level wrapper. The complex logic has been
# moved to scan.sh and worker.sh. It properly handles temporary files and permissions.
update_cache() {
    local networks="${1:-${CONFIG[networks]}}"
    if [[ -z "$networks" ]]; then
        log_error "No networks to scan. Please define them in '$CONFIG_FILE' or use the -S flag."
        return 1
    fi

    log_info "Starting network scan..."
    log_info "Networks: $networks"
    log_info "Communities: ${CONFIG[communities]}"

    local temp_cache;
    temp_cache=$(mktemp) || { log_error "Could not create temp file for cache."; return 1; }

    # The run_parallel_scan function will output all found devices to stdout
    run_parallel_scan "$networks" > "$temp_cache"

    local found_count;
    found_count=$(wc -l < "$temp_cache")

    if (( found_count > 0 )); then
        # Atomically replace the old cache with the new one
        # Use sudo if we are running as root to set correct permissions
        if [[ $EUID -eq 0 ]]; then
            install -m 644 "$temp_cache" "$CACHE_FILE"
        else
            mv "$temp_cache" "$CACHE_FILE"
        fi
        log_info "Scan complete. Found and cached $found_count devices."
    else
        log_error "Scan complete. No responsive devices found."
        rm -f "$temp_cache"
        return 1
    fi
}


# Searches the main cache for a pattern.
# REFACTOR: Simplified search logic. It now case-insensitively matches the
# pattern against the entire line, making it easy to search by IP, name, or serial.
search_cache() {
    local pattern="$1"

    if [[ ! -s "$CACHE_FILE" ]]; then
        log_error "Cache is empty. Please run 'netsnmp --update' first."
        return 1
    fi

    log_info "Searching for devices matching '${pattern}'..."
    # Use grep for efficient, case-insensitive searching
    grep -i "$pattern" "$CACHE_FILE" | while IFS='|' read -r ip name serial mac descr; do
        # Pretty print the output
        printf "IP:       %s\n" "$ip"
        printf "Name:     %s\n" "$name"
        [[ -n "$serial" ]] && printf "Serial:   %s\n" "$serial"
        [[ -n "$mac" ]] && printf "MAC:      %s\n" "$mac"
        echo "----------------------------------------"
    done

    # Check if grep found anything
    if ! grep -iq "$pattern" "$CACHE_FILE"; then
        log_error "No devices found matching '$pattern'."
    fi
}

# Wipes the cache files.
clear_cache() {
    log_info "Clearing all cache files..."
    rm -f "$CACHE_FILE" "$AP_CACHE_FILE"
    log_info "Cache cleared."
}