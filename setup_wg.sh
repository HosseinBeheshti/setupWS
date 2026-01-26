#!/bin/bash

# ============================================================
# WireGuard VPN Server Setup Script
# ============================================================
# This script sets up WireGuard VPN server on Ubuntu 24.04 VPS:
# - Generates server and client keypairs
# - Creates WireGuard server configuration
# - Configures NAT/masquerading for internet egress
# - Enables IP forwarding
# - Generates client configuration files and QR codes
# - Starts and enables WireGuard service
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
print_header() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}========================================${NC}\n"; }

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

if [[ -z "$WG_CLIENT_COUNT" ]]; then
    print_warning "WG_CLIENT_COUNT not set, defaulting to 3 clients"
    WG_CLIENT_COUNT=3
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
echo -e "${CYAN}Clients to generate:${NC} $WG_CLIENT_COUNT"
echo -e "${CYAN}Network Interface:${NC} $DEFAULT_INTERFACE"
echo ""

# Step 1: Create WireGuard directory structure
print_header "Step 1/6: Creating WireGuard Directory Structure"
mkdir -p /etc/wireguard/clients
chmod 700 /etc/wireguard
print_message "✓ Directory structure created"

# Step 2: Generate server keypair
print_header "Step 2/6: Generating Server Keypair"
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

# Step 3: Generate client keypairs and configurations
print_header "Step 3/6: Generating Client Keypairs and Configurations"

# Extract network prefix from WG_SERVER_ADDRESS (e.g., 10.8.0 from 10.8.0.1/24)
WG_NETWORK_PREFIX=$(echo $WG_SERVER_ADDRESS | cut -d'.' -f1-3)

# Array to store client public keys for server config
declare -a CLIENT_PUBLIC_KEYS
declare -a CLIENT_IPS

for ((i=1; i<=WG_CLIENT_COUNT; i++)); do
    CLIENT_NAME="client$i"
    CLIENT_IP="${WG_NETWORK_PREFIX}.$((i+1))"
    CLIENT_IPS+=("$CLIENT_IP")
    
    print_message "Generating configuration for $CLIENT_NAME (IP: $CLIENT_IP/32)..."
    
    if [[ -f /etc/wireguard/clients/${CLIENT_NAME}_private.key ]]; then
        print_warning "Client $CLIENT_NAME keypair already exists, skipping generation"
        CLIENT_PRIVATE_KEY=$(cat /etc/wireguard/clients/${CLIENT_NAME}_private.key)
        CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/clients/${CLIENT_NAME}_public.key)
    else
        # Generate client keypair
        wg genkey | tee /etc/wireguard/clients/${CLIENT_NAME}_private.key | wg pubkey > /etc/wireguard/clients/${CLIENT_NAME}_public.key
        chmod 600 /etc/wireguard/clients/${CLIENT_NAME}_private.key
        CLIENT_PRIVATE_KEY=$(cat /etc/wireguard/clients/${CLIENT_NAME}_private.key)
        CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/clients/${CLIENT_NAME}_public.key)
    fi
    
    CLIENT_PUBLIC_KEYS+=("$CLIENT_PUBLIC_KEY")
    
    # Create client configuration file
    cat > /etc/wireguard/clients/${CLIENT_NAME}.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/32
DNS = $WG_CLIENT_DNS

[Peer]
PublicKey = $WG_SERVER_PUBLIC_KEY
Endpoint = $VPS_PUBLIC_IP:$WG_SERVER_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    
    print_message "  ✓ Configuration created: /etc/wireguard/clients/${CLIENT_NAME}.conf"
    
    # Generate QR code for mobile clients
    if command -v qrencode &> /dev/null; then
        qrencode -t ansiutf8 < /etc/wireguard/clients/${CLIENT_NAME}.conf > /etc/wireguard/clients/${CLIENT_NAME}_qr.txt
        print_message "  ✓ QR code generated: /etc/wireguard/clients/${CLIENT_NAME}_qr.txt"
    fi
done

print_message "✓ Generated $WG_CLIENT_COUNT client configurations"

# Step 4: Create server configuration
print_header "Step 4/6: Creating Server Configuration"

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = $WG_SERVER_ADDRESS
ListenPort = $WG_SERVER_PORT
PrivateKey = $WG_SERVER_PRIVATE_KEY

# NAT and forwarding rules
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE

EOF

# Add each client as a peer
for ((i=0; i<WG_CLIENT_COUNT; i++)); do
    cat >> /etc/wireguard/wg0.conf <<EOF
# Client $((i+1))
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEYS[$i]}
AllowedIPs = ${CLIENT_IPS[$i]}/32

EOF
done

chmod 600 /etc/wireguard/wg0.conf
print_message "✓ Server configuration created: /etc/wireguard/wg0.conf"

# Step 5: Enable IP forwarding
print_header "Step 5/6: Enabling IP Forwarding"

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

# Step 6: Start WireGuard service
print_header "Step 6/6: Starting WireGuard Service"

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

echo -e "${CYAN}Client Configurations:${NC}"
echo -e "  Location: ${GREEN}/etc/wireguard/clients/${NC}"
echo -e "  Generated: ${GREEN}$WG_CLIENT_COUNT client(s)${NC}"
echo ""

for ((i=1; i<=WG_CLIENT_COUNT; i++)); do
    CLIENT_NAME="client$i"
    CLIENT_IP="${WG_NETWORK_PREFIX}.$((i+1))"
    echo -e "  ${YELLOW}$CLIENT_NAME:${NC}"
    echo -e "    Config file: ${GREEN}/etc/wireguard/clients/${CLIENT_NAME}.conf${NC}"
    echo -e "    QR code:     ${GREEN}/etc/wireguard/clients/${CLIENT_NAME}_qr.txt${NC}"
    echo -e "    VPN IP:      ${GREEN}$CLIENT_IP${NC}"
    echo ""
done

echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. ${BLUE}Distribute client configurations:${NC}"
echo -e "   - Desktop: Copy .conf files to client devices"
echo -e "   - Mobile: Display QR codes with: ${CYAN}cat /etc/wireguard/clients/client1_qr.txt${NC}"
echo ""
echo -e "2. ${BLUE}Test VPN connection:${NC}"
echo -e "   - Connect with WireGuard client"
echo -e "   - Verify exit IP: ${CYAN}curl ifconfig.me${NC} (should show ${GREEN}$VPS_PUBLIC_IP${NC})"
echo ""
echo -e "3. ${BLUE}Monitor WireGuard:${NC}"
echo -e "   - Status: ${CYAN}sudo wg show${NC}"
echo -e "   - Service: ${CYAN}sudo systemctl status wg-quick@wg0${NC}"
echo -e "   - Logs: ${CYAN}sudo journalctl -u wg-quick@wg0 -f${NC}"
echo ""

echo -e "${GREEN}Setup completed at $(date)${NC}"

exit 0
