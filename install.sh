#!/bin/bash

#====================================
# VPN Server One-Line Installation Script
#====================================

# Color definitions (temporary, until common.sh is downloaded)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   VPN Server One-Line Installation${NC}"
echo -e "${GREEN}=====================================${NC}"
echo

# Create temporary directory
TEMP_DIR="/tmp/vpn_install_$$"
mkdir -p $TEMP_DIR
cd $TEMP_DIR

echo -e "${YELLOW}Downloading installation scripts...${NC}"

# Download scripts from GitHub (with cache buster)
CACHE_BUSTER="?t=$(date +%s)"
curl -sL "https://raw.githubusercontent.com/service0427/vpn/main/install_vpn_server.sh${CACHE_BUSTER}" -o install_vpn_server.sh
curl -sL "https://raw.githubusercontent.com/service0427/vpn/main/uninstall_vpn.sh${CACHE_BUSTER}" -o uninstall_vpn.sh
curl -sL "https://raw.githubusercontent.com/service0427/vpn/main/check_firewall.sh${CACHE_BUSTER}" -o check_firewall.sh
curl -sL "https://raw.githubusercontent.com/service0427/vpn/main/vpn_heartbeat.sh${CACHE_BUSTER}" -o vpn_heartbeat.sh
curl -sL "https://raw.githubusercontent.com/service0427/vpn/main/common.sh${CACHE_BUSTER}" -o common.sh

# Grant execution permissions
chmod +x *.sh

# Create /home/vpn directory
mkdir -p /home/vpn

# Copy scripts
cp *.sh /home/vpn/
cd /home/vpn

echo -e "${GREEN}✓ Starting installation...${NC}"
echo

# Run installation
./install_vpn_server.sh

# Clean up temporary directory
rm -rf $TEMP_DIR

echo
echo -e "${YELLOW}Setting up auto-installation on reboot...${NC}"

# Cron job configuration (prevent duplicates)
CRON_ENTRY="@reboot while ! ping -c 1 8.8.8.8 >/dev/null 2>&1; do sleep 1; done && curl -sL https://github.com/service0427/vpn/raw/main/install.sh | sudo bash >/dev/null 2>&1"

# Check and remove existing cron job
if crontab -l 2>/dev/null | grep -q "github.com/service0427/vpn/raw/main/install.sh"; then
    crontab -l 2>/dev/null | grep -v "github.com/service0427/vpn/raw/main/install.sh" | crontab - 2>/dev/null || true
fi

# Add new cron job
(crontab -l 2>/dev/null || true; echo "$CRON_ENTRY") | crontab - 2>/dev/null

echo -e "${GREEN}✓ Auto-installation on reboot enabled${NC}"

echo
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   Installation Complete!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo
echo -e "${YELLOW}Useful commands:${NC}"
echo -e "  Check VPN status: ${GREEN}wg show${NC}"
echo -e "  Check firewall: ${GREEN}/home/vpn/check_firewall.sh${NC}"
echo -e "  Reinstall VPN: ${GREEN}/home/vpn/install_vpn_server.sh${NC}"
echo -e "  Remove VPN: ${GREEN}/home/vpn/uninstall_vpn.sh${NC}"
echo
echo -e "${YELLOW}Automatic configuration:${NC}"
echo -e "  Auto-reinstall on reboot enabled (auto re-register on IP change)"
echo -e "  Check cron: ${GREEN}crontab -l${NC}"