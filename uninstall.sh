#!/bin/bash
#
# NetSnmp - Uninstaller
# Description: Safely removes all files and directories created by the installer.
#

set -e

# --- Configuration ---
# This script needs to know where files *might* be installed.
# It will check both system and user locations.
readonly FILES_TO_REMOVE=(
    "/usr/local/bin/netsnmp"
    "/usr/local/bin/uninstall.sh"
    "/usr/local/share/man/man1/netsnmp.1.gz"
    "${HOME}/.local/bin/netsnmp"
    "${HOME}/.local/bin/uninstall.sh"
    "${HOME}/.local/share/man/man1/netsnmp.1.gz"
)

readonly DIRS_TO_REMOVE=(
    "/usr/local/lib/netsnmp"
    "/etc/netsnmp"
    "/var/cache/netsnmp"
    "${HOME}/.local/lib/netsnmp"
    "${HOME}/.config/netsnmp"
    "${HOME}/.cache/netsnmp"
)

# --- Helper Functions ---
_log() { echo "→ $*"; }
_success() { echo "✓ $*"; }
_warn() { echo "⚠️ $*"; }

# --- Main Logic ---
echo "--- NetSnmp Uninstaller ---"
echo ""

if [[ $EUID -ne 0 ]]; then
    _warn "This script should be run with sudo to ensure all system files can be removed."
    read -p "Do you want to continue without sudo? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting."
        exit 1
    fi
fi

read -p "This will permanently remove all NetSnmp files and configurations. Are you sure? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting."
    exit 0
fi

_log "Removing individual files..."
for file in "${FILES_TO_REMOVE[@]}"; do
    if [[ -f "$file" ]]; then
        rm -f "$file" && _success "Removed ${file}"
    fi
done

_log "Removing directories..."
for dir in "${DIRS_TO_REMOVE[@]}"; do
    if [[ -d "$dir" ]]; then
        rm -rf "$dir" && _success "Removed directory ${dir}"
    fi
done

# Note: We do not remove the log file itself, as log rotation might have changed its permissions.
# The parent directory removal will handle it.

echo ""
_success "NetSnmp has been successfully uninstalled."