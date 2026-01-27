#!/bin/bash

# ============================================================
# WireGuard VPN Server Setup Script
# ============================================================
# This script sets up WireGuard VPN server on Ubuntu 24.04 VPS:
# - Generates server keypair
# - Creates WireGuard server configuration
# - Configures NAT/masquerading for internet egress
# - Enables IP forwarding
# - Starts and enables WireGuard service
#
# Client management is done separately using: ./manage_wg_client.sh
#
# Prerequisites:
# 1. Ubuntu 24.04 VPS with public IP
# 2. Configuration in workstation.env (WG_SERVER_PORT, WG_SERVER_ADDRESS, etc.)
#
# Usage: sudo ./setup_wg.sh
# ============================================================

set -e  # Exit on any error

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Helper Functions ---
print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "\n${BLUE}======================================================${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}======================================================${NC}\n"; }

# --- Check if running as root ---
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# --- Load Configuration ---
print_message "Loading configuration from workstation.env..."
ENV_FILE="./workstation.env"
if [[ ! -f "$ENV_FILE" ]]; then
    print_error "Configuration file not found: $ENV_FILE"
    exit 1
fi
source "$ENV_FILE"
print_message "Configuration loaded successfully."

# --- Validate Configuration ---
if [[ -z "$WG_SERVER_PORT" ]]; then
    print_error "WG_SERVER_PORT is not set in workstation.env"
    exit 1
fi

if [[ -z "$WG_SERVER_ADDRESS" ]]; then
    print_error "WG_SERVER_ADDRESS is not set in workstation.env"
    exit 1
fi

# Detect VPS IP if not set
if [[ -z "$VPS_PUBLIC_IP" ]]; then
    VPS_PUBLIC_IP=$(hostname -I | awk '{print $1}')
    print_message "Auto-detected VPS IP: $VPS_PUBLIC_IP"
fi

# Detect default network interface
DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
if [[ -z "$DEFAULT_INTERFACE" ]]; then
    print_error "Could not detect default network interface"
    exit 1
fi

print_header "WireGuard VPN Server Setup"
echo -e "${CYAN}VPS IP:${NC} $VPS_PUBLIC_IP"
echo -e "${CYAN}WireGuard Port:${NC} $WG_SERVER_PORT"
echo -e "${CYAN}VPN Subnet:${NC} $WG_SERVER_ADDRESS"
echo -e "${CYAN}Network Interface:${NC} $DEFAULT_INTERFACE"
echo ""

# Step 1: Create WireGuard directory structure
print_header "Step 1/5: Creating WireGuard Directory Structure"
mkdir -p /etc/wireguard/clients
chmod 700 /etc/wireguard
print_message "✓ Directory structure created"

# Step 2: Generate server keypair
print_header "Step 2/5: Generating Server Keypair"
if [[ -f /etc/wireguard/server_private.key ]]; then
    print_warning "Server keypair already exists, skipping generation"
    WG_SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private.key)
    WG_SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)
else
    print_message "Generating server private key..."
    wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
    chmod 600 /etc/wireguard/server_private.key
    WG_SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private.key)
    WG_SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)
    print_message "✓ Server keypair generated"
fi

echo -e "${CYAN}Server Public Key:${NC} $WG_SERVER_PUBLIC_KEY"

# Step 3: Create server configuration
print_header "Step 3/5: Creating Server Configuration"

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = $WG_SERVER_ADDRESS
ListenPort = $WG_SERVER_PORT
PrivateKey = $WG_SERVER_PRIVATE_KEY

# NAT and forwarding rules
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE

# Clients will be added using ./manage_wg_client.sh

EOF

chmod 600 /etc/wireguard/wg0.conf
print_message "✓ Server configuration created: /etc/wireguard/wg0.conf"
print_message "✓ Use ./manage_wg_client.sh to add clients"

# Step 4: Enable IP forwarding
print_header "Step 4/5: Enabling IP Forwarding"

sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

# Make persistent
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
fi
if ! grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
    echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
fi

print_message "✓ IP forwarding enabled and persisted"

# Step 5: Start WireGuard service
print_header "Step 5/5: Starting WireGuard Service"

# Enable and start WireGuard
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

# Wait for service to start
sleep 2

# Check service status
if systemctl is-active --quiet wg-quick@wg0; then
    print_message "✓ WireGuard service started successfully"
else
    print_error "WireGuard service failed to start!"
    print_error "Check logs with: journalctl -u wg-quick@wg0 -n 50"
    exit 1
fi

# Verify WireGuard interface is up
if ip link show wg0 &> /dev/null; then
    print_message "✓ WireGuard interface wg0 is UP"
else
    print_error "WireGuard interface wg0 is not up!"
    exit 1
fi

# Display WireGuard status
print_header "WireGuard Status"
wg show wg0

print_header "Setup Complete!"

echo -e "${GREEN}WireGuard VPN server successfully installed and configured!${NC}\n"

echo -e "${CYAN}Server Information:${NC}"
echo -e "  VPS IP:           ${GREEN}$VPS_PUBLIC_IP${NC}"
echo -e "  WireGuard Port:   ${GREEN}$WG_SERVER_PORT${NC}"
echo -e "  VPN Subnet:       ${GREEN}$WG_SERVER_ADDRESS${NC}"
echo -e "  Interface:        ${GREEN}wg0${NC}"
echo -e "  Public Key:       ${GREEN}$WG_SERVER_PUBLIC_KEY${NC}"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. ${BLUE}Add WireGuard clients:${NC}"
echo -e "   ${CYAN}sudo ./manage_wg_client.sh add laptop${NC}"
echo -e "   ${CYAN}sudo ./manage_wg_client.sh add phone${NC}"
echo ""
echo -e "2. ${BLUE}List all clients:${NC}"
echo -e "   ${CYAN}sudo ./manage_wg_client.sh list${NC}"
echo ""
echo -e "3. ${BLUE}Show QR code for mobile:${NC}"
echo -e "   ${CYAN}sudo ./manage_wg_client.sh qr phone${NC}"
echo ""
echo -e "4. ${BLUE}Test VPN connection:${NC}"
echo -e "   - Connect with WireGuard client"
echo -e "   - Verify exit IP: ${CYAN}curl ifconfig.me${NC} (should show ${GREEN}$VPS_PUBLIC_IP${NC})"
echo ""
echo -e "5. ${BLUE}Monitor WireGuard:${NC}"
echo -e "   - Status: ${CYAN}sudo wg show${NC}"
echo -e "   - Service: ${CYAN}sudo systemctl status wg-quick@wg0${NC}"
echo -e "   - Logs: ${CYAN}sudo journalctl -u wg-quick@wg0 -f${NC}"
echo ""

echo -e "${GREEN}Setup completed at $(date)${NC}"

exit 0
