# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a WireGuard VPN server installation script that creates 10 pre-configured client keys. The server ONLY handles VPN connections - all key management is done via external API at http://220.121.120.83/vpn_api/

## Key Components

### Scripts
- `/home/vpn/install_vpn_server.sh` - One-click VPN server setup
  - Creates 10 WireGuard peers (10.8.0.10 - 10.8.0.19)
  - Auto-registers with API at http://220.121.120.83/vpn_api/
  - Handles reinstallation (deletes old data automatically)
- `/home/vpn/uninstall_vpn.sh` - Complete VPN removal
  - Removes WireGuard configuration
  - Deletes server from API

### Generated Files
- `/etc/wireguard/wg0.conf` - Server configuration
- `/etc/wireguard/clients/` - Client config files
- `/home/vpn/vpn_server_data.json` - JSON data for API registration

## Common Commands

```bash
# Install VPN server
sudo ./install_vpn_server.sh

# Check VPN status
wg show

# Restart WireGuard
wg-quick down wg0 && wg-quick up wg0
```

## External API Integration

All key allocation/management is handled by external API:
- **Base URL**: http://220.121.120.83/vpn_api/
- **Allocate**: GET /allocate
- **Release**: POST /release
- **Server Register**: POST /server/register (needs development)
- **Bulk Keys**: POST /keys/bulk (needs development)

## Important Notes

1. This server does NOT run any API services
2. All API functionality moved to http://220.121.120.83/vpn_api/
3. Only maintain the installation script and usage documentation
4. System supports exactly 10 concurrent connections
5. IP range fixed to 10.8.0.10-19