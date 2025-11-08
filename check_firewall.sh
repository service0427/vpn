#!/bin/bash

#====================================
# Firewall Status Check Script
#====================================

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || source /home/vpn/common.sh

print_header "Firewall Status Check"

# 1. Basic information
echo "Basic Information:"
firewall-cmd --state
firewall-cmd --get-default-zone
echo

# 2. Allowed services
echo "Allowed Services:"
firewall-cmd --list-services
echo

# 3. Open ports
echo "Open Ports:"
firewall-cmd --list-ports
echo

# 4. SSH port check
echo "SSH Status:"
if firewall-cmd --list-services | grep -q ssh; then
    print_success "SSH service enabled"
else
    print_warning "SSH service not found in firewall!"
fi

# Check SSH port
SSH_PORT=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
echo "SSH Port: $SSH_PORT"
echo

# 5. Critical ports check
echo "Critical Port Status:"
CRITICAL_PORTS="22 80 443 3306 ${VPN_PORT}"
for port in $CRITICAL_PORTS; do
    if firewall-cmd --list-all | grep -E "ports:|services:" | grep -q "$port"; then
        print_success "Port $port open"
    else
        print_error "Port $port closed"
    fi
done
echo

# 6. Full configuration
echo "Full Firewall Configuration:"
firewall-cmd --list-all

echo
echo "======================================"
print_warning "Important Notes:"
echo "- Never block SSH (22)"
echo "- Only open necessary ports, leave others to default policy"
echo "- Always test SSH connection after firewall changes"
echo "======================================"
