#!/bin/bash

#====================================
# VPN Common Functions and Settings
# - Used by all VPN scripts
#====================================

# Color definitions
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export NC='\033[0m' # No Color

# VPN configuration constants
export VPN_INTERFACE="wg0"
export VPN_PORT="55555"
export VPN_SUBNET="10.8.0"
export VPN_START_IP=10
export VPN_END_IP=19
export API_URL="http://220.121.120.83/vpn_api"
export VPN_DIR="/home/vpn"
export WIREGUARD_DIR="/etc/wireguard"

# Get server public IP
get_server_ip() {
    curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "unknown"
}

# Get main network interface
get_main_interface() {
    ip route | grep '^default' | head -1 | awk '{print $5}'
}

# Get local IP (main interface)
get_local_ip() {
    local interface=$(get_main_interface)
    if [ -z "$interface" ]; then
        echo "unknown"
        return 1
    fi
    ip -4 addr show "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1
}

# Color message output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}$1${NC}"
}

# Print header
print_header() {
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}   $1${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# Check root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script requires root privileges."
        echo "Please run with sudo: sudo $0"
        exit 1
    fi
}

# Check file existence
check_file() {
    if [ ! -f "$1" ]; then
        print_error "File not found: $1"
        return 1
    fi
    return 0
}

# Check WireGuard installation
check_wireguard() {
    if ! command -v wg &> /dev/null; then
        print_error "WireGuard is not installed."
        return 1
    fi
    return 0
}

# API call (GET)
api_get() {
    local endpoint="$1"
    curl -s --connect-timeout 10 "${API_URL}${endpoint}"
}

# API call (POST JSON)
api_post() {
    local endpoint="$1"
    local data="$2"
    curl -s --connect-timeout 10 \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$data" \
        "${API_URL}${endpoint}"
}

# API call (POST file)
api_post_file() {
    local endpoint="$1"
    local file="$2"
    curl -s --connect-timeout 10 \
        -X POST \
        -H "Content-Type: application/json" \
        -d @"$file" \
        "${API_URL}${endpoint}"
}
