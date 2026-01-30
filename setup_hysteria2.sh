#!/bin/bash
# ============================================================
# Hysteria2 VPN Server Setup Script
# ============================================================
# This script sets up Hysteria2 proxy server optimized for
# high-latency, unstable networks (perfect for mobile data in Iran)
# Uses UDP protocol (QUIC) for better performance than TCP-based proxies
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
print_info "Starting Hysteria2 Setup"
print_info "============================================================"

# ============================================================
# Install Hysteria2 using official script
# ============================================================
if ! command -v hysteria &> /dev/null; then
    print_info "Installing Hysteria2..."
    bash <(curl -fsSL https://get.hy2.sh/)
    print_success "Hysteria2 installed successfully"
else
    print_success "Hysteria2 is already installed"
fi

# ============================================================
# Generate password if not provided
# ============================================================
if [ -z "$HYSTERIA2_PASSWORD" ] || [ "$HYSTERIA2_PASSWORD" = "<auto_generated_password>" ]; then
    HYSTERIA2_PASSWORD=$(openssl rand -base64 32)
    print_warning "Generated new password: $HYSTERIA2_PASSWORD"
    
    # Save to workstation.env
    sed -i "s|HYSTERIA2_PASSWORD=\"<auto_generated_password>\"|HYSTERIA2_PASSWORD=\"$HYSTERIA2_PASSWORD\"|g" "$SCRIPT_DIR/workstation.env"
    print_success "Password saved to workstation.env"
fi

# ============================================================
# Create Hysteria2 configuration directory
# ============================================================
HYSTERIA_CONFIG_DIR="/etc/hysteria"
mkdir -p "$HYSTERIA_CONFIG_DIR"
print_info "Created Hysteria2 configuration directory: $HYSTERIA_CONFIG_DIR"

# ============================================================
# Generate Self-Signed Certificate
# ============================================================
print_info "Generating self-signed TLS certificate..."
openssl req -x509 -nodes -newkey rsa:4096 \
    -keyout "$HYSTERIA2_KEY_PATH" \
    -out "$HYSTERIA2_CERT_PATH" \
    -subj "/CN=$HYSTERIA2_SNI" \
    -days 3650 2>/dev/null

print_success "TLS certificate generated successfully"

# ============================================================
# Generate Hysteria2 Configuration File
# ============================================================
print_info "Generating Hysteria2 configuration..."

cat > "$HYSTERIA_CONFIG_DIR/config.yaml" <<EOF
listen: :$HYSTERIA2_PORT

tls:
  cert: $HYSTERIA2_CERT_PATH
  key: $HYSTERIA2_KEY_PATH

auth:
  type: password
  password: $HYSTERIA2_PASSWORD

masquerade:
  type: proxy
  proxy:
    url: $HYSTERIA2_MASQUERADE_URL
    rewriteHost: true

# Optimization for high-speed performance
quic:
  initStreamReceiveWindow: $HYSTERIA2_INIT_STREAM_RECEIVE_WINDOW
  maxStreamReceiveWindow: $HYSTERIA2_MAX_STREAM_RECEIVE_WINDOW
  initConnReceiveWindow: $HYSTERIA2_INIT_CONN_RECEIVE_WINDOW
  maxConnReceiveWindow: $HYSTERIA2_MAX_CONN_RECEIVE_WINDOW
EOF

# Add bandwidth limits if specified
if [ "$HYSTERIA2_BANDWIDTH_UP" != "0" ] || [ "$HYSTERIA2_BANDWIDTH_DOWN" != "0" ]; then
    cat >> "$HYSTERIA_CONFIG_DIR/config.yaml" <<EOF

# Bandwidth limits
bandwidth:
  up: ${HYSTERIA2_BANDWIDTH_UP} mbps
  down: ${HYSTERIA2_BANDWIDTH_DOWN} mbps
EOF
fi

print_success "Hysteria2 configuration file created"

# ============================================================
# Set proper permissions
# ============================================================
print_info "Setting proper permissions..."
chown -R hysteria:hysteria "$HYSTERIA_CONFIG_DIR"
chmod 600 "$HYSTERIA2_KEY_PATH"
chmod 644 "$HYSTERIA2_CERT_PATH"
print_success "Permissions set successfully"

# ============================================================
# Configure Firewall
# ============================================================
print_info "Configuring firewall for Hysteria2..."
if command -v ufw &> /dev/null; then
    ufw allow "$HYSTERIA2_PORT/udp" comment "Hysteria2 UDP"
    ufw allow "$HYSTERIA2_PORT/tcp" comment "Hysteria2 TCP"
    print_success "UFW firewall rules added for port $HYSTERIA2_PORT"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port="$HYSTERIA2_PORT/udp"
    firewall-cmd --permanent --add-port="$HYSTERIA2_PORT/tcp"
    firewall-cmd --reload
    print_success "firewalld rules added for port $HYSTERIA2_PORT"
fi

# ============================================================
# Enable and Start Hysteria2 Service
# ============================================================
print_info "Enabling and starting Hysteria2 service..."
systemctl enable hysteria-server.service
systemctl restart hysteria-server.service

# Wait for service to start
sleep 3

# Check if service is running
if systemctl is-active --quiet hysteria-server.service; then
    print_success "Hysteria2 service started successfully"
else
    print_error "Failed to start Hysteria2 service"
    systemctl status hysteria-server.service
    exit 1
fi

# ============================================================
# Get Server IP Address
# ============================================================
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="YOUR_SERVER_IP"
fi

# ============================================================
# Generate Hysteria2 URI
# ============================================================
# Format: hysteria2://[password]@[server_ip]:[port]?sni=[sni]&insecure=[1|0]#[name]
HYSTERIA2_URI="hysteria2://${HYSTERIA2_PASSWORD}@${SERVER_IP}:${HYSTERIA2_PORT}?sni=${HYSTERIA2_SNI}&insecure=1#Hysteria2-Server"

# ============================================================
# Display Connection Information
# ============================================================
print_success "============================================================"
print_success "Hysteria2 Setup Complete!"
print_success "============================================================"
echo ""
print_info "Connection Details:"
echo -e "${BLUE}Server IP:${NC} $SERVER_IP"
echo -e "${BLUE}Port:${NC} $HYSTERIA2_PORT (UDP)"
echo -e "${BLUE}Protocol:${NC} Hysteria2 (QUIC)"
echo -e "${BLUE}Password:${NC} $HYSTERIA2_PASSWORD"
echo -e "${BLUE}SNI:${NC} $HYSTERIA2_SNI"
echo -e "${BLUE}Insecure:${NC} True (self-signed certificate)"
echo ""
print_info "Hysteria2 Connection URI:"
echo -e "${GREEN}$HYSTERIA2_URI${NC}"
echo ""
print_info "Service Status:"
systemctl status hysteria-server.service --no-pager -l
echo ""
print_warning "Important Notes:"
print_warning "1. Hysteria2 uses UDP (QUIC) for better performance on mobile networks"
print_warning "2. Self-signed certificate is used - clients must enable 'insecure' mode"
print_warning "3. Password saved in workstation.env - keep it secure"
print_warning "4. Use v2rayNG (v1.8.5+) or other Hysteria2-compatible clients"
echo ""
print_warning "5. Client Configuration (v2rayNG):"
echo -e "   ${BLUE}→${NC} Type: Hysteria2"
echo -e "   ${BLUE}→${NC} Remarks: Scotland-Hy2"
echo -e "   ${BLUE}→${NC} Address: $SERVER_IP"
echo -e "   ${BLUE}→${NC} Port: $HYSTERIA2_PORT"
echo -e "   ${BLUE}→${NC} Auth (Password): $HYSTERIA2_PASSWORD"
echo -e "   ${BLUE}→${NC} SNI: $HYSTERIA2_SNI"
echo -e "   ${BLUE}→${NC} Insecure: True (check this box)"
echo -e "   ${BLUE}→${NC} Downlink/Uplink: 100 Mbps (optional)"
echo ""
print_warning "6. Manual Configuration Alternative:"
echo -e "   ${BLUE}→${NC} Copy the Hysteria2 URI above and import it in v2rayNG"
echo -e "   ${BLUE}→${NC} Or scan this text as a shareable link"
echo ""
print_warning "7. Service commands:"
echo -e "   ${BLUE}→${NC} Start: systemctl start hysteria-server.service"
echo -e "   ${BLUE}→${NC} Stop: systemctl stop hysteria-server.service"
echo -e "   ${BLUE}→${NC} Restart: systemctl restart hysteria-server.service"
echo -e "   ${BLUE}→${NC} Status: systemctl status hysteria-server.service"
echo -e "   ${BLUE}→${NC} Logs: journalctl -u hysteria-server.service -f"
echo ""
print_warning "8. Why Hysteria2 for mobile networks?"
echo -e "   ${BLUE}→${NC} UDP-based protocol bypasses TCP throttling"
echo -e "   ${BLUE}→${NC} Better performance on high-latency networks"
echo -e "   ${BLUE}→${NC} Optimized for congested mobile data connections"
echo -e "   ${BLUE}→${NC} More resistant to DPI than TCP-based protocols"
echo ""
print_success "Hysteria2 is now ready to use!"
print_info "Save the connection URI or configure your client manually"
echo ""
