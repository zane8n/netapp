#!/bin/bash
#
# NetSnmp - Universal Installer
# Description: Installs the NetSnmp tool and its components system-wide or for a user.
#

set -e
set -o pipefail

# --- Configuration ---
# Source URL for fetching files if they are not local
# REPO_URL="https://raw.githubusercontent.com/yourusername/netsnmp/main"

# Installation directories
PREFIX_SYSTEM="/usr/local"
PREFIX_USER="${HOME}/.local"

# File paths
declare -A PATHS_SYSTEM=(
    [bin]="${PREFIX_SYSTEM}/bin"
    [lib]="${PREFIX_SYSTEM}/lib/netsnmp"
    [conf_dir]="/etc/netsnmp"
    [cache_dir]="/var/cache/netsnmp"
    [log_file]="/var/log/netsnmp.log"
    [man_dir]="${PREFIX_SYSTEM}/share/man/man1"
)

declare -A PATHS_USER=(
    [bin]="${PREFIX_USER}/bin"
    [lib]="${PREFIX_USER}/lib/netsnmp"
    [conf_dir]="${HOME}/.config/netsnmp"
    [cache_dir]="${HOME}/.cache/netsnmp"
    [log_file]="${HOME}/.cache/netsnmp.log"
    [man_dir]="${PREFIX_USER}/share/man/man1"
)

# List of files to install
readonly SCRIPT_FILES=("netsnmp")
readonly LIB_FILES=("lib/core.sh" "lib/scan.sh" "lib/cache.sh" "lib/discovery.sh" "lib/ui.sh")
readonly CONFIG_TEMPLATE="conf/netsnmp.conf.template"
readonly MAN_PAGE="man/netsnmp.1"


# --- Helper Functions ---
_log() {
    echo "INFO: $*"
}

_error() {
    echo "ERROR: $*" >&2
    exit 1
}

_warn() {
    echo "WARNING: $*" >&2
}

# --- Installation Functions ---

# Detects the system's package manager
detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "deb"
    elif command -v dnf >/dev/null 2>&1; then
        echo "rpm-dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "rpm-yum"
    elif command -v pacman >/dev/null 2>&1; then
        echo "arch"
    elif command -v zypper >/dev/null 2>&1; then
        echo "suse"
    else
        echo "unknown"
    fi
}

# Installs dependencies based on the detected package manager
install_dependencies() {
    local pm
    pm=$(detect_package_manager)

    _log "Detected package manager: ${pm}"
    _log "Installing dependencies (snmp, fping)..."

    case ${pm} in
        deb)
            apt-get update
            apt-get install -y snmp fping
            ;;
        rpm-dnf)
            dnf install -y net-snmp-utils fping
            ;;
        rpm-yum)
            yum install -y net-snmp-utils fping
            ;;
        arch)
            pacman -Sy --noconfirm net-snmp fping
            ;;
        suse)
            zypper install -y net-snmp fping
            ;;
        *)
            _warn "Unknown package manager. Please ensure the following are installed:"
            _warn "  - snmp (snmpget, snmpwalk commands)"
            _warn "  - fping (highly recommended for performance)"
            _warn "  - ping (fallback)"
            read -p "Press Enter to continue..."
            ;;
    esac
}

# Installs all the tool's scripts and libraries
install_scripts() {
    local -n paths=$1
    
    _log "Creating directories..."
    mkdir -p "${paths[bin]}"
    mkdir -p "${paths[lib]}"

    _log "Installing main script to ${paths[bin]}/netsnmp..."
    cp "${SCRIPT_FILES[0]}" "${paths[bin]}/"
    chmod 755 "${paths[bin]}/netsnmp"

    _log "Installing libraries to ${paths[lib]}..."
    for lib_file in "${LIB_FILES[@]}"; do
        cp "$lib_file" "${paths[lib]}/"
        chmod 644 "${paths[lib]}/$(basename "$lib_file")"
    done
}

# Sets up configuration, cache, and log directories/files
setup_environment() {
    local -n paths=$1

    _log "Setting up environment directories..."
    mkdir -p "${paths[conf_dir]}"
    mkdir -p "${paths[cache_dir]}"
    mkdir -p "$(dirname "${paths[log_file]}")"
    
    # Install config template if no config exists
    if [[ ! -f "${paths[conf_dir]}/netsnmp.conf" ]]; then
        _log "Installing configuration template to ${paths[conf_dir]}/netsnmp.conf..."
        cp "${CONFIG_TEMPLATE}" "${paths[conf_dir]}/netsnmp.conf"
        chmod 644 "${paths[conf_dir]}/netsnmp.conf"
    else
        _log "Existing configuration found. Skipping template installation."
    fi

    # Create log file
    touch "${paths[log_file]}"
    chmod 644 "${paths[log_file]}"
}

# Installs the man page
install_man_page() {
    local -n paths=$1

    _log "Installing man page..."
    mkdir -p "${paths[man_dir]}"
    
    gzip -c "${MAN_PAGE}" > "${paths[man_dir]}/netsnmp.1.gz"
    chmod 644 "${paths[man_dir]}/netsnmp.1.gz"
}

# Main installation logic for system-wide install
main_installation() {
    if [[ $EUID -ne 0 ]]; then
        _error "System-wide installation requires root privileges. Please run with sudo."
    fi

    install_dependencies
    install_scripts PATHS_SYSTEM
    setup_environment PATHS_SYSTEM
    install_man_page PATHS_SYSTEM

    echo ""
    _log "✅ System-wide installation complete!"
    echo ""
    echo "Next steps:"
    echo "1. (Optional) Configure the tool:"
    echo "   sudo netsnmp --wizard"
    echo "2. Scan your network:"
    echo "   sudo netsnmp --update"
    echo "3. Search for devices:"
    echo "   netsnmp switch"
    echo "4. View help:"
    echo "   netsnmp --help or man netsnmp"
}

# Main installation logic for user-specific install
user_installation() {
    _log "Starting user-specific installation..."
    _warn "Please ensure dependencies are installed (snmp, fping)."
    echo "On Debian/Ubuntu: sudo apt install snmp fping"
    echo "On Fedora/CentOS: sudo dnf install net-snmp-utils fping"
    echo "On Arch Linux:    sudo pacman -S net-snmp fping"
    read -p "Press Enter to continue..."

    install_scripts PATHS_USER
    setup_environment PATHS_USER
    install_man_page PATHS_USER

    # Check if user's local bin is in PATH
    if [[ ":$PATH:" != *":${PATHS_USER[bin]}:"* ]]; then
        _warn "Your PATH does not include ${PATHS_USER[bin]}."
        _warn "Add the following to your ~/.bashrc or ~/.zshrc:"
        echo ""
        echo "export PATH=\"${PATHS_USER[bin]}:\$PATH\""
        echo ""
    fi

    echo ""
    _log "✅ User-specific installation complete!"
    echo "Please restart your terminal or run 'source ~/.bashrc' for changes to take effect."
}

# --- Script Entrypoint ---

show_usage() {
    echo "NetSnmp Installer"
    echo "Usage: $0 [--user | --help]"
    echo ""
    echo "  --user    Install for the current user only (~/.local)."
    echo "  --help    Show this help message."
    echo ""
    echo "Running without arguments performs a system-wide installation (requires sudo)."
}

# Check for local files
for f in "${SCRIPT_FILES[@]}" "${LIB_FILES[@]}" "$CONFIG_TEMPLATE" "$MAN_PAGE"; do
    if [[ ! -f "$f" ]]; then
        _error "Missing required file: '$f'. Please run this installer from the project's root directory."
        # Optional: Add curl/wget logic here to fetch from a repo if needed
    fi
done

case "${1:-}" in
    --user)
        user_installation
        ;;
    --help)
        show_usage
        ;;
    *)
        main_installation
        ;;
esac