#!/bin/bash
#
# NetSnmp - Scan Worker (v3.0)
# This script is executed by xargs for each IP address.
# It is a self-sufficient program that initializes its own environment.
#

# Argument check
if [[ -z "$1" ]]; then
    exit 1
fi

WORKER_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
export LIB_DIR="$WORKER_DIR"

source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/discovery.sh"

# --- Main Worker Logic ---
core::bootstrap
core::init

IP_TO_SCAN="$1"
result=$(discovery::resolve_snmp_details "$IP_TO_SCAN")

if [[ -n "$result" ]]; then
    hostname=$(echo "$result" | cut -d'|' -f1)
    serial=$(echo "$result" | cut -d'|' -f2)
    echo "$IP_TO_SCAN \"$hostname\" \"$serial\""
fi

exit 0