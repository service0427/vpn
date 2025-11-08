#!/bin/bash

#====================================
# VPN Server One-Line Installation Script
#====================================

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || source /home/vpn/common.sh

print_header "VPN Server One-Line Installation"

# Create temporary directory
TEMP_DIR="/tmp/vpn_install_$$"
mkdir -p $TEMP_DIR
cd $TEMP_DIR

print_info "Downloading installation scripts..."

# Download scripts from GitHub
curl -sL https://raw.githubusercontent.com/service0427/vpn/main/install_vpn_server.sh -o install_vpn_server.sh
curl -sL https://raw.githubusercontent.com/service0427/vpn/main/uninstall_vpn.sh -o uninstall_vpn.sh
curl -sL https://raw.githubusercontent.com/service0427/vpn/main/check_firewall.sh -o check_firewall.sh
curl -sL https://raw.githubusercontent.com/service0427/vpn/main/vpn_heartbeat.sh -o vpn_heartbeat.sh
curl -sL https://raw.githubusercontent.com/service0427/vpn/main/common.sh -o common.sh

# Grant execution permissions
chmod +x *.sh

# Create /home/vpn directory
mkdir -p /home/vpn

# Copy scripts
cp *.sh /home/vpn/
cd /home/vpn

print_success "Starting installation..."
echo

# Run installation
./install_vpn_server.sh

# Clean up temporary directory
rm -rf $TEMP_DIR

echo
print_info "Setting up auto-installation on reboot..."

# Cron job configuration (prevent duplicates)
CRON_ENTRY="@reboot while ! ping -c 1 8.8.8.8 >/dev/null 2>&1; do sleep 1; done && curl -sL https://github.com/service0427/vpn/raw/main/install.sh | sudo bash >/dev/null 2>&1"

# Check and remove existing cron job
if crontab -l 2>/dev/null | grep -q "github.com/service0427/vpn/raw/main/install.sh"; then
    crontab -l 2>/dev/null | grep -v "github.com/service0427/vpn/raw/main/install.sh" | crontab - 2>/dev/null || true
fi

# Add new cron job
(crontab -l 2>/dev/null || true; echo "$CRON_ENTRY") | crontab - 2>/dev/null

print_success "Auto-installation on reboot enabled"

echo
print_header "Installation Complete!"
echo
print_info "Useful commands:"
echo -e "  Check VPN status: ${GREEN}wg show${NC}"
echo -e "  Check firewall: ${GREEN}/home/vpn/check_firewall.sh${NC}"
echo -e "  Reinstall VPN: ${GREEN}/home/vpn/install_vpn_server.sh${NC}"
echo -e "  Remove VPN: ${GREEN}/home/vpn/uninstall_vpn.sh${NC}"
echo
print_info "Automatic configuration:"
echo -e "  Auto-reinstall on reboot enabled (auto re-register on IP change)"
echo -e "  Check cron: ${GREEN}crontab -l${NC}"