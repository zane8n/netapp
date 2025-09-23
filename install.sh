#!/bin/bash
#
# NetSnmp Installer
#
# Installs the NetSnmp tool, libraries, configuration, and man page.
# Must be run with sudo for system-wide installation.

set -e

# --- Configuration ---
INSTALL_PREFIX="/usr/local"
BIN_DIR="${INSTALL_PREFIX}/bin"
LIB_DIR="${INSTALL_PREFIX}/lib/netsnmp"
CONF_DIR="/etc/netsnmp"
CACHE_DIR="/var/cache/netsnmp"
LOG_DIR="/var/log"
MAN_DIR="${INSTALL_PREFIX}/share/man/man1"

TARGET_BINARY="${BIN_DIR}/netsnmp"

# --- UI Functions ---
info() { echo "INFO: $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }
success() { echo "✅ SUCCESS: $*"; }

# --- Helper Functions ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This installer must be run as root. Please use 'sudo bash $0'."
    fi
}

detect_package_manager() {
    if command -v apt-get >/dev/null; then echo "apt-get";
    elif command -v dnf >/dev/null; then echo "dnf";
    elif command -v yum >/dev/null; then echo "yum";
    elif command -v pacman >/dev/null; then echo "pacman";
    elif command -v zypper >/dev/null; then echo "zypper";
    else echo "unknown"; fi
}

install_dependencies() {
    local pm
    pm=$(detect_package_manager)
    info "Detected package manager: ${pm}"
    info "Installing dependencies (net-snmp-utils, iputils)..."

    case "$pm" in
        apt-get) sudo apt-get update && sudo apt-get install -y snmp iputils-ping ;;
        dnf|yum) sudo "$pm" install -y net-snmp-utils iputils ;;
        pacman) sudo pacman -Sy --noconfirm net-snmp iputils ;;
        zypper) sudo zypper install -y net-snmp iputils ;;
        *)
            echo "WARNING: Could not determine package manager."
            echo "Please ensure the following are installed manually:"
            echo "  - snmpwalk, snmpget (from a package like 'net-snmp-utils')"
            echo "  - ping (from a package like 'iputils')"
            read -p "Press [Enter] to continue..."
            ;;
    esac
}

# --- Main Installation Logic ---
create_directories() {
    info "Creating required directories..."
    mkdir -p "$BIN_DIR"
    mkdir -p "$LIB_DIR"
    mkdir -p "$CONF_DIR"
    mkdir -p "$CACHE_DIR"
    mkdir -p "$MAN_DIR"
}

install_files() {
    info "Installing application files..."
    # Ensure source files are in the same directory as the installer
    cd "$(dirname "$0")"

    install -m 755 netsnmp "$TARGET_BINARY"
    # Copy all library scripts
    for lib_file in lib/*.sh; do
        install -m 644 "$lib_file" "$LIB_DIR/"
    done
}

install_config() {
    info "Installing configuration template..."
    if [[ ! -f "${CONF_DIR}/netsnmp.conf" ]]; then
        install -m 644 "conf/netsnmp.conf.template" "${CONF_DIR}/netsnmp.conf"
    else
        info "Existing configuration found. Skipping template installation."
    fi
}

install_man_page() {
    info "Installing man page..."
    gzip -c "man/netsnmp.1" > "${MAN_DIR}/netsnmp.1.gz"
    chmod 644 "${MAN_DIR}/netsnmp.1.gz"
}

# --- Main Execution ---
main() {
    echo "╔══════════════════════════════════╗"
    echo "║       NetSnmp Tool Installer       ║"
    echo "╚══════════════════════════════════╝"
    echo ""

    check_root
    install_dependencies
    create_directories
    install_files
    install_config
    install_man_page

    echo ""
    success "Installation complete!"
    echo ""
    echo "Next Steps:"
    echo "1. Configure the tool by editing: ${CONF_DIR}/netsnmp.conf"
    echo "   Or run the configuration wizard: sudo netsnmp --wizard"
    echo "2. Run your first scan:             sudo netsnmp --update"
    echo "3. Search the cache:                netsnmp switch01"
    echo "4. To uninstall, run the 'uninstall.sh' script from this directory."
}

main "$@"