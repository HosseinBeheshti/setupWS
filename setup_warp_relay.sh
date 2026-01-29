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
apt-get install -y socat iptables-persistent

# Cloudflare MASQUE endpoint (for Iran filtering bypass)
CLOUDFLARE_WARP_IP="162.159.197.5"
CLOUDFLARE_WARP_PORT="443"

# Local relay port (using standard HTTPS port for better firewall traversal)
RELAY_PORT="${WARP_ROUTING_PORT:-443}"

echo -e "${GREEN}Configuring iptables NAT for WARP relay...${NC}"

# Enable IP forwarding (already enabled by setup_virtual_router.sh, but ensure it's set)
sysctl -w net.ipv4.ip_forward=1

# Remove any existing rules for this port
iptables -t nat -D PREROUTING -p udp --dport ${RELAY_PORT} -j DNAT --to-destination ${CLOUDFLARE_WARP_IP}:${CLOUDFLARE_WARP_PORT} 2>/dev/null || true
iptables -t nat -D POSTROUTING -p udp -d ${CLOUDFLARE_WARP_IP} --dport ${CLOUDFLARE_WARP_PORT} -j MASQUERADE 2>/dev/null || true

# Add NAT rules for WARP relay
iptables -t nat -A PREROUTING -p udp --dport ${RELAY_PORT} -j DNAT --to-destination ${CLOUDFLARE_WARP_IP}:${CLOUDFLARE_WARP_PORT}
iptables -t nat -A POSTROUTING -p udp -d ${CLOUDFLARE_WARP_IP} --dport ${CLOUDFLARE_WARP_PORT} -j MASQUERADE

# Save iptables rules
netfilter-persistent save

echo -e "${GREEN}✓ iptables NAT rules configured${NC}"

# Configure firewall with iptables
echo -e "${GREEN}Configuring iptables firewall for WARP relay...${NC}"

# Allow incoming UDP on relay port
iptables -C INPUT -p udp --dport ${RELAY_PORT} -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport ${RELAY_PORT} -j ACCEPT

# Save iptables rules
netfilter-persistent save

echo -e "${GREEN}✓ Firewall configured to allow port ${RELAY_PORT}/udp${NC}"

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}WARP Relay Setup Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "${GREEN}Relay Configuration:${NC}"
echo -e "  Listen Port:      ${RELAY_PORT}/udp"
echo -e "  Forward To:       ${CLOUDFLARE_WARP_IP}:${CLOUDFLARE_WARP_PORT}"
echo -e "  VPS Public IP:    ${VPS_PUBLIC_IP}"
echo -e "  Method:           iptables NAT"
echo ""
echo -e "${YELLOW}Client Configuration:${NC}"
echo -e "  sudo warp-cli tunnel endpoint set ${VPS_PUBLIC_IP}:${RELAY_PORT}"
echo ""
echo -e "${YELLOW}Verify NAT Rules:${NC}"
echo -e "  sudo iptables -t nat -L -n -v | grep ${RELAY_PORT}"
echo ""
echo -e "${YELLOW}Monitor Traffic:${NC}"
echo -e "  sudo tcpdump -i any -n udp port ${RELAY_PORT}"
echo ""
