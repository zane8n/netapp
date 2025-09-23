#!/bin/bash
#
# NetSnmp - Scan Worker
# Description: This script is executed in parallel for each IP address.
# It is a self-sufficient program that initializes its own environment.
#

# Argument check
if [[ -z "$1" ]]; then
    # This script is not meant to be run by a user directly.
    exit 1
fi

# Determine the library directory relative to this worker's location.
WORKER_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
export LIB_DIR="$WORKER_DIR"

# Source the necessary libraries.
source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/discovery.sh"

# --- Main Worker Logic ---

# Step 1: Initialize the environment. This is the crucial step.
# It loads the exact same configuration file the main script would.
core::bootstrap
core::init

# Step 2: Get the IP address from the command line argument.
IP_TO_SCAN="$1"

# Step 3: Execute the discovery function for the given IP.
# This function will now use the correct G_CONFIG values.
result=$(discovery::resolve_snmp_details "$IP_TO_SCAN")

# Step 4: Format and print the output if successful.
if [[ -n "$result" ]]; then
    hostname=$(echo "$result" | cut -d'|' -f1)
    serial=$(echo "$result" | cut -d'|' -f2)
    # The output format must match what the cache functions expect.
    echo "$IP_TO_SCAN \"$hostname\" \"$serial\""
fi

exit 0