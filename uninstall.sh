#!/bin/bash
#
# NetSnmp Uninstaller

set -e

# --- Configuration ---
readonly INSTALL_PREFIX="/usr/local"
readonly BIN_DIR="${INSTALL_PREFIX}/bin"
readonly LIB_DIR="${INSTALL_PREFIX}/lib/netsnmp"
readonly MAN_DIR="${INSTALL_PREFIX}/share/man/man1"
readonly CONFIG_DIR="/etc/netsnmp"
readonly CACHE_DIR="/var/cache/netsnmp"
readonly LOG_FILE="/var/log/netsnmp.log"

# --- Main Uninstallation ---
main() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This uninstaller must be run with sudo or as root." >&2
        exit 1
    fi

    echo "This will remove NetSnmp from your system."
    read -p "Do you want to also remove configuration files in ${CONFIG_DIR}? [y/N] " -n 1 -r
    echo
    local remove_config=$REPLY
    
    read -p "Do you want to also remove cache and log files? [y/N] " -n 1 -r
    echo
    local remove_cache=$REPLY

    echo "Uninstalling NetSnmp..."

    # Remove binary, lib, and man page
    rm -f "${BIN_DIR}/netsnmp"
    rm -rf "${LIB_DIR}"
    rm -f "${MAN_DIR}/netsnmp.1.gz"
    echo "✓ Core files removed."

    # Conditionally remove config
    if [[ $remove_config =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        echo "✓ Configuration directory removed."
    fi

    # Conditionally remove cache and logs
    if [[ $remove_cache =~ ^[Yy]$ ]]; then
        rm -rf "$CACHE_DIR"
        rm -f "$LOG_FILE"
        echo "✓ Cache and log files removed."
    fi

    echo -e "\n✅ Uninstallation complete."
}

main "$@"