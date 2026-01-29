#!/bin/bash
# ============================================================
# Xray VPN Server Setup Script
# ============================================================
# This script sets up Xray-core in Docker mode with VLESS protocol
# Uses Cloudflare proxied subdomain for secure access
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
print_info "Starting Xray-core Setup in Docker Mode"
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
# Create Xray configuration directory
# ============================================================
XRAY_CONFIG_DIR="/etc/xray"
mkdir -p "$XRAY_CONFIG_DIR"
print_info "Created Xray configuration directory: $XRAY_CONFIG_DIR"

# ============================================================
# Generate Xray Configuration File
# ============================================================
print_info "Generating Xray configuration..."

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
            "email": "user@xray"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 80
          }
        ]
      },
      "streamSettings": {
        "network": "$XRAY_NETWORK",
        "security": "$XRAY_SECURITY",
        "tlsSettings": {
          "serverName": "$XRAY_PANEL_DOMAIN",
          "alpn": ["h2", "http/1.1"],
          "certificates": [
            {
              "certificateFile": "/etc/xray/cert.pem",
              "keyFile": "/etc/xray/key.pem"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
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

print_success "Xray configuration file created"

# ============================================================
# Setup SSL Certificates (Let's Encrypt or Self-Signed)
# ============================================================
print_info "Setting up SSL certificates..."

if [ "$XRAY_USE_ACME" = "true" ]; then
    # Use acme.sh for Let's Encrypt certificates
    print_info "Installing acme.sh for Let's Encrypt certificates..."
    
    if [ ! -d "/root/.acme.sh" ]; then
        curl https://get.acme.sh | sh
        source ~/.bashrc
    fi
    
    # Issue certificate
    /root/.acme.sh/acme.sh --issue -d "$XRAY_PANEL_DOMAIN" --standalone --force
    
    # Install certificate
    /root/.acme.sh/acme.sh --installcert -d "$XRAY_PANEL_DOMAIN" \
        --key-file "$XRAY_CONFIG_DIR/key.pem" \
        --fullchain-file "$XRAY_CONFIG_DIR/cert.pem"
    
    print_success "Let's Encrypt certificates installed"
else
    # Use Cloudflare Origin certificates or self-signed
    print_warning "Using Cloudflare Origin certificates or self-signed certificates"
    print_warning "Please place your certificates in:"
    print_warning "  - Certificate: $XRAY_CONFIG_DIR/cert.pem"
    print_warning "  - Private Key: $XRAY_CONFIG_DIR/key.pem"
    
    # Create self-signed certificate if files don't exist
    if [ ! -f "$XRAY_CONFIG_DIR/cert.pem" ] || [ ! -f "$XRAY_CONFIG_DIR/key.pem" ]; then
        print_info "Generating self-signed certificate for testing..."
        openssl req -x509 -newkey rsa:4096 -keyout "$XRAY_CONFIG_DIR/key.pem" \
            -out "$XRAY_CONFIG_DIR/cert.pem" -days 365 -nodes \
            -subj "/CN=$XRAY_PANEL_DOMAIN"
        print_success "Self-signed certificate generated"
    fi
fi

# Set proper permissions
chmod 644 "$XRAY_CONFIG_DIR/cert.pem"
chmod 600 "$XRAY_CONFIG_DIR/key.pem"

# ============================================================
# Pull and Run Xray Docker Container
# ============================================================
print_info "Pulling Xray-core Docker image..."
docker pull ghcr.io/xtls/xray-core:latest

# Stop and remove existing container if exists
if docker ps -a | grep -q xray-server; then
    print_info "Stopping existing Xray container..."
    docker stop xray-server
    docker rm xray-server
fi

print_info "Starting Xray-core container..."
docker run -d \
    --name xray-server \
    --restart unless-stopped \
    -v "$XRAY_CONFIG_DIR":/etc/xray \
    -p "$XRAY_PORT:$XRAY_PORT" \
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
    ufw allow "$XRAY_PORT/tcp" comment "Xray VLESS"
    print_success "UFW firewall rule added for port $XRAY_PORT"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port="$XRAY_PORT/tcp"
    firewall-cmd --reload
    print_success "firewalld rule added for port $XRAY_PORT"
fi

# ============================================================
# Display Connection Information
# ============================================================
print_success "============================================================"
print_success "Xray-core Setup Complete!"
print_success "============================================================"
echo ""
print_info "Connection Details:"
echo -e "${BLUE}Domain:${NC} $XRAY_PANEL_DOMAIN"
echo -e "${BLUE}Port:${NC} $XRAY_PORT"
echo -e "${BLUE}UUID:${NC} $XRAY_UUID"
echo -e "${BLUE}Network:${NC} $XRAY_NETWORK"
echo -e "${BLUE}Security:${NC} $XRAY_SECURITY"
echo -e "${BLUE}Flow:${NC} $XRAY_FLOW"
echo ""
print_info "VLESS Connection String:"
echo -e "${GREEN}vless://$XRAY_UUID@$XRAY_PANEL_DOMAIN:$XRAY_PORT?security=$XRAY_SECURITY&sni=$XRAY_PANEL_DOMAIN&type=$XRAY_NETWORK&flow=$XRAY_FLOW#Xray-VPS${NC}"
echo ""
print_info "Container Status:"
docker ps --filter name=xray-server --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
print_warning "Important Notes:"
print_warning "1. Make sure to configure Cloudflare tunnel for $XRAY_PANEL_DOMAIN"
print_warning "2. Save your UUID ($XRAY_UUID) securely"
print_warning "3. Use v2rayN, v2rayNG, or compatible clients to connect"
print_warning "4. Check container logs: docker logs xray-server"
echo ""
print_success "Setup completed successfully!"
