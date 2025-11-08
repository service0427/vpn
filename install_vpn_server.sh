#!/bin/bash

#====================================
# VPN Server Installation Script
# - Install WireGuard VPN server
# - Auto-generate 10 keys
# - Database initialization
#====================================

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || source /home/vpn/common.sh

# Get server IP
SERVER_IP=$(get_server_ip)

print_header "VPN Server Automatic Installation Script"
echo
print_info "Server IP: ${SERVER_IP}"
print_info "VPN Port: ${VPN_PORT}"
print_info "Key generation range: ${VPN_SUBNET}.${VPN_START_IP} ~ ${VPN_SUBNET}.${VPN_END_IP}"
echo

# 1. Install required packages
print_success "[1/6] Installing required packages..."

# Detect OS
OS=$(detect_os)

# Install packages by OS
if [[ "$OS" == "ubuntu" ]]; then
    print_info "Ubuntu detected..."
    apt-get update
    apt-get install -y wireguard-tools iptables ufw curl jq
elif [[ "$OS" == "rocky" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]]; then
    print_info "Rocky/RHEL detected..."
    # Enable EPEL repository (for WireGuard installation)
    dnf install -y epel-release 2>/dev/null || true
    dnf config-manager --set-enabled crb 2>/dev/null || true
    dnf install -y wireguard-tools iptables firewalld curl jq
else
    print_error "Unsupported OS: $OS"
    print_warning "Please install WireGuard manually"
    exit 1
fi

# 2. Enable IP forwarding
print_success "[2/6] Configuring kernel settings..."
cat > /etc/sysctl.d/99-wireguard.conf << EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.core.netdev_max_backlog=5000
net.ipv4.tcp_congestion_control=bbr
net.netfilter.nf_conntrack_max=262144
EOF
sysctl -p /etc/sysctl.d/99-wireguard.conf > /dev/null

# 3. Clean up existing WireGuard configuration (for reinstallation)
if [ -f ${WIREGUARD_DIR}/${VPN_INTERFACE}.conf ]; then
    print_warning "Existing WireGuard configuration found. Cleaning up..."
    wg-quick down ${VPN_INTERFACE} 2>/dev/null
    systemctl stop wg-quick@${VPN_INTERFACE} 2>/dev/null
    rm -f ${WIREGUARD_DIR}/${VPN_INTERFACE}.conf
    rm -f ${WIREGUARD_DIR}/server.key ${WIREGUARD_DIR}/server.pub
    rm -rf ${WIREGUARD_DIR}/clients/
    print_success "Existing configuration cleanup complete"
fi

# 4. Generate WireGuard keys
print_success "[4/6] Generating WireGuard server keys..."
mkdir -p ${WIREGUARD_DIR}
cd ${WIREGUARD_DIR}

# Generate server keys
wg genkey | tee server.key | wg pubkey > server.pub
SERVER_PRIVATE_KEY=$(cat server.key)
SERVER_PUBLIC_KEY=$(cat server.pub)

# 5. Create WireGuard configuration file
print_success "[5/6] Creating WireGuard configuration file..."
cat > ${WIREGUARD_DIR}/${VPN_INTERFACE}.conf << EOF
[Interface]
PrivateKey = ${SERVER_PRIVATE_KEY}
Address = ${VPN_SUBNET}.1/24
ListenPort = ${VPN_PORT}
SaveConfig = false

# NAT configuration
PostUp = iptables -t nat -A POSTROUTING -s ${VPN_SUBNET}.0/24 -j MASQUERADE
PostUp = iptables -A FORWARD -i ${VPN_INTERFACE} -j ACCEPT
PostUp = iptables -A FORWARD -o ${VPN_INTERFACE} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s ${VPN_SUBNET}.0/24 -j MASQUERADE
PostDown = iptables -D FORWARD -i ${VPN_INTERFACE} -j ACCEPT
PostDown = iptables -D FORWARD -o ${VPN_INTERFACE} -j ACCEPT

EOF

# 6. Generate and register 10 client keys
print_success "[6/7] Generating client keys (${VPN_START_IP} ~ ${VPN_END_IP})..."
mkdir -p ${WIREGUARD_DIR}/clients

for i in $(seq ${VPN_START_IP} ${VPN_END_IP}); do
    CLIENT_IP="${VPN_SUBNET}.${i}"
    echo -e "  Generating: ${CLIENT_IP}"

    # Generate client keys
    CLIENT_PRIVATE=$(wg genkey)
    CLIENT_PUBLIC=$(echo ${CLIENT_PRIVATE} | wg pubkey)

    # Add Peer to WireGuard
    cat >> ${WIREGUARD_DIR}/${VPN_INTERFACE}.conf << EOF

[Peer]
PublicKey = ${CLIENT_PUBLIC}
AllowedIPs = ${CLIENT_IP}/32
EOF

    # Create client configuration file
    cat > ${WIREGUARD_DIR}/clients/client_${i}.conf << EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE}
Address = ${CLIENT_IP}/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_IP}:${VPN_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
done

# 7. Generate JSON for API server integration
print_success "[7/7] Generating API integration data..."

# Create server registration JSON
cat > ${VPN_DIR}/server_register.json << EOF
{
  "public_ip": "${SERVER_IP}",
  "port": ${VPN_PORT},
  "server_pubkey": "${SERVER_PUBLIC_KEY}",
  "memo": "VPN Server ${SERVER_IP}"
}
EOF

# Create keys registration JSON
cat > ${VPN_DIR}/keys_register.json << EOF
{
  "public_ip": "${SERVER_IP}",
  "port": ${VPN_PORT},
  "keys": [
EOF

# Add key information as JSON array
FIRST=1
for i in $(seq ${VPN_START_IP} ${VPN_END_IP}); do
    if [ -f ${WIREGUARD_DIR}/clients/client_${i}.conf ]; then
        CLIENT_IP="${VPN_SUBNET}.${i}"
        CLIENT_PRIVATE=$(grep "PrivateKey" ${WIREGUARD_DIR}/clients/client_${i}.conf | cut -d'=' -f2 | xargs)
        CLIENT_PUBLIC=$(echo ${CLIENT_PRIVATE} | wg pubkey)

        if [ $FIRST -eq 0 ]; then
            echo "," >> ${VPN_DIR}/keys_register.json
        fi
        FIRST=0

        cat >> ${VPN_DIR}/keys_register.json << EOF
    {
      "internal_ip": "${CLIENT_IP}",
      "private_key": "${CLIENT_PRIVATE}",
      "public_key": "${CLIENT_PUBLIC}"
    }
EOF
    fi
done

cat >> ${VPN_DIR}/keys_register.json << EOF

  ]
}
EOF

# 8. Configure firewall (add VPN port only)
print_success "Configuring firewall..."
print_warning "Note: Only adding VPN port (${VPN_PORT}/udp). Existing settings like SSH will be preserved."

if [[ "$OS" == "ubuntu" ]]; then
    # Ubuntu UFW configuration
    ufw --force enable 2>/dev/null || true
    ufw allow ${VPN_PORT}/udp
    ufw allow ssh
    print_success "VPN port ${VPN_PORT}/udp added to UFW firewall"
    ufw status numbered
else
    # Rocky/RHEL firewalld configuration
    systemctl start firewalld 2>/dev/null || true
    systemctl enable firewalld 2>/dev/null || true

    # Check currently open ports
    echo "Currently open services/ports:"
    firewall-cmd --list-all | grep -E "services:|ports:" | head -2

    # Add VPN port only (preserve existing settings)
    firewall-cmd --permanent --add-port=${VPN_PORT}/udp
    firewall-cmd --permanent --add-masquerade
    firewall-cmd --reload

    print_success "VPN port ${VPN_PORT}/udp added"
    echo "Updated port list:"
    firewall-cmd --list-ports
fi

# 9. Start WireGuard
print_success "Starting WireGuard..."
wg-quick up ${VPN_INTERFACE}
systemctl enable wg-quick@${VPN_INTERFACE}

# 10. Completion message
echo
print_header "VPN Server Installation Complete!"
echo
print_info "Server information:"
echo -e "  IP: ${SERVER_IP}"
echo -e "  Port: ${VPN_PORT}"
echo -e "  Public Key: ${SERVER_PUBLIC_KEY}"
echo -e "  Subnet: ${VPN_SUBNET}.0/24"
echo -e "  Number of clients: $((VPN_END_IP - VPN_START_IP + 1))"
echo
print_info "Generated API registration files:"
echo -e "  Server: ${GREEN}${VPN_DIR}/server_register.json${NC}"
echo -e "  Keys:   ${GREEN}${VPN_DIR}/keys_register.json${NC}"
echo
print_info "Manual registration (if needed):"
echo -e "  ${GREEN}curl -X POST \"${API_URL}/server/register\" -H \"Content-Type: application/json\" -d @${VPN_DIR}/server_register.json${NC}"
echo -e "  ${GREEN}curl -X POST \"${API_URL}/keys/register\" -H \"Content-Type: application/json\" -d @${VPN_DIR}/keys_register.json${NC}"
echo
print_success "Client configuration files:"
echo -e "   ${WIREGUARD_DIR}/clients/ directory"
echo
echo -e "${GREEN}=====================================${NC}"

# Check status
wg show

# ========================================
# Automatic API Registration
# ========================================

echo ""
print_header "Registering VPN Server to Central API..."
echo ""

# Check and delete existing server
print_info "Checking existing server information..."
if curl -s "${API_URL}/status?ip=${SERVER_IP}" | jq '.success' | grep -q true; then
    print_warning "Existing server information found. Deleting..."
    curl -s "${API_URL}/release/all?ip=${SERVER_IP}&delete=true" > /dev/null
    print_success "Existing server information deleted"
    echo
fi

# 1. Register server information
print_info "Step 1/2: Registering server information..."
SERVER_RESPONSE=$(curl -s -X POST "${API_URL}/server/register" \
  -H "Content-Type: application/json" \
  -d @${VPN_DIR}/server_register.json)

if echo "$SERVER_RESPONSE" | jq '.success' 2>/dev/null | grep -q true; then
    SERVER_ID=$(echo "$SERVER_RESPONSE" | jq -r '.server_id // .data.server_id' 2>/dev/null)
    ACTION=$(echo "$SERVER_RESPONSE" | jq -r '.action // "registered"' 2>/dev/null)
    print_success "Server ${ACTION} (ID: ${SERVER_ID})"

    # 2. Register client keys in bulk
    TOTAL_KEYS=$((VPN_END_IP - VPN_START_IP + 1))
    print_info "Step 2/2: Registering ${TOTAL_KEYS} client keys..."
    KEYS_RESPONSE=$(curl -s -X POST "${API_URL}/keys/register" \
      -H "Content-Type: application/json" \
      -d @${VPN_DIR}/keys_register.json)

    if echo "$KEYS_RESPONSE" | jq '.success' 2>/dev/null | grep -q true; then
        REGISTERED=$(echo "$KEYS_RESPONSE" | jq -r '.registered // .data.registered' 2>/dev/null)
        TOTAL=$(echo "$KEYS_RESPONSE" | jq -r '.total // .data.total' 2>/dev/null)
        print_success "Keys registered: ${REGISTERED}/${TOTAL}"
        echo ""
        print_success "VPN server installation and API registration complete!"
    else
        print_warning "Key registration failed"
        echo "Response: $KEYS_RESPONSE"
    fi
else
    print_warning "Server registration failed"
    echo "Response: $SERVER_RESPONSE"
fi

echo ""
print_info "Available commands:"
echo -e "  # Check server list"
echo -e "  curl ${API_URL}/list"
echo ""
echo -e "  # Test key allocation"
echo -e "  curl \"${API_URL}/allocate?ip=${SERVER_IP}\""

# ========================================
# Heartbeat Configuration
# ========================================

echo ""
print_header "Configuring Heartbeat..."
echo ""

# Add Heartbeat script to crontab
if ! crontab -l 2>/dev/null | grep -q "vpn_heartbeat.sh"; then
    (crontab -l 2>/dev/null; echo "*/1 * * * * ${VPN_DIR}/vpn_heartbeat.sh > /dev/null 2>&1") | crontab -
    print_success "Heartbeat cron registered (runs every minute)"
else
    print_warning "Heartbeat cron already registered"
fi

print_success "VPN server will send status to central API every minute"