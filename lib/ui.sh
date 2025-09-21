#!/bin/bash
#
# NetSnmp Library - UI Function
# Description: Handles all user-facing output, like help, headers, and messages.
#

# --- Colors and Formatting ---
if [[ -t 1 ]]; then
    readonly C_RESET='\033[0m'; readonly C_BOLD='\033[1m';
    readonly C_RED='\033[0;31m'; readonly C_GREEN='\033[0;32m';
    readonly C_YELLOW='\033[0;33m'; readonly C_BLUE='\033[0;34m';
    readonly C_CYAN='\033[0;36m';
fi

# --- Standard UI Components ---
ui::print_header() { echo -e "\n${C_BOLD}${C_CYAN}--- ${1} ---${C_RESET}"; }
ui::print_success() { echo -e "${C_GREEN}✓${C_RESET} ${1}"; }
ui::print_error() { echo -e "${C_RED}✗ ERROR:${C_RESET} ${1}" >&2; }
ui::print_info() { echo -e "${C_YELLOW}→${C_RESET} ${1}"; }

# --- Help and Manuals ---

ui::show_help() {
    echo -e "${C_BOLD}NetSnmp v${VERSION} - Network Device Discovery Tool${C_RESET}"
    echo "A fast and efficient network scanner using ICMP and SNMP."
    echo ""
    echo -e "${C_BOLD}USAGE:${C_RESET}"
    echo "  netsnmp [OPTIONS] [SEARCH_PATTERN]"
    echo ""
    echo -e "${C_BOLD}CORE COMMANDS:${C_RESET}"
    echo -e "  ${C_CYAN}-u, --update${C_RESET}              Rebuilds the device cache by scanning the network."
    echo -e "  ${C_CYAN}--update-incremental${C_RESET}   Scans and updates the cache without removing offline devices."
    echo -e "  ${C_CYAN}[pattern]${C_RESET}                Search the cache for a device by IP, hostname, or serial."
    echo ""
    echo -e "${C_BOLD}CACHE MANAGEMENT:${C_RESET}"
    echo -e "  ${C_CYAN}-i, --info${C_RESET}                Show cache statistics and status."
    echo -e "  ${C_CYAN}-c, --clear${C_RESET}               Clear all cached data."
    echo ""
    echo -e "${C_BOLD}CONFIGURATION & UTILITIES:${C_RESET}"
    echo -e "  ${C_CYAN}--config${C_RESET}                  Display the current configuration."
    echo -e "  ${C_CYAN}--wizard${C_RESET}                  Run the interactive configuration wizard."
    echo -e "  ${C_CYAN}-h, --help${C_RESET}                  Show this help message."
    echo -e "  ${C_CYAN}-v, --verbose${C_RESET}             Enable verbose (step-by-step) output."
    echo -e "  ${C_CYAN}--version${C_RESET}                 Show the tool's version."
    echo ""
    echo -e "${C_BOLD}DIAGNOSTICS:${C_RESET}"
    echo -e "  ${C_CYAN}--test-scan${C_RESET}               Run a quick check of dependencies and configuration."
    echo -e "  ${C_CYAN}--test-snmp [IP]${C_RESET}        Test SNMP connectivity against a single IP."
    echo -e "  ${C_CYAN}--test-ips [NETWORK]${C_RESET}    Verify IP generation for a network string."
    echo ""
    echo -e "${C_BOLD}EXAMPLES:${C_RESET}"
    echo "  netsnmp --update"
    echo "  netsnmp switch-01-floor2"
    echo "  netsnmp 192.168.10.5"
    echo "  netsnmp --update-incremental"
    echo ""
    echo -e "For complete details, see ${C_BOLD}man netsnmp${C_RESET}."
}

ui::show_version() { echo "NetSnmp v${VERSION}"; }

ui::show_uninstall_instructions() {
    ui::print_header "Uninstall Instructions"
    ui::print_info "To uninstall, please run the dedicated uninstall script:"
    echo "  sudo uninstall.sh"
    ui::print_info "This will safely remove all installed files and directories."
}

ui::show_troubleshooting_tips() {
    ui::print_header "Troubleshooting"
    ui::print_info "If no devices were found, please check the following:"
    echo "  1. Network Connectivity: Can you 'ping' the target devices manually from this machine?"
    echo "  2. Configuration: Are the subnets and communities correct? Run 'netsnmp --config' to verify."
    echo "  3. Firewalls: Is ICMP (ping) or SNMP (UDP port 161) being blocked by a firewall?"
    echo -e "     ${C_YELLOW}→ If ICMP is blocked, you MUST use the SNMP-only scan mode.${C_RESET}"
    echo "       Edit your config file and set: scan_mode=\"snmp\""
    echo "  4. Device SNMP: Is SNMP enabled on the target network devices themselves?"
    echo ""
    ui::print_info "Use the built-in diagnostic tools to help isolate the problem:"
    echo "  - 'netsnmp --test-scan' to check your local setup."
    echo "  - 'netsnmp --test-snmp [IP]' to verify SNMP against a specific, known-good device."
}

# --- Interactive Wizard ---

ui::run_config_wizard() {
    # It is critical that the wizard loads the most current config before editing.
    core::load_config

    ui::print_header "NetSnmp Configuration Wizard"
    echo "Please provide the default values for your network scans."
    echo "You can leave any prompt blank to accept the current value shown in [brackets]."
    echo ""

    local current_subnets="${G_CONFIG[subnets]}"
    read -rp "Networks to scan: [${current_subnets}]: " new_subnets
    G_CONFIG[subnets]="${new_subnets:-$current_subnets}"

    local current_communities="${G_CONFIG[communities]}"
    read -rp "SNMP communities: [${current_communities}]: " new_communities
    G_CONFIG[communities]="${new_communities:-$current_communities}"

    local current_mode="${G_CONFIG[scan_mode]}"
    read -rp "Scan mode (icmp/snmp): [${current_mode}]: " new_mode
    # This is the corrected, robust logic:
    # 1. Use the new value, or fall back to the current one if input is empty.
    G_CONFIG[scan_mode]="${new_mode:-$current_mode}"
    # 2. Validate the result. If it's invalid, revert to the original value.
    if [[ "${G_CONFIG[scan_mode]}" != "icmp" && "${G_CONFIG[scan_mode]}" != "snmp" ]]; then
        ui::print_error "Invalid mode '${G_CONFIG[scan_mode]}'. Reverting to '${current_mode}'."
        G_CONFIG[scan_mode]="${current_mode}"
    fi
    
    echo ""
    core::save_config
    ui::print_success "Configuration saved to: ${G_PATHS[config_file]}"
    echo ""
    ui::print_info "Your selected scan mode is now: '${G_CONFIG[scan_mode]}'."
    ui::print_info "You can now run 'netsnmp --update'."
}