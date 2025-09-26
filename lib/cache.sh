#!/bin/bash
#
# NetSnmp Cache Library
# Manages the device cache files.

# Updates the main device cache by scanning networks.
# Usage: cache::update [CUSTOM_NETWORKS] [CUSTOM_COMMUNITIES]
function cache::update() {
    local custom_networks="$1"
    local custom_communities="$2"

    # Use custom values if provided, otherwise use config values.
    local scan_networks="${custom_networks:-${CONFIG[subnets]}}"
    [[ -z "$scan_networks" ]] && core::log "ERROR" "No networks to scan. Configure with --wizard." && exit 1
    
    # Temporarily override config for this run if custom values were passed.
    local old_communities="${CONFIG[communities]}"
    [[ -n "$custom_communities" ]] && CONFIG[communities]="$custom_communities"

    core::log "INFO" "Starting network scan..."
    core::log "VERBOSE" "Networks: ${scan_networks}"
    core::log "VERBOSE" "Communities: ${CONFIG[communities]}"

    local temp_cache; temp_cache=$(mktemp)
    
    # Iterate over all defined networks and scan them.
    for network in ${scan_networks}; do
        scan::network "$network" >> "$temp_cache"
    done
    
    # Atomically replace the old cache with the new one.
    mv "$temp_cache" "$CACHE_FILE"
    
    # Restore config if it was temporarily changed.
    CONFIG[communities]="$old_communities"

    local total_found; total_found=$(wc -l < "$CACHE_FILE" | tr -d ' ')
    core::log "INFO" "Scan complete. Found ${total_found} devices."
    core::log "INFO" "Cache updated: ${CACHE_FILE}"
}

# Searches the cache for a pattern.
# Usage: cache::search [PATTERN]
function cache::search() {
    local pattern="${1:-}"

    if [[ ! -s "$CACHE_FILE" ]]; then
        if cache::is_valid; then
            core::log "INFO" "Cache is empty. No devices found."
        else
            core::log "WARN" "Cache is stale or missing. Run 'netsnmp --update' to scan your network."
        fi
        return
    fi
    
    core::log "INFO" "Searching for '${pattern}' in device cache..."
    
    # Grep for pattern (case-insensitive) or cat all if no pattern.
    local results; results=$(grep -i "$pattern" "$CACHE_FILE" || true)

    if [[ -z "$results" ]]; then
        core::log "INFO" "No devices found matching your query."
    else
        core::log "RAW" "IP Address        Hostname              Serial"
        core::log "RAW" "----------------- --------------------- --------------------"
        echo "$results" | awk '{printf "%-17s %-21s %-20s\n", $1, $2, $3}'
    fi
}

# Checks if the main cache file is present and within its TTL.
function cache::is_valid() {
    [[ -s "$CACHE_FILE" ]] && \
    (( $(date +%s) - $(stat -c %Y "$CACHE_FILE") < ${CONFIG[cache_ttl]} ))
}

# Clears all cache files.
function cache::clear() {
    core::log "INFO" "Clearing all cache files..."
    rm -f "${CACHE_FILE}" "${AP_CACHE_FILE}"
    core::log "INFO" "Cache cleared."
}