#!/bin/bash
#
# NetSnmp - Universal Installer
# Description: Installs the NetSnmp tool and its components system-wide or for a user.
#

set -e
set -o pipefail

# --- Configuration ---
PREFIX_SYSTEM="/usr/local"
PREFIX_USER="${HOME}/.local"

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

readonly SCRIPT_FILES=("netsnmp" "uninstall.sh")
readonly LIB_FILES=("lib/core.sh" "lib/scan.sh" "lib/cache.sh" "lib/discovery.sh" "lib/ui.sh")
readonly CONFIG_TEMPLATE="conf/netsnmp.conf.template"
readonly MAN_PAGE="man/netsnmp.1"

# --- Helper Functions ---
_log() { echo "→ $*"; }
_success() { echo "✓ $*"; }
_error() { echo "✗ ERROR: $*" >&2; exit 1; }
_warn() { echo "⚠️ WARNING: $*" >&2; }

# --- Installation Functions ---

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then echo "deb";
    elif command -v dnf >/dev/null 2>&1; then echo "rpm-dnf";
    elif command -v yum >/dev/null 2>&1; then echo "rpm-yum";
    elif command -v pacman >/dev/null 2>&1; then echo "arch";
    elif command -v zypper >/dev/null 2>&1; then echo "suse";
    else echo "unknown"; fi
}

install_dependencies() {
    local pm; pm=$(detect_package_manager)
    _log "Detected package manager: ${pm}"
    _log "Installing dependencies (snmp, fping)..."
    _log "NOTE: 'fping' is highly recommended for optimal scan performance."

    case ${pm} in
        deb) apt-get update && apt-get install -y snmp fping ;;
        rpm-dnf) dnf install -y net-snmp-utils fping ;;
        rpm-yum) yum install -y net-snmp-utils fping ;;
        arch) pacman -Sy --noconfirm net-snmp fping ;;
        suse) zypper install -y net-snmp fping ;;
        *)
            _warn "Unknown package manager. Please ensure the following are installed:"
            _warn "  - snmp (provides snmpget, snmpwalk)"
            _warn "  - fping (for high-performance scanning)"
            read -p "Press Enter to continue once dependencies are installed..."
            ;;
    esac
    _success "Dependencies installed."
}

install_files() {
    local -n paths=$1
    local name=$2

    _log "Creating directories for ${name} installation..."
    mkdir -p "${paths[bin]}" "${paths[lib]}" "${paths[conf_dir]}" "${paths[cache_dir]}" \
             "$(dirname "${paths[log_file]}")" "${paths[man_dir]}"

    _log "Installing scripts to ${paths[bin]}..."
    cp "${SCRIPT_FILES[@]}" "${paths[bin]}/"
    chmod 755 "${paths[bin]}/netsnmp" "${paths[bin]}/uninstall.sh"

    _log "Installing libraries to ${paths[lib]}..."
    cp ${LIB_FILES[@]} "${paths[lib]}/"
    chmod 644 "${paths[lib]}"/*

    if [[ ! -f "${paths[conf_dir]}/netsnmp.conf" ]]; then
        _log "Installing configuration template..."
        cp "${CONFIG_TEMPLATE}" "${paths[conf_dir]}/netsnmp.conf"
        chmod 644 "${paths[conf_dir]}/netsnmp.conf"
    else
        _log "Existing configuration found, skipping template install."
    fi

    _log "Installing man page..."
    gzip -c "${MAN_PAGE}" > "${paths[man_dir]}/netsnmp.1.gz"
    chmod 644 "${paths[man_dir]}/netsnmp.1.gz"
    
    _log "Finalizing environment..."
    touch "${paths[log_file]}"
    chmod 644 "${paths[log_file]}"
}

main_installation() {
    if [[ $EUID -ne 0 ]]; then
        _error "System-wide installation requires root privileges. Please run with sudo."
    fi
    install_dependencies
    install_files PATHS_SYSTEM "system-wide"
    
    echo ""
    _success "NetSnmp has been installed system-wide."
    echo ""
    echo "======================= NEXT STEPS ======================="
    echo "1. Run the configuration wizard (optional):"
    echo "   sudo netsnmp --wizard"
    echo ""
    echo "2. Start your first scan:"
    echo "   sudo netsnmp --update"
    echo ""
    echo "3. Search for a device:"
    echo "   netsnmp switch"
    echo ""
    echo "To view all options, run: man netsnmp"
    echo "To uninstall, run: sudo uninstall.sh"
    echo "=========================================================="
}

user_installation() {
    _log "Starting user-specific installation..."
    _warn "Please ensure dependencies are installed (snmp, fping)."
    echo "  On Debian/Ubuntu: sudo apt install snmp fping"
    echo "  On Fedora/CentOS: sudo dnf install net-snmp-utils fping"
    read -p "Press Enter to continue..."
    
    install_files PATHS_USER "user"
    
    if [[ ":$PATH:" != *":${PATHS_USER[bin]}:"* ]]; then
        _warn "Your PATH does not include ${PATHS_USER[bin]}."
        _warn "Add the following to your ~/.bashrc or ~/.zshrc:"
        echo "  export PATH=\"${PATHS_USER[bin]}:\$PATH\""
    fi

    echo ""
    _success "NetSnmp has been installed for the current user."
    echo "Please restart your terminal or run 'source ~/.bashrc' for changes to take effect."
}

show_usage() {
    echo "NetSnmp Installer"
    echo "Usage: $0 [--user | --help]"
    echo ""
    echo "  --user    Install for the current user only (~/.local)."
    echo "  --help    Show this help message."
    echo ""
    echo "Default action is a system-wide installation (requires sudo)."
}

for f in "${SCRIPT_FILES[@]}" "${LIB_FILES[@]}" "$CONFIG_TEMPLATE" "$MAN_PAGE"; do
    [[ ! -f "$f" ]] && _error "Missing required file: '$f'. Run from the project root."
done

case "${1:-}" in
    --user) user_installation ;;
    --help) show_usage ;;
    *) main_installation ;;
esac