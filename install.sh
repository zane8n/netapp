#!/bin/bash
#
# NetSnmp Installer
# Installs the modular version of the NetSnmp tool.

set -e

# --- Configuration ---
readonly INSTALL_PREFIX="/usr/local"
readonly BIN_DIR="${INSTALL_PREFIX}/bin"
readonly LIB_DIR="${INSTALL_PREFIX}/lib/netsnmp"
readonly MAN_DIR="${INSTALL_PREFIX}/share/man/man1"
readonly CONFIG_DIR="/etc/netsnmp"
readonly CACHE_DIR="/var/cache/netsnmp"
readonly LOG_DIR="/var/log"

# --- Main Installation ---
main() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This installer must be run with sudo or as root." >&2
        exit 1
    fi

    echo "Starting NetSnmp installation..."

    # 1. Detect dependencies
    detect_dependencies

    # 2. Create directories
    echo "Creating directories..."
    mkdir -p "$BIN_DIR" "$LIB_DIR" "$MAN_DIR" "$CONFIG_DIR" "$CACHE_DIR" "$LOG_DIR"
    echo "✓ Directories created."

    # 3. Install files (assuming they are in the same directory as install.sh)
    echo "Installing application files..."
    install -m 755 netsnmp "$BIN_DIR/"
    install -m 644 lib/*.sh "$LIB_DIR/"
    echo "✓ Scripts installed."

    # 4. Install config template
    if [ ! -f "${CONFIG_DIR}/netsnmp.conf" ]; then
        install -m 644 conf/netsnmp.conf.template "${CONFIG_DIR}/netsnmp.conf"
        echo "✓ Default configuration installed."
    else
        echo "ⓘ Existing configuration found. Skipping template installation."
    fi

    # 5. Install man page
    install -m 644 man/netsnmp.1 "${MAN_DIR}/"
    gzip -f "${MAN_DIR}/netsnmp.1"
    echo "✓ Man page installed."

    echo -e "\n✅ Installation successful!"
    echo "   Run 'netsnmp --help' to get started."
    echo "   Run 'netsnmp --wizard' to configure."
}

# --- Helper Functions ---
detect_dependencies() {
    echo "Checking for dependencies (snmp-tools, iputils)..."
    local missing=""

    command -v snmpget &>/dev/null || missing+=" snmp-tools"
    command -v ping &>/dev/null || missing+=" iputils"

    if [[ -n "$missing" ]]; then
        echo "ERROR: Missing dependencies:$missing" >&2
        echo "Please install them using your package manager." >&2
        echo "  e.g., sudo apt install snmp iputils-ping" >&2
        echo "  e.g., sudo dnf install net-snmp-utils iputils" >&2
        exit 1
    fi
    echo "✓ Dependencies are satisfied."
}

main "$@"