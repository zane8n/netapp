#!/bin/bash
#
# NetSnmp - Universal Installer (Version 3.0 Final)
# Description: Installs the NetSnmp tool and all its components.
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
readonly LIB_FILES=("lib/core.sh" "lib/scan.sh" "lib/cache.sh" "lib/discovery.sh" "lib/ui.sh" "lib/worker.sh")
readonly CONFIG_TEMPLATE="conf/netsnmp.conf.template"
readonly MAN_PAGE="man/netsnmp.1"

# --- Helper Functions ---
_log() { echo "→ $*"; }
_success() { echo "✓ $*"; }
_error() { echo "✗ ERROR: $*" >&2; exit 1; }
_warn() { echo "⚠️ WARNING: $*" >&2; }

# --- Installation Logic ---

install_files() {
    local -n paths=$1
    local name=$2

    _log "Creating directories for ${name} installation..."
    mkdir -p "${paths[bin]}" "${paths[lib]}" "${paths[conf_dir]}" "${paths[cache_dir]}" \
             "$(dirname "${paths[log_file]}")" "${paths[man_dir]}"

    _log "Installing main executables to ${paths[bin]}..."
    cp "${SCRIPT_FILES[@]}" "${paths[bin]}/"
    chmod 755 "${paths[bin]}/netsnmp" "${paths[bin]}/uninstall.sh"

    _log "Installing libraries to ${paths[lib]}..."
    cp ${LIB_FILES[@]} "${paths[lib]}/"
    chmod 644 "${paths[lib]}"/*.sh
    # The worker MUST be executable
    chmod 755 "${paths[lib]}/worker.sh"

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
    install_files PATHS_SYSTEM "system-wide"
    
    echo ""
    _success "NetSnmp has been installed system-wide."
    echo ""
    echo "======================= NEXT STEPS ======================="
    echo "1. Run the configuration wizard (as root):"
    echo "   sudo netsnmp --wizard"
    echo ""
    echo "2. Start your first scan (as root):"
    echo "   sudo netsnmp --update"
    echo ""
    echo "3. Search for a device:"
    echo "   netsnmp switch"
    echo ""
    echo "To view all options, run: man netsnmp"
    echo "To uninstall, run: sudo uninstall.sh"
    echo "=========================================================="
}

show_usage() {
    echo "NetSnmp Installer"
    echo "Usage: $0 [--help]"
    echo "Default action is a system-wide installation (requires sudo)."
}

# Check for local files
for f in "${SCRIPT_FILES[@]}" "${LIB_FILES[@]}" "$CONFIG_TEMPLATE" "$MAN_PAGE"; do
    [[ ! -f "$f" ]] && _error "Missing required file: '$f'. Run this from the project root."
done

case "${1:-}" in
    --help) show_usage ;;
    *) main_installation ;;
esac