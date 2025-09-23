#!/bin/bash
#
# NetSnmp Uninstaller
#
# Removes all system-wide files and directories created by the installer.
# Must be run with sudo.

set -e

# --- Configuration ---
INSTALL_PREFIX="/usr/local"
BIN_DIR="${INSTALL_PREFIX}/bin"
LIB_DIR="${INSTALL_PREFIX}/lib/netsnmp"
CONF_DIR="/etc/netsnmp"
CACHE_DIR="/var/cache/netsnmp"
LOG_FILE="/var/log/netsnmp.log"
MAN_DIR="${INSTALL_PREFIX}/share/man/man1"

TARGET_BINARY="${BIN_DIR}/netsnmp"

# --- UI Functions ---
info() { echo "INFO: $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }
success() { echo "✅ SUCCESS: $*"; }
warn() { echo "WARN: $*"; }


# --- Helper Functions ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This uninstaller must be run as root. Please use 'sudo bash $0'."
    fi
}

# --- Main Uninstallation Logic ---
main() {
    echo "╔═════════════════════════════════════╗"
    echo "║       NetSnmp Tool Uninstaller        ║"
    echo "╚═════════════════════════════════════╝"
    echo ""
    read -p "This will remove all NetSnmp files. Are you sure? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Uninstallation cancelled."
        exit 0
    fi

    check_root

    info "Removing files and directories..."
    rm -f "$TARGET_BINARY"
    rm -rf "$LIB_DIR"
    rm -f "${MAN_DIR}/netsnmp.1.gz"

    # Important: Only remove config/cache if they exist to avoid errors
    if [ -d "$CONF_DIR" ]; then
        # Check if user wants to keep configuration
        read -p "Do you want to remove configuration files in ${CONF_DIR}? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$CONF_DIR"
            info "Removed configuration directory."
        else
            warn "Skipping configuration directory removal."
        fi
    fi

    rm -rf "$CACHE_DIR"
    rm -f "$LOG_FILE"

    success "Uninstallation complete."
}

main "$@"