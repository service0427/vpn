# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a WireGuard VPN server installation script that creates 10 pre-configured client keys. The server ONLY handles VPN connections - all key management is done via external API at http://220.121.120.83/vpn_api/

## Repository Information

**IMPORTANT: GitHub Repository Structure**
- **This repository**: https://github.com/service0427/vpn
- **Push location**: All VPN server code in `/home/vpn/` must be pushed to this repository
- **Future projects**: `vpn-mobile` will be created in a separate repository (not yet created)

When pushing to GitHub:
```bash
cd /home/vpn
git add -A
git commit -m "Your commit message"
git push origin main
```

## Key Components

### Scripts (in /home/vpn/)
- `install.sh` - One-click installation entry point
- `install_vpn_server.sh` - VPN server setup
  - Creates 10 WireGuard peers (10.8.0.10 - 10.8.0.19)
  - Auto-registers with API at http://220.121.120.83/vpn_api/
  - Handles reinstallation (deletes old data automatically)
- `uninstall_vpn.sh` - Complete VPN removal
  - Removes WireGuard configuration
  - Deletes server from API
- `check_firewall.sh` - Firewall status check
- `vpn_heartbeat.sh` - Server heartbeat to API
- `common.sh` - Shared functions and configuration

### Generated Files
- `/etc/wireguard/wg0.conf` - Server configuration
- `/etc/wireguard/clients/` - Client config files (10 files)
- `/home/vpn/server_register.json` - Server registration data
- `/home/vpn/keys_register.json` - Client keys registration data

## One-Click Installation

```bash
curl -sL https://github.com/service0427/vpn/raw/main/install.sh | sudo bash
```

This command:
1. Downloads all required scripts
2. Installs and configures WireGuard VPN server
3. Registers server and keys with API
4. Sets up auto-reinstall on reboot (for IP changes)

## Common Commands

```bash
# Check VPN status
wg show

# Restart WireGuard
wg-quick down wg0 && wg-quick up wg0

# Check firewall
/home/vpn/check_firewall.sh

# Reinstall VPN server
/home/vpn/install_vpn_server.sh

# Remove VPN server
/home/vpn/uninstall_vpn.sh

# Check cron jobs
crontab -l
```

## External API Integration

All key allocation/management is handled by external API:
- **Base URL**: http://220.121.120.83/vpn_api/
- **Server Register**: POST /server/register
- **Keys Register**: POST /keys/register
- **Allocate Key**: GET /allocate
- **Release Key**: POST /release
- **Server Heartbeat**: GET /server/heartbeat

### API Registration Process

**Step 1: Register Server**
```bash
curl -X POST "http://220.121.120.83/vpn_api/server/register" \
  -H "Content-Type: application/json" \
  -d @/home/vpn/server_register.json
```

**Step 2: Register Keys**
```bash
curl -X POST "http://220.121.120.83/vpn_api/keys/register" \
  -H "Content-Type: application/json" \
  -d @/home/vpn/keys_register.json
```

## Important Notes

1. This server does NOT run any API services
2. All API functionality is at http://220.121.120.83/vpn_api/
3. System supports exactly 10 concurrent connections
4. IP range fixed to 10.8.0.10-19
5. VPN port: 55555/UDP
6. Auto-reboot registration enabled (cron-based)
7. All messages are in English (VMware compatibility)
8. Code is modularized using common.sh

## Auto-Reboot Feature

The installation automatically sets up a cron job that:
- Runs on every reboot
- Waits for network connectivity (ping check)
- Reinstalls VPN server with new IP
- Re-registers to API automatically
- Runs silently (no disk logs)

This is useful when running in VMware with bridge networking that may change IPs.

## Development Notes

- All scripts use `common.sh` for shared functions
- Color-coded output: GREEN (success), YELLOW (info), RED (error)
- No Korean characters (English only for VMware)
- Clean, modular code structure
- No legacy SQL code (removed)
