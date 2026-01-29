#!/bin/bash

# setup_warp_relay.sh - Configure WARP UDP relay using socat
# This relays WARP client traffic through your VPS to Cloudflare's WireGuard endpoint
# Bypasses ISP filtering of Cloudflare IPs (critical for Iran and similar regions)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workstation.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}WARP UDP Relay Setup${NC}"
echo -e "${GREEN}================================${NC}"

# Check if WARP routing is enabled
if [ "$WARP_ROUTING_ENABLED" != "true" ]; then
    echo -e "${YELLOW}WARP routing is not enabled in workstation.env${NC}"
    echo -e "${YELLOW}Skipping WARP relay setup...${NC}"
    exit 0
fi

echo -e "${GREEN}Installing socat for UDP relay...${NC}"
apt-get update
apt-get install -y socat

# Cloudflare MASQUE endpoint (for Iran filtering bypass)
CLOUDFLARE_WARP_IP="162.159.197.5"
CLOUDFLARE_WARP_PORT="443"

# Local relay port (using standard HTTPS port for better firewall traversal)
RELAY_PORT="${WARP_ROUTING_PORT:-443}"

echo -e "${GREEN}Creating systemd service for WARP relay...${NC}"

cat > /etc/systemd/system/warp-relay.service <<EOF
[Unit]
Description=WARP UDP Relay to Cloudflare MASQUE
Documentation=https://github.com/HosseinBeheshti/setupWS
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/socat UDP4-LISTEN:${RELAY_PORT},fork,reuseaddr UDP4:${CLOUDFLARE_WARP_IP}:${CLOUDFLARE_WARP_PORT}
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}Enabling and starting warp-relay service...${NC}"
systemctl daemon-reload
systemctl enable warp-relay
systemctl restart warp-relay

# Wait for service to start
sleep 2

# Check service status
if systemctl is-active --quiet warp-relay; then
    echo -e "${GREEN}✓ WARP relay service is running${NC}"
else
    echo -e "${RED}✗ WARP relay service failed to start${NC}"
    systemctl status warp-relay --no-pager
    exit 1
fi

# Configure firewall
echo -e "${GREEN}Configuring firewall for WARP relay...${NC}"
ufw allow ${RELAY_PORT}/udp comment "WARP UDP Relay"

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}WARP Relay Setup Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "${GREEN}Relay Configuration:${NC}"
echo -e "  Listen Port:      ${RELAY_PORT}/udp"
echo -e "  Forward To:       ${CLOUDFLARE_WARP_IP}:${CLOUDFLARE_WARP_PORT}"
echo -e "  VPS Public IP:    ${VPS_PUBLIC_IP}"
echo ""
echo -e "${YELLOW}Client Configuration:${NC}"
echo -e "  warp-cli registration set-custom-endpoint ${VPS_PUBLIC_IP}:${RELAY_PORT}"
echo ""
echo -e "${YELLOW}Monitor Relay:${NC}"
echo -e "  sudo journalctl -u warp-relay -f"
echo ""
echo -e "${YELLOW}Service Control:${NC}"
echo -e "  sudo systemctl status warp-relay"
echo -e "  sudo systemctl restart warp-relay"
echo -e "  sudo systemctl stop warp-relay"
echo ""
