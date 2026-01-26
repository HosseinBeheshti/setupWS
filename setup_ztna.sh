#!/bin/bash

# ============================================================
# Cloudflare Zero Trust VPN - Automated Setup (cloudflared + Egress)
# ============================================================
# This script performs complete VPS setup for cloudflared egress routing:
# - Installs cloudflared (Cloudflare Tunnel)
# - Configures tunnel with token from workstation.env
# - Enables WARP routing for egress
# - Configures NAT/masquerading for internet egress
# - Enables IP forwarding
# - Configures firewall
# - Starts cloudflared as system service
#
# Prerequisites:
# 1. Complete Part 1 in README.md (Cloudflare dashboard setup)
# 2. Add CLOUDFLARE_TUNNEL_TOKEN to workstation.env
#
# Usage: sudo ./setup_ztna.sh
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
if [[ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]]; then
    print_error "CLOUDFLARE_TUNNEL_TOKEN is not set in workstation.env"
    print_error "Please complete Part 1 in README.md and add the token"
    exit 1
fi

if [[ -z "$TUNNEL_NAME" ]]; then
    print_error "TUNNEL_NAME is not set in workstation.env"
    print_error "Please set the tunnel name (e.g., vps-egress)"
    exit 1
fi

# Detect VPS IP if not set
if [[ -z "$VPS_PUBLIC_IP" ]]; then
    VPS_PUBLIC_IP=$(hostname -I | awk '{print $1}')
    print_message "Auto-detected VPS IP: $VPS_PUBLIC_IP"
fi

print_header "Cloudflare Zero Trust - Automated Setup (cloudflared + Egress)"
echo -e "${CYAN}VPS IP:${NC} $VPS_PUBLIC_IP"
echo -e "${CYAN}Tunnel Name:${NC} $TUNNEL_NAME"
echo -e "${CYAN}Tunnel Token:${NC} ${CLOUDFLARE_TUNNEL_TOKEN:0:20}...${CLOUDFLARE_TUNNEL_TOKEN: -10}"
echo ""

# Step 1: Update System
print_header "Step 1/3: Updating System"
print_message "Updating package lists..."
apt-get update -qq
print_message "Upgrading packages (this may take several minutes)..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
print_message "✓ System updated"

# Step 2: Configure Firewall
print_header "Step 2/3: Configuring Firewall"

print_message "Configuring UFW firewall..."
ufw --force enable > /dev/null

# Allow SSH
ufw allow 22/tcp comment 'SSH' > /dev/null
print_message "  ✓ Allowed SSH (port 22)"

print_message "✓ Firewall configured"

# Step 2.5: Detect Network Interface
print_header "Step 2.5/4: Detecting Network Interface"
DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
if [[ -z "$DEFAULT_INTERFACE" ]]; then
    print_error "Could not detect default network interface"
    print_error "Please manually configure NAT rules"
    exit 1
fi
print_message "Detected default interface: $DEFAULT_INTERFACE"

# Step 3: Install and Configure cloudflared
print_header "Step 3/4: Installing cloudflared (Cloudflare Tunnel)"

# 1. Download and install cloudflared
print_message "Downloading cloudflared..."
cd /tmp
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb

if [[ ! -f cloudflared-linux-amd64.deb ]]; then
    print_error "Failed to download cloudflared"
    exit 1
fi

print_message "Installing cloudflared..."
dpkg -i cloudflared-linux-amd64.deb
rm cloudflared-linux-amd64.deb

# Verify installation
CLOUDFLARED_VERSION=$(cloudflared --version 2>&1 | head -1)
print_message "✓ cloudflared installed: $CLOUDFLARED_VERSION"

# 2. Create cloudflared configuration directory
print_message "Creating cloudflared configuration..."
mkdir -p /etc/cloudflared

# 3. Create configuration file with WARP routing enabled
print_message "Configuring tunnel for egress routing..."
cat > /etc/cloudflared/config.yml <<EOF
tunnel: $TUNNEL_NAME
credentials-file: /etc/cloudflared/credentials.json

# Enable WARP routing for egress
warp-routing:
  enabled: true

# Default ingress rule (required)
ingress:
  - service: http_status:404
EOF

# 4. Create credentials file from token
print_message "Setting up tunnel credentials..."
echo "$CLOUDFLARE_TUNNEL_TOKEN" | base64 -d > /etc/cloudflared/credentials.json 2>/dev/null

# If token is not base64 encoded, try using it directly
if [[ ! -s /etc/cloudflared/credentials.json ]] || ! grep -q "AccountTag" /etc/cloudflared/credentials.json 2>/dev/null; then
    # Token might be the full service install command or just the token
    # Extract token if it's in the service install format
    if [[ "$CLOUDFLARE_TUNNEL_TOKEN" =~ eyJ ]]; then
        TOKEN_PART=$(echo "$CLOUDFLARE_TUNNEL_TOKEN" | grep -oP 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' | head -1)
        if [[ -n "$TOKEN_PART" ]]; then
            echo "$TOKEN_PART" | base64 -d > /etc/cloudflared/credentials.json 2>/dev/null
        fi
    fi
fi

# Validate credentials file
if [[ ! -s /etc/cloudflared/credentials.json ]]; then
    print_error "Failed to create credentials file"
    print_error "Please check your CLOUDFLARE_TUNNEL_TOKEN in workstation.env"
    exit 1
fi

print_message "✓ Tunnel configured with WARP routing enabled"

# 2. Enable IP forwarding on the host
print_message "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

# Make persistent
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
fi
if ! grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
    echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
fi

print_message "✓ IP forwarding enabled"

# Step 4: Configure NAT for True VPN Functionality
print_header "Step 4/5: Configuring NAT (Network Address Translation)"

print_warning "⚠️  Configuring NAT to route traffic through VPS (true VPN mode)"
print_message "This allows all client traffic to exit via your VPS IP"
echo ""

# Install iptables-persistent for saving rules
print_message "Installing iptables-persistent..."
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent > /dev/null 2>&1

# Configure NAT/masquerading
print_message "Configuring NAT on interface: $DEFAULT_INTERFACE"
iptables -t nat -A POSTROUTING -o "$DEFAULT_INTERFACE" -j MASQUERADE

# Allow forwarding from WARP interface to internet
print_message "Configuring forwarding rules..."
iptables -A FORWARD -i CloudflareWARP -o "$DEFAULT_INTERFACE" -j ACCEPT
iptables -A FORWARD -i "$DEFAULT_INTERFACE" -o CloudflareWARP -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save rules
print_message "Saving iptables rules..."
netfilter-persistent save > /dev/null 2>&1

print_message "✓ NAT configured successfully"
print_message "  Exit IP for clients will be: $VPS_PUBLIC_IP"
echo ""

# Step 5: Run cloudflared tunnel
print_header "Step 5/5: Starting cloudflared Service"

print_message "Installing cloudflared as system service..."
cloudflared service install

print_message "Starting cloudflared service..."
systemctl start cloudflared
systemctl enable cloudflared

# Wait for service to start
sleep 5

# Check service status
if systemctl is-active --quiet cloudflared; then
    print_message "✓ cloudflared service started successfully"
    
    # Try to get tunnel info
    print_message "Tunnel information:"
    cloudflared tunnel info $TUNNEL_NAME 2>/dev/null || print_warning "  (Use 'cloudflared tunnel info $TUNNEL_NAME' to check tunnel details)"
else
    print_error "cloudflared service failed to start!"
    print_error "Check logs with: journalctl -u cloudflared -n 50"
    exit 1
fi

print_message ""
print_warning "IMPORTANT: Configure hostname routes in Cloudflare Dashboard:"
print_warning "  1. Go to: Networks → Routes → Hostname routes"
print_warning "  2. Click 'Create hostname route'"
print_warning "  3. Add hostname route:"
print_warning "     - Hostname: * (for all traffic)"
print_warning "     - Tunnel: $TUNNEL_NAME"
print_warning "  4. Save and wait 1-2 minutes"
print_warning ""
print_warning "Configure Split Tunnels:"
print_warning "  1. Go to: Team & Resources → Devices → Device profiles → Default"
print_warning "  2. Split Tunnels → Manage"
print_warning "  3. Ensure 100.64.0.0/10 is NOT in exclude list"
print_warning "  4. Save"
print_warning ""
print_warning "Without these, clients will NOT route traffic through VPS!"


print_header "Setup Complete!"

echo -e "${GREEN}All components successfully installed and configured!${NC}\n"
echo -e "${YELLOW}Installed & Configured:${NC}"
echo -e "  ✓ cloudflared tunnel (configured for egress)"
echo -e "  ✓ WARP routing enabled"
echo -e "  ✓ NAT/masquerading configured"
echo -e "  ✓ System IP forwarding enabled"
echo -e "  ✓ Firewall rules configured"
echo ""

echo -e "${CYAN}VPS Information:${NC}"
echo -e "  IP Address:        ${GREEN}$VPS_PUBLIC_IP${NC}"
echo -e "  Network Interface: ${GREEN}$DEFAULT_INTERFACE${NC}"
echo -e "  SSH Port:          ${GREEN}22${NC}"
echo ""

echo -e "${CYAN}Service Status:${NC}"
echo -e "  cloudflared: ${GREEN}$(systemctl is-active cloudflared)${NC}"
echo -e "  Tunnel Name: ${GREEN}$TUNNEL_NAME${NC}"
echo ""

echo -e "${CYAN}NAT Configuration:${NC}"
echo -e "  NAT/Masquerading: ${GREEN}Enabled on $DEFAULT_INTERFACE${NC}"
echo -e "  Forwarding Rules: ${GREEN}Configured${NC}"
echo -e "  Exit IP:          ${GREEN}$VPS_PUBLIC_IP${NC}"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. ${BLUE}Verify cloudflared tunnel:${NC}"
echo -e "   ${CYAN}sudo systemctl status cloudflared${NC}"
echo -e "   ${CYAN}sudo cloudflared tunnel info $TUNNEL_NAME${NC}"
echo -e "   ${CYAN}sudo journalctl -u cloudflared -f${NC}"
echo ""
echo -e "2. ${BLUE}Verify NAT is working:${NC}"
echo -e "   ${CYAN}sudo iptables -t nat -L -v -n | grep MASQUERADE${NC}"
echo ""
echo -e "3. ${BLUE}Configure Hostname Routes in Dashboard:${NC}"
echo -e "   - Networks → Routes → Hostname routes"
echo -e "   - Add route: Hostname = *, Tunnel = $TUNNEL_NAME"
echo ""
echo -e "4. ${BLUE}Configure Split Tunnels:${NC}"
echo -e "   - Team & Resources → Devices → Device profiles → Default"
echo -e "   - Split Tunnels → Remove 100.64.0.0/10 from exclude list"
echo ""
echo -e "5. ${BLUE}On client device, test exit IP:${NC}"
echo -e "   ${CYAN}curl ifconfig.me${NC}"
echo -e "   Should show: ${GREEN}$VPS_PUBLIC_IP${NC}"
echo ""

echo -e "${GREEN}Setup completed at $(date)${NC}"
echo -e "${YELLOW}Read the complete guide in README.md${NC}"

exit 0
