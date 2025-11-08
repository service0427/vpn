#!/bin/bash

# Setup script to enable automatic VPN installation on reboot
# This ensures VPN server re-registers with updated IP after VM bridge changes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up automatic VPN installation on reboot..."

# Create the cron job entry - waits for network, no logs
CRON_ENTRY="@reboot while ! ping -c 1 8.8.8.8 >/dev/null 2>&1; do sleep 1; done && curl -sL https://github.com/service0427/vpn/raw/main/install.sh | sudo bash >/dev/null 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "github.com/service0427/vpn/raw/main/install.sh"; then
    echo "Cron job already exists. Removing old entry..."
    crontab -l 2>/dev/null | grep -v "github.com/service0427/vpn/raw/main/install.sh" | crontab - || true
fi

# Add the cron job
(crontab -l 2>/dev/null || true; echo "$CRON_ENTRY") | crontab -

echo "✓ Cron job added successfully!"
echo ""
echo "The VPN server will automatically reinstall on every reboot."
echo "This ensures the server re-registers with the API when IP changes."
echo ""
echo "Network readiness check: ping 8.8.8.8 (retries every 1 second)"
echo "No logs written to disk (saves space)"
echo ""
echo "To view current cron jobs:"
echo "  crontab -l"
echo ""
echo "To remove auto-install:"
echo "  crontab -l | grep -v 'github.com/service0427/vpn' | crontab -"
