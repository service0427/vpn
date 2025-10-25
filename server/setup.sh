#!/bin/bash

#######################################
# VPN Server Auto Install Script
# Automatically install and configure WireGuard VPN server
#######################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    log_error "This script requires root privileges"
    exit 1
fi

log_info "Starting VPN server installation..."

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
    log_info "Detected OS: $OS $VER"
else
    log_error "Unsupported OS"
    exit 1
fi

# Package manager setup
case $OS in
    ubuntu|debian)
        PKG_UPDATE="apt update"
        PKG_INSTALL="apt install -y"
        ;;
    rocky|centos|rhel|fedora)
        PKG_UPDATE="dnf check-update || true"
        PKG_INSTALL="dnf install -y"
        ;;
    *)
        log_error "Unsupported OS: $OS"
        exit 1
        ;;
esac

# Detect main network interface
log_info "Detecting network interface..."
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -z "$MAIN_INTERFACE" ]; then
    log_error "Cannot find main network interface"
    exit 1
fi
log_success "Main interface: $MAIN_INTERFACE"

# Get public IP
log_info "Getting public IP..."
PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "")
if [ -z "$PUBLIC_IP" ]; then
    log_error "Cannot auto-detect public IP"
    exit 1
fi
log_success "Public IP: $PUBLIC_IP"

# Auto-generate VPN name from IP
VPN_NAME="vpn-$(echo $PUBLIC_IP | tr '.' '-')"
REGION="KR"

log_info "VPN name: $VPN_NAME"
log_info "Region: $REGION"

# Install WireGuard and required tools
log_info "Installing WireGuard and tools..."
$PKG_UPDATE

case $OS in
    rocky|centos|rhel|fedora)
        $PKG_INSTALL wireguard-tools iptables iptables-services curl jq
        ;;
    ubuntu|debian)
        $PKG_INSTALL wireguard-tools iptables curl jq
        ;;
esac

if ! command -v wg &> /dev/null; then
    log_error "WireGuard installation failed"
    exit 1
fi

if ! command -v iptables &> /dev/null; then
    log_error "iptables installation failed"
    exit 1
fi

log_success "WireGuard and iptables installed"

# Create WireGuard directory
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# Generate server keys
log_info "Generating server keys..."
if [ ! -f /etc/wireguard/server-private.key ]; then
    wg genkey | tee /etc/wireguard/server-private.key | wg pubkey > /etc/wireguard/server-public.key
    chmod 600 /etc/wireguard/server-private.key
    log_success "Server keys generated"
else
    log_warn "Server keys already exist (reusing)"
fi

SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server-private.key)
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server-public.key)

# Generate client keys
log_info "Generating client keys..."
if [ ! -f /etc/wireguard/client-private.key ]; then
    wg genkey | tee /etc/wireguard/client-private.key | wg pubkey > /etc/wireguard/client-public.key
    chmod 600 /etc/wireguard/client-private.key
    log_success "Client keys generated"
else
    log_warn "Client keys already exist (reusing)"
fi

CLIENT_PRIVATE_KEY=$(cat /etc/wireguard/client-private.key)
CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/client-public.key)

# Create WireGuard server config
log_info "Creating WireGuard server config..."
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIVATE_KEY

# IP forwarding and NAT
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE

# Client config
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = 10.8.0.2/32
EOF

chmod 600 /etc/wireguard/wg0.conf
log_success "Server config created"

# Enable IP forwarding permanently
log_info "Enabling IP forwarding..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1 > /dev/null
log_success "IP forwarding enabled"

# Configure firewall
log_info "Configuring firewall..."
if command -v firewall-cmd &> /dev/null; then
    log_info "Configuring firewalld..."
    systemctl enable firewalld --now 2>/dev/null || true
    firewall-cmd --permanent --add-port=51820/udp
    firewall-cmd --permanent --add-masquerade
    firewall-cmd --reload
    log_success "firewalld configured"
elif command -v ufw &> /dev/null; then
    log_info "Configuring UFW..."
    ufw allow 51820/udp
    ufw --force enable
    log_success "UFW configured"
else
    log_warn "No firewall found - using iptables directly"
    iptables -A INPUT -p udp --dport 51820 -j ACCEPT
    log_warn "iptables rules may not persist after reboot"
fi

# Start WireGuard service
log_info "Starting WireGuard service..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

if systemctl is-active --quiet wg-quick@wg0; then
    log_success "WireGuard service started"
else
    log_error "WireGuard service start failed"
    exit 1
fi

# Create client config file
CLIENT_CONFIG="/etc/wireguard/client.conf"
cat > $CLIENT_CONFIG <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = 10.8.0.2/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $PUBLIC_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 $CLIENT_CONFIG

# Print completion message
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "VPN server installation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}Server Info:${NC}"
echo "  - Public IP: $PUBLIC_IP"
echo "  - VPN Subnet: 10.8.0.0/24"
echo "  - Server Address: 10.8.0.1"
echo "  - Client Address: 10.8.0.2"
echo ""
echo -e "${BLUE}Client Config File:${NC}"
echo "  Location: $CLIENT_CONFIG"
echo ""
echo -e "${YELLOW}Copy this config file to client server!${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Client Config Content:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat $CLIENT_CONFIG
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}VPN Status:${NC}"
wg show
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "  1. Copy the client config above"
echo "  2. Run setup.sh on client server"
echo "  3. Run add.sh with the config"
echo ""

# Register to API
log_info "Registering to API server..."
API_HOST="220.121.120.83"

# WireGuard interface name (wg-{name})
WG_INTERFACE="wg-${VPN_NAME}"

# SSH connection info (root@public_ip)
SSH_HOST="root@${PUBLIC_IP}"

# API call with debug output
log_info "API Host: $API_HOST"
log_info "VPN Name: $VPN_NAME"
log_info "Interface: $WG_INTERFACE"

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://$API_HOST/api/vpn/register \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$VPN_NAME\",
        \"host\": \"$SSH_HOST\",
        \"public_ip\": \"$PUBLIC_IP\",
        \"interface\": \"$WG_INTERFACE\",
        \"region\": \"$REGION\",
        \"port\": 51820,
        \"description\": \"Auto-generated by setup.sh\"
    }")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

echo "API Response (HTTP $HTTP_CODE):"
echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"

if [ "$HTTP_CODE" = "200" ] && echo "$BODY" | jq -e '.success' > /dev/null 2>&1; then
    log_success "API registration complete: $VPN_NAME"
else
    log_warn "API registration failed (VPN is still working)"
    echo "Debug: Check API server at http://$API_HOST/health"
fi

echo ""
echo -e "${BLUE}API Info:${NC}"
echo "  - VPN Name: $VPN_NAME"
echo "  - Interface: $WG_INTERFACE"
echo "  - API Server: $API_HOST"
echo ""
