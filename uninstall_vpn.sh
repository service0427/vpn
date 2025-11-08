#!/bin/bash

#====================================
# VPN Server Complete Removal Script
# - Remove WireGuard
# - Delete server info from API
# - Clean up all configurations
#====================================

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || source /home/vpn/common.sh

SERVER_IP=$(get_server_ip)

echo -e "${RED}=====================================${NC}"
echo -e "${RED}   VPN Server Complete Removal${NC}"
echo -e "${RED}=====================================${NC}"
echo
print_warning "Warning: This operation cannot be undone!"
echo -e "- Remove WireGuard wg0 interface only (wg1 will be preserved)"
echo -e "- Delete server and key info from API"
echo -e "- Delete /etc/wireguard/wg0.conf related configuration only"
echo
read -p "Do you really want to continue? (y/N): " confirm

# Default is N (cancel)
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo

# 1. Delete server info from API
print_info "[1/4] Deleting server info from API... (IP: ${SERVER_IP})"
RESPONSE=$(curl -s "${API_URL}/release/all?ip=${SERVER_IP}&delete=true")
if echo "$RESPONSE" | jq '.success' | grep -q true; then
    KEYS_DELETED=$(echo "$RESPONSE" | jq -r '.deleted.keys_deleted // 0')
    print_success "Server info deleted from API (IP: ${SERVER_IP}, Deleted keys: ${KEYS_DELETED})"
else
    print_warning "API deletion failed (IP: ${SERVER_IP}, manual processing required)"
fi

# 2. Stop WireGuard service
print_info "[2/4] Stopping WireGuard service..."
systemctl stop wg-quick@${VPN_INTERFACE} 2>/dev/null
systemctl disable wg-quick@${VPN_INTERFACE} 2>/dev/null
wg-quick down ${VPN_INTERFACE} 2>/dev/null
print_success "WireGuard service stopped"

# 3. Delete configuration files (wg0 related only)
print_info "[3/4] Deleting wg0 configuration files..."
rm -f ${WIREGUARD_DIR}/${VPN_INTERFACE}.conf
rm -f ${WIREGUARD_DIR}/server.key ${WIREGUARD_DIR}/server.pub
rm -rf ${WIREGUARD_DIR}/clients/  # wg0 client configs
rm -f ${VPN_DIR}/server_register.json
rm -f ${VPN_DIR}/keys_register.json
print_success "wg0 configuration files deleted"

# 4. Remove firewall rules (VPN port only)
print_info "[4/4] Removing firewall rules (VPN port only)..."

# Check current status before removal
echo "Current firewall status:"
firewall-cmd --list-all | grep -E "services:|ports:" | head -2

# Remove VPN port only (keep SSH, etc.)
SAVED_VPN_PORT=$(grep -oP 'ListenPort\s*=\s*\K\d+' ${WIREGUARD_DIR}/${VPN_INTERFACE}.conf 2>/dev/null || echo "${VPN_PORT}")
if firewall-cmd --list-ports | grep -q "${SAVED_VPN_PORT}/udp"; then
    firewall-cmd --permanent --remove-port=${SAVED_VPN_PORT}/udp 2>/dev/null
    print_success "VPN port ${SAVED_VPN_PORT}/udp removed"
else
    echo "VPN port already removed."
fi

# masquerade is needed by VPN, so remove it (be careful as other services might use it)
# firewall-cmd --permanent --remove-masquerade 2>/dev/null

firewall-cmd --reload 2>/dev/null

echo "Updated firewall status:"
firewall-cmd --list-all | grep -E "services:|ports:" | head -2
print_success "Firewall cleanup complete (essential ports like SSH are preserved)"

echo
print_header "VPN Server Removal Complete!"
echo
print_info "Removed server: ${SERVER_IP}:${SAVED_VPN_PORT}"
echo
print_info "Next steps:"
echo -e "1. To reinstall the server:"
echo -e "   ${GREEN}sudo ./install_vpn_server.sh${NC}"
echo
echo -e "2. To remove WireGuard package as well:"
echo -e "   ${GREEN}dnf remove -y wireguard-tools${NC}"
echo
