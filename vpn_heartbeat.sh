#!/bin/bash

#====================================
# VPN Server Heartbeat Script
# - Sends server status to central API every minute
# - Runs silently without logs
#====================================

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || source /home/vpn/common.sh

# Get main network interface (using default route)
MAIN_INTERFACE=$(get_main_interface)

if [ -z "$MAIN_INTERFACE" ]; then
    # Exit if main interface not found
    exit 0
fi

# Get local IP from main interface
SERVER_IP=$(get_local_ip)

# If private IP, get public IP
if [[ $SERVER_IP =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.) ]]; then
    SERVER_IP=$(get_server_ip)
fi

# Collect RX/TX bytes (main ethernet interface)
RX=$(ip -s link show $MAIN_INTERFACE 2>/dev/null | grep -A1 "RX:" | tail -1 | awk '{print $1}')
TX=$(ip -s link show $MAIN_INTERFACE 2>/dev/null | grep -A1 "TX:" | tail -1 | awk '{print $1}')

# Set default values
RX=${RX:-0}
TX=${TX:-0}

# Send heartbeat (no logs)
curl -s --connect-timeout 5 "${API_URL}/server/heartbeat?ip=$SERVER_IP&interface=$MAIN_INTERFACE&rx=$RX&tx=$TX" > /dev/null 2>&1

exit 0
