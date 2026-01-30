#!/bin/bash
# ============================================================
# Xray VPN Server Setup Script (VLESS + Reality)
# ============================================================
# This script sets up Xray-core with direct installation (not Docker)
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
# Install Xray-core using official script
# ============================================================
if ! command -v xray &> /dev/null; then
    print_info "Installing Xray-core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    print_success "Xray-core installed successfully"
else
    print_success "Xray-core is already installed"
fi

# ============================================================
# Generate UUID for VLESS if not provided
# ============================================================
if [ -z "$XRAY_UUID" ] || [ "$XRAY_UUID" = "<auto_generated_uuid>" ]; then
    XRAY_UUID=$(cat /proc/sys/kernel/random/uuid)
    print_warning "Generated new UUID: $XRAY_UUID"
    
    # Save to workstation.env
    sed -i "s|XRAY_UUID=\"<auto_generated_uuid>\"|XRAY_UUID=\"$XRAY_UUID\"|g" "$SCRIPT_DIR/workstation.env"
    print_success "UUID saved to workstation.env"
fi

# ============================================================
# Generate Reality Keys if not provided
# ============================================================
print_info "Generating Reality protocol keys..."

# Generate both private and public keys together
if [ -z "$XRAY_REALITY_PRIVATE_KEY" ] || [ "$XRAY_REALITY_PRIVATE_KEY" = "<auto_generated_private_key>" ] || [ -z "$XRAY_REALITY_PUBLIC_KEY" ] || [ "$XRAY_REALITY_PUBLIC_KEY" = "<auto_generated_public_key>" ]; then
    KEY_OUTPUT=$(xray x25519 2>&1)
    XRAY_REALITY_PRIVATE_KEY=$(echo "$KEY_OUTPUT" | awk '/PrivateKey:/{print $2}')
    XRAY_REALITY_PUBLIC_KEY=$(echo "$KEY_OUTPUT" | awk '/Password:/{print $2}')
    
    if [ -z "$XRAY_REALITY_PRIVATE_KEY" ] || [ -z "$XRAY_REALITY_PUBLIC_KEY" ]; then
        print_error "Failed to generate keys. xray x25519 output:"
        echo "$KEY_OUTPUT"
        exit 1
    fi
    
    print_warning "Generated new keys:"
    print_warning "  Private key: $XRAY_REALITY_PRIVATE_KEY"
    print_warning "  Public key: $XRAY_REALITY_PUBLIC_KEY"
    
    # Save to workstation.env
    print_info "Saving keys to workstation.env..."
    sed -i "s|XRAY_REALITY_PRIVATE_KEY=\"<auto_generated_private_key>\"|XRAY_REALITY_PRIVATE_KEY=\"$XRAY_REALITY_PRIVATE_KEY\"|g" "$SCRIPT_DIR/workstation.env"
    sed -i "s|XRAY_REALITY_PUBLIC_KEY=\"<auto_generated_public_key>\"|XRAY_REALITY_PUBLIC_KEY=\"$XRAY_REALITY_PUBLIC_KEY\"|g" "$SCRIPT_DIR/workstation.env"
    print_success "Keys saved to workstation.env"
fi

# ============================================================
# Generate Short IDs if not provided
# ============================================================
if [ -z "$XRAY_REALITY_SHORT_IDS" ]; then
    XRAY_REALITY_SHORT_IDS=$(openssl rand -hex 6)
    print_warning "Generated new short ID: $XRAY_REALITY_SHORT_IDS"
    
    # Save to workstation.env
    print_info "Saving short ID to workstation.env..."
    sed -i "s|XRAY_REALITY_SHORT_IDS=\"\"|XRAY_REALITY_SHORT_IDS=\"$XRAY_REALITY_SHORT_IDS\"|g" "$SCRIPT_DIR/workstation.env"
    print_success "Short ID saved to workstation.env"
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
XRAY_CONFIG_DIR="/usr/local/etc/xray"
mkdir -p "$XRAY_CONFIG_DIR"
print_info "Created Xray configuration directory: $XRAY_CONFIG_DIR"

# ============================================================
# Generate Xray Configuration File (VLESS + Reality)
# ============================================================
print_info "Generating Xray configuration with Reality protocol..."

# Use XRAY_LISTENING_PORT if defined, otherwise fall back to XRAY_PORT
LISTEN_PORT="${XRAY_LISTENING_PORT:-$XRAY_PORT}"

cat > "$XRAY_CONFIG_DIR/config.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $LISTEN_PORT,
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
# Enable and Start Xray Service
# ============================================================
print_info "Enabling and starting Xray service..."
setcap cap_net_bind_service=+ep /usr/local/bin/xray
systemctl enable xray
systemctl restart xray

# Wait for service to start
sleep 3

# Check if service is running
if systemctl is-active --quiet xray; then
    print_success "Xray service started successfully"
else
    print_error "Failed to start Xray service"
    systemctl status xray
    exit 1
fi

# ============================================================
# Configure Firewall
# ============================================================
print_info "Configuring firewall for Xray..."
if command -v ufw &> /dev/null; then
    ufw allow "$LISTEN_PORT/tcp" comment "Xray VLESS Reality"
    print_success "UFW firewall rule added for port $LISTEN_PORT"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port="$LISTEN_PORT/tcp"
    firewall-cmd --reload
    print_success "firewalld rule added for port $LISTEN_PORT"
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
echo -e "${BLUE}Port:${NC} $LISTEN_PORT (Users connect here)"
echo -e "${BLUE}Destination:${NC} $XRAY_REALITY_DEST (Reality mimics HTTPS to this site)"
echo -e "${BLUE}Protocol:${NC} VLESS"
echo -e "${BLUE}Security:${NC} Reality"
echo -e "${BLUE}Flow:${NC} $XRAY_FLOW"
echo ""
echo -e "${BLUE}UUID:${NC} $XRAY_UUID"
echo -e "${BLUE}Public Key:${NC} $XRAY_REALITY_PUBLIC_KEY"
echo -e "${BLUE}Short IDs:${NC} $XRAY_REALITY_SHORT_IDS"
echo -e "${BLUE}SNI:${NC} ${XRAY_REALITY_SERVER_NAMES%%,*}"
echo -e "${BLUE}Fingerprint:${NC} chrome"
echo ""
print_info "VLESS Connection String:"
echo -e "${GREEN}vless://$XRAY_UUID@$SERVER_IP:$LISTEN_PORT?security=reality&sni=${XRAY_REALITY_SERVER_NAMES%%,*}&fp=chrome&pbk=$XRAY_REALITY_PUBLIC_KEY&sid=$XRAY_REALITY_SHORT_IDS&type=tcp&flow=$XRAY_FLOW#Xray-Reality${NC}"
echo ""
print_info "Service Status:"
systemctl status xray --no-pager -l
echo ""
print_warning "Important Notes:"
print_warning "1. Reality protocol mimics connection to $XRAY_REALITY_DEST"
print_warning "2. No SSL certificates needed - Reality handles encryption"
print_warning "3. Save your UUID and keys securely - stored in workstation.env"
print_warning "4. Use v2rayN, v2rayNG, or compatible clients to connect"
print_warning "5. Client Configuration:"
echo -e "   ${BLUE}→${NC} Address: $SERVER_IP"
echo -e "   ${BLUE}→${NC} Port: $LISTEN_PORT (Users connect to this port)"
echo -e "   ${BLUE}→${NC} UUID: $XRAY_UUID"
echo -e "   ${BLUE}→${NC} Flow: $XRAY_FLOW"
echo -e "   ${BLUE}→${NC} Security: reality"
echo -e "   ${BLUE}→${NC} SNI: ${XRAY_REALITY_SERVER_NAMES%%,*}"
echo -e "   ${BLUE}→${NC} Fingerprint: chrome"
echo -e "   ${BLUE}→${NC} Public Key: $XRAY_REALITY_PUBLIC_KEY"
echo -e "   ${BLUE}→${NC} Short ID: $XRAY_REALITY_SHORT_IDS"
echo ""
print_warning "6. Check service logs: journalctl -u xray -f"
print_warning "7. Service commands:"
echo -e "   ${BLUE}→${NC} Start: systemctl start xray"
echo -e "   ${BLUE}→${NC} Stop: systemctl stop xray"
echo -e "   ${BLUE}→${NC} Restart: systemctl restart xray"
echo -e "   ${BLUE}→${NC} Status: systemctl status xray"
echo ""
print_success "Setup completed successfully!"
