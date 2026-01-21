#!/bin/bash

################################################################################
# WireGuard Peer Provisioning Script
# Description: Automates WireGuard peer creation with SQLite tracking
# Usage: sudo ./add_wg_peer.sh <username>
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DB_PATH="/var/lib/ztna/users.db"
WG_CONFIG="/etc/wireguard/wg0.conf"
CLIENT_DIR="/var/lib/ztna/clients"
WG_SUBNET="10.13.13.0/24"
WG_PORT="51820"

# Source environment variables
if [ -f "$(dirname "$0")/workstation.env" ]; then
    source "$(dirname "$0")/workstation.env"
    WG_SERVER_PUBLIC_IP="${WG_SERVER_PUBLIC_IP:-$(curl -s ifconfig.me)}"
    WG_DNS="${WG_DNS:-1.1.1.1,1.0.0.1}"
else
    echo -e "${YELLOW}Warning: workstation.env not found, using defaults${NC}"
    WG_SERVER_PUBLIC_IP=$(curl -s ifconfig.me)
    WG_DNS="1.1.1.1,1.0.0.1"
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Check if username provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Username required${NC}"
    echo "Usage: sudo $0 <username>"
    echo "Example: sudo $0 john_doe"
    exit 1
fi

USERNAME="$1"

# Validate username (alphanumeric and underscore only)
if ! [[ "$USERNAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo -e "${RED}Error: Username can only contain letters, numbers, and underscores${NC}"
    exit 1
fi

# Check if username already exists
if sqlite3 "$DB_PATH" "SELECT username FROM users WHERE username='$USERNAME';" | grep -q "$USERNAME"; then
    echo -e "${RED}Error: Username '$USERNAME' already exists${NC}"
    echo "Use: sudo ./query_users.sh to view existing users"
    exit 1
fi

echo -e "${BLUE}========================================"
echo "WireGuard Peer Provisioning"
echo -e "========================================${NC}"
echo -e "Username: ${GREEN}$USERNAME${NC}"

# Get next available IP
echo -e "${YELLOW}Allocating IP address...${NC}"

# Query database for last assigned IP
LAST_IP=$(sqlite3 "$DB_PATH" "SELECT peer_ip FROM users ORDER BY id DESC LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$LAST_IP" ]; then
    # First user, start at .2 (.1 is gateway)
    PEER_IP="10.13.13.2"
else
    # Increment last IP
    LAST_OCTET=$(echo "$LAST_IP" | cut -d'.' -f4)
    NEXT_OCTET=$((LAST_OCTET + 1))
    
    if [ $NEXT_OCTET -gt 254 ]; then
        echo -e "${RED}Error: Subnet exhausted (no more IPs available)${NC}"
        exit 1
    fi
    
    PEER_IP="10.13.13.$NEXT_OCTET"
fi

echo -e "Assigned IP: ${GREEN}$PEER_IP${NC}"

# Generate WireGuard keys
echo -e "${YELLOW}Generating WireGuard keypair...${NC}"

PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
PRESHARED_KEY=$(wg genpsk)

echo -e "Public Key: ${GREEN}${PUBLIC_KEY:0:20}...${NC}"

# Get server public key
if [ ! -f "/etc/wireguard/server_public.key" ]; then
    # Extract from wg0.conf if exists, or generate new
    if [ -f "$WG_CONFIG" ]; then
        SERVER_PRIVATE_KEY=$(grep "PrivateKey" "$WG_CONFIG" | awk '{print $3}')
        if [ -n "$SERVER_PRIVATE_KEY" ]; then
            SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)
            echo "$SERVER_PUBLIC_KEY" > /etc/wireguard/server_public.key
        fi
    fi
    
    if [ ! -f "/etc/wireguard/server_public.key" ]; then
        echo -e "${YELLOW}Generating server keypair (first time)...${NC}"
        SERVER_PRIVATE_KEY=$(wg genkey)
        SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)
        echo "$SERVER_PRIVATE_KEY" > /etc/wireguard/server_private.key
        echo "$SERVER_PUBLIC_KEY" > /etc/wireguard/server_public.key
        chmod 600 /etc/wireguard/server_private.key
    fi
fi

SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)

# Add peer to WireGuard config
echo -e "${YELLOW}Updating WireGuard configuration...${NC}"

# Create WireGuard config if doesn't exist
if [ ! -f "$WG_CONFIG" ]; then
    echo -e "${YELLOW}Creating initial WireGuard server config...${NC}"
    SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private.key)
    
    cat > "$WG_CONFIG" << EOF
[Interface]
Address = 10.13.13.1/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE_KEY
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

EOF
    chmod 600 "$WG_CONFIG"
fi

# Append peer configuration
cat >> "$WG_CONFIG" << EOF
# Client: $USERNAME
[Peer]
PublicKey = $PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = $PEER_IP/32

EOF

# Insert record into database
echo -e "${YELLOW}Adding to database...${NC}"

DEVICE_ID=$(uuidgen | cut -d'-' -f1)
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')

sqlite3 "$DB_PATH" << EOF
INSERT INTO users (username, device_id, public_key, peer_ip, created_at, last_seen)
VALUES ('$USERNAME', '$DEVICE_ID', '$PUBLIC_KEY', '$PEER_IP', '$CREATED_AT', NULL);
EOF

echo -e "${GREEN}Database record created${NC}"

# Restart WireGuard
echo -e "${YELLOW}Restarting WireGuard...${NC}"

if docker ps | grep -q wireguard; then
    docker restart wireguard > /dev/null 2>&1
    echo -e "${GREEN}WireGuard container restarted${NC}"
else
    # If not using Docker, use wg-quick
    if systemctl is-active --quiet wg-quick@wg0; then
        wg syncconf wg0 <(wg-quick strip wg0)
        echo -e "${GREEN}WireGuard config reloaded${NC}"
    else
        wg-quick up wg0
        echo -e "${GREEN}WireGuard interface started${NC}"
    fi
fi

# Generate client configuration file
echo -e "${YELLOW}Generating client configuration...${NC}"

mkdir -p "$CLIENT_DIR"

CLIENT_CONFIG="$CLIENT_DIR/${USERNAME}.conf"

cat > "$CLIENT_CONFIG" << EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $PEER_IP/32
DNS = $WG_DNS

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
Endpoint = $WG_SERVER_PUBLIC_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

chmod 600 "$CLIENT_CONFIG"

echo -e "${GREEN}Config file: $CLIENT_CONFIG${NC}"

# Generate QR code
echo ""
echo -e "${BLUE}========================================"
echo "CLIENT CONFIGURATION"
echo -e "========================================${NC}"
echo ""
cat "$CLIENT_CONFIG"
echo ""

echo -e "${BLUE}========================================"
echo "QR CODE (Scan with mobile device)"
echo -e "========================================${NC}"

if command -v qrencode &> /dev/null; then
    qrencode -t ansiutf8 < "$CLIENT_CONFIG"
    
    # Also save PNG version
    qrencode -t png -o "${CLIENT_CONFIG%.conf}.png" < "$CLIENT_CONFIG"
    echo ""
    echo -e "${GREEN}QR code also saved as: ${CLIENT_CONFIG%.conf}.png${NC}"
else
    echo -e "${YELLOW}Warning: qrencode not installed, QR code not generated${NC}"
    echo "Install with: sudo apt install qrencode"
fi

echo ""
echo -e "${GREEN}========================================"
echo "Peer provisioning completed!"
echo -e "========================================${NC}"
echo -e "Username: ${GREEN}$USERNAME${NC}"
echo -e "Assigned IP: ${GREEN}$PEER_IP${NC}"
echo -e "Device ID: ${GREEN}$DEVICE_ID${NC}"
echo -e "Config file: ${GREEN}$CLIENT_CONFIG${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Send config file to user securely"
echo "2. User imports into WireGuard client"
echo "3. Or user scans QR code with mobile app"
echo ""
echo -e "${BLUE}Verify connection with:${NC}"
echo "  sudo wg show"
echo "  sudo ./query_users.sh"
echo ""
