#!/bin/bash
# ============================================================
# Xray VPN Server Setup Script (VLESS + Reality)
# ============================================================
# This script sets up Xray-core in Docker mode with VLESS + Reality protocol
# Reality protocol mimics legitimate HTTPS traffic to bypass DPI filtering
# ============================================================

set -e  # Exit on error

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workstation.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (use sudo)"
    exit 1
fi

print_info "============================================================"
print_info "Starting Xray-core Setup with VLESS + Reality Protocol"
print_info "============================================================"

# ============================================================
# Install Docker if not present
# ============================================================
if ! command -v docker &> /dev/null; then
    print_info "Docker not found. Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    systemctl enable docker
    systemctl start docker
    print_success "Docker installed successfully"
else
    print_success "Docker is already installed"
fi

# ============================================================
# Generate UUID for VLESS if not provided
# ============================================================
if [ -z "$XRAY_UUID" ] || [ "$XRAY_UUID" = "<auto_generated_uuid>" ]; then
    XRAY_UUID=$(cat /proc/sys/kernel/random/uuid)
    print_warning "Generated new UUID: $XRAY_UUID"
    print_warning "Please update XRAY_UUID in workstation.env with this value"
fi

# ============================================================
# Generate Reality Keys if not provided
# ============================================================
print_info "Generating Reality protocol keys..."

# Pull Xray image first to use for key generation
docker pull ghcr.io/xtls/xray-core:latest

# Generate private key
if [ -z "$XRAY_REALITY_PRIVATE_KEY" ] || [ "$XRAY_REALITY_PRIVATE_KEY" = "<auto_generated_private_key>" ]; then
    XRAY_REALITY_PRIVATE_KEY=$(docker run --rm ghcr.io/xtls/xray-core:latest xray x25519)
    print_warning "Generated new private key: $XRAY_REALITY_PRIVATE_KEY"
    print_warning "Please update XRAY_REALITY_PRIVATE_KEY in workstation.env with this value"
fi

# Generate public key from private key
if [ -z "$XRAY_REALITY_PUBLIC_KEY" ] || [ "$XRAY_REALITY_PUBLIC_KEY" = "<auto_generated_public_key>" ]; then
    XRAY_REALITY_PUBLIC_KEY=$(docker run --rm ghcr.io/xtls/xray-core:latest xray x25519 -i "$XRAY_REALITY_PRIVATE_KEY" | grep "Public key:" | awk '{print $3}')
    print_warning "Generated new public key: $XRAY_REALITY_PUBLIC_KEY"
    print_warning "Please update XRAY_REALITY_PUBLIC_KEY in workstation.env with this value"
fi

# ============================================================
# Generate Short IDs if not provided
# ============================================================
if [ -z "$XRAY_REALITY_SHORT_IDS" ]; then
    # Generate a random 12-character hex short ID
    XRAY_REALITY_SHORT_IDS=$(openssl rand -hex 6)
    print_warning "Generated new short ID: $XRAY_REALITY_SHORT_IDS"
    print_warning "Please update XRAY_REALITY_SHORT_IDS in workstation.env with this value"
fi

# Convert comma-separated short IDs to JSON array format
IFS=',' read -ra SHORT_ID_ARRAY <<< "$XRAY_REALITY_SHORT_IDS"
SHORT_IDS_JSON=""
for sid in "${SHORT_ID_ARRAY[@]}"; do
    sid=$(echo "$sid" | xargs)  # Trim whitespace
    if [ -n "$sid" ]; then
        if [ -z "$SHORT_IDS_JSON" ]; then
            SHORT_IDS_JSON="\"$sid\""
        else
            SHORT_IDS_JSON="$SHORT_IDS_JSON,\"$sid\""
        fi
    fi
done

# If no short IDs were provided or generated, use empty string
if [ -z "$SHORT_IDS_JSON" ]; then
    SHORT_IDS_JSON='""'
fi

# Convert comma-separated server names to JSON array format
IFS=',' read -ra SERVER_NAME_ARRAY <<< "$XRAY_REALITY_SERVER_NAMES"
SERVER_NAMES_JSON=""
for sn in "${SERVER_NAME_ARRAY[@]}"; do
    sn=$(echo "$sn" | xargs)  # Trim whitespace
    if [ -n "$sn" ]; then
        if [ -z "$SERVER_NAMES_JSON" ]; then
            SERVER_NAMES_JSON="\"$sn\""
        else
            SERVER_NAMES_JSON="$SERVER_NAMES_JSON,\"$sn\""
        fi
    fi
done

# ============================================================
# Create Xray configuration directory
# ============================================================
XRAY_CONFIG_DIR="/etc/xray"
mkdir -p "$XRAY_CONFIG_DIR"
print_info "Created Xray configuration directory: $XRAY_CONFIG_DIR"

# ============================================================
# Generate Xray Configuration File (VLESS + Reality)
# ============================================================
print_info "Generating Xray configuration with Reality protocol..."

cat > "$XRAY_CONFIG_DIR/config.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$XRAY_UUID",
            "flow": "$XRAY_FLOW",
            "level": 0,
            "email": "user@reality"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "$XRAY_NETWORK",
        "security": "$XRAY_SECURITY",
        "realitySettings": {
          "show": false,
          "dest": "$XRAY_REALITY_DEST",
          "xver": 0,
          "serverNames": [
            $SERVER_NAMES_JSON
          ],
          "privateKey": "$XRAY_REALITY_PRIVATE_KEY",
          "shortIds": [
            $SHORT_IDS_JSON
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

print_success "Xray configuration file created with Reality protocol"

# ============================================================
# Stop and Remove Existing Container if Exists
# ============================================================
if docker ps -a | grep -q xray-server; then
    print_info "Stopping existing Xray container..."
    docker stop xray-server 2>/dev/null || true
    docker rm xray-server 2>/dev/null || true
fi

# ============================================================
# Run Xray Docker Container
# ============================================================
print_info "Starting Xray-core container with Reality protocol..."
docker run -d \
    --name xray-server \
    --restart unless-stopped \
    -v "$XRAY_CONFIG_DIR":/etc/xray \
    -p "$XRAY_PORT:$XRAY_PORT" \
    --network host \
    ghcr.io/xtls/xray-core:latest \
    run -c /etc/xray/config.json

# Wait for container to start
sleep 3

# Check if container is running
if docker ps | grep -q xray-server; then
    print_success "Xray-core container started successfully"
else
    print_error "Failed to start Xray-core container"
    docker logs xray-server
    exit 1
fi

# ============================================================
# Configure Firewall
# ============================================================
print_info "Configuring firewall for Xray..."
if command -v ufw &> /dev/null; then
    ufw allow "$XRAY_PORT/tcp" comment "Xray VLESS Reality"
    print_success "UFW firewall rule added for port $XRAY_PORT"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port="$XRAY_PORT/tcp"
    firewall-cmd --reload
    print_success "firewalld rule added for port $XRAY_PORT"
fi

# ============================================================
# Get Server IP Address
# ============================================================
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="YOUR_SERVER_IP"
fi

# ============================================================
# Display Connection Information
# ============================================================
print_success "============================================================"
print_success "Xray-core Setup Complete with VLESS + Reality!"
print_success "============================================================"
echo ""
print_info "Connection Details:"
echo -e "${BLUE}Server IP:${NC} $SERVER_IP"
echo -e "${BLUE}Port:${NC} $XRAY_PORT"
echo -e "${BLUE}Protocol:${NC} VLESS"
echo -e "${BLUE}Security:${NC} Reality"
echo -e "${BLUE}Flow:${NC} $XRAY_FLOW"
echo ""
echo -e "${BLUE}UUID:${NC} $XRAY_UUID"
echo -e "${BLUE}Public Key:${NC} $XRAY_REALITY_PUBLIC_KEY"
echo -e "${BLUE}Short ID(s):${NC} $XRAY_REALITY_SHORT_IDS"
echo -e "${BLUE}SNI:${NC} ${XRAY_REALITY_SERVER_NAMES%%,*}"
echo -e "${BLUE}Fingerprint:${NC} chrome"
echo ""
print_info "VLESS Connection String:"
echo -e "${GREEN}vless://$XRAY_UUID@$SERVER_IP:$XRAY_PORT?security=reality&sni=${XRAY_REALITY_SERVER_NAMES%%,*}&fp=chrome&pbk=$XRAY_REALITY_PUBLIC_KEY&sid=$XRAY_REALITY_SHORT_IDS&type=tcp&flow=$XRAY_FLOW#Xray-Reality${NC}"
echo ""
print_info "Container Status:"
docker ps --filter name=xray-server --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
print_warning "Important Notes:"
print_warning "1. Reality protocol mimics connection to $XRAY_REALITY_DEST"
print_warning "2. No SSL certificates needed - Reality handles encryption"
print_warning "3. Save your UUID and keys securely (they're in workstation.env)"
print_warning "4. Use v2rayN, v2rayNG, or compatible clients to connect"
print_warning "5. Client Configuration:"
echo -e "   ${BLUE}→${NC} Address: $SERVER_IP"
echo -e "   ${BLUE}→${NC} Port: $XRAY_PORT"
echo -e "   ${BLUE}→${NC} UUID: $XRAY_UUID"
echo -e "   ${BLUE}→${NC} Flow: $XRAY_FLOW"
echo -e "   ${BLUE}→${NC} Security: reality"
echo -e "   ${BLUE}→${NC} SNI: ${XRAY_REALITY_SERVER_NAMES%%,*}"
echo -e "   ${BLUE}→${NC} Fingerprint: chrome"
echo -e "   ${BLUE}→${NC} Public Key: $XRAY_REALITY_PUBLIC_KEY"
echo -e "   ${BLUE}→${NC} Short ID: $XRAY_REALITY_SHORT_IDS"
echo ""
print_warning "6. Manage users with: sudo ./manage_xray.sh"
print_warning "7. Check container logs: docker logs xray-server"
echo ""
print_success "Setup completed successfully!"
