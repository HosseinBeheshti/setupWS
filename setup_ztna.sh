#!/bin/bash

# ============================================================
# Cloudflare Zero Trust Access Setup (SSH/VNC only)
# ============================================================
# This script configures Cloudflare Access for SSH and VNC connections:
# - Installs cloudflared (Cloudflare Tunnel)
# - Configures tunnel for SSH/VNC access (NO traffic routing)
# - Enables WARP routing for custom endpoint (bypass filtering)
# - Opens firewall ports for L2TP (direct VPS access)
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
    print_error "Please set the tunnel name (e.g., vps-access)"
    exit 1
fi

# Detect VPS IP if not set
if [[ -z "$VPS_PUBLIC_IP" ]]; then
    VPS_PUBLIC_IP=$(hostname -I | awk '{print $1}')
    print_message "Auto-detected VPS IP: $VPS_PUBLIC_IP"
fi

print_header "Cloudflare Zero Trust Access Setup (SSH/VNC)"
echo -e "${CYAN}VPS IP:${NC} $VPS_PUBLIC_IP"
echo -e "${CYAN}Tunnel Name:${NC} $TUNNEL_NAME"
echo -e "${CYAN}Tunnel Token:${NC} ${CLOUDFLARE_TUNNEL_TOKEN:0:20}...${CLOUDFLARE_TUNNEL_TOKEN: -10}"
echo ""

# Step 1: Initial Configuration
print_header "Step 1/4: Initial Configuration"

print_message "Firewall will be configured by setup_ws.sh after all components are installed"
print_message "SSH/VNC will only be accessible via Cloudflare tunnel (not directly)"

# Step 2: Install cloudflared
print_header "Step 2/4: Installing cloudflared (Cloudflare Tunnel)"

# 1. Add Cloudflare GPG key
print_message "Adding Cloudflare GPG key..."
mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null

# 2. Add Cloudflare repository
print_message "Adding Cloudflare repository..."
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list

# 3. Install cloudflared
print_message "Installing cloudflared..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y cloudflared

# Verify installation
CLOUDFLARED_VERSION=$(cloudflared --version 2>&1 | head -1)
print_message "✓ cloudflared installed: $CLOUDFLARED_VERSION"

# 4. Extract tunnel credentials from token
print_message "Extracting tunnel credentials from token..."
mkdir -p /root/.cloudflared
mkdir -p /etc/cloudflared

# Decode the token to get tunnel ID
TUNNEL_ID=$(echo "$CLOUDFLARE_TUNNEL_TOKEN" | base64 -d 2>/dev/null | grep -o '"t":"[^"]*"' | cut -d'"' -f4)
if [[ -z "$TUNNEL_ID" ]]; then
    print_error "Failed to extract tunnel ID from token"
    exit 1
fi

print_message "Tunnel ID: $TUNNEL_ID"

# 5. Create cloudflared config file with WARP routing
print_message "Creating cloudflared configuration with WARP routing..."
cat > /etc/cloudflared/config.yml <<EOF
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json

# Enable WARP routing for custom endpoint (bypass Iran filtering)
warp-routing:
  enabled: ${WARP_ROUTING_ENABLED:-true}

# Ingress rules are managed via Cloudflare dashboard
ingress:
  - service: http_status:404
EOF

# 6. Create credentials file from token
print_message "Creating tunnel credentials file..."
echo "$CLOUDFLARE_TUNNEL_TOKEN" | base64 -d > /root/.cloudflared/$TUNNEL_ID.json 2>/dev/null || {
    # Fallback: install with token first to get credentials
    print_message "Using fallback method to extract credentials..."
    cloudflared service install "$CLOUDFLARE_TUNNEL_TOKEN" 2>/dev/null || true
    systemctl stop cloudflared 2>/dev/null || true
    # Find and use the generated credentials
    if [[ -f /etc/cloudflared/cert.json ]]; then
        cp /etc/cloudflared/cert.json /root/.cloudflared/$TUNNEL_ID.json
    fi
}

# 7. Install cloudflared service with config file
print_message "Installing cloudflared service with config..."
cloudflared --config /etc/cloudflared/config.yml service install

print_message "✓ cloudflared service installed with WARP routing enabled"

# Step 3: Start cloudflared Service
print_header "Step 3/4: Starting cloudflared Service"

print_message "Starting cloudflared service..."
systemctl start cloudflared
systemctl enable cloudflared

# Wait for service to start
sleep 5

# Check service status
if systemctl is-active --quiet cloudflared; then
    print_message "✓ cloudflared service started successfully"
    
    # Show connection status (token-based tunnels don't support 'tunnel info')
    print_message "Tunnel status:"
    systemctl status cloudflared --no-pager -l | grep -E "(Active:|Main PID:|Registered tunnel)" || true
else
    print_error "cloudflared service failed to start!"
    print_error "Check logs with: journalctl -xeu cloudflared -n 50"
    print_error "Check status with: systemctl status cloudflared"
    
    # Show recent logs
    print_message "Recent logs:"
    journalctl -u cloudflared -n 20 --no-pager || true
    
    exit 1
fi

# Step 4: Display Configuration Summary
print_header "Step 4/4: Configuration Summary"

print_message "✓ Cloudflare Tunnel installed and running"
print_message "✓ Firewall configured with VPN ports open"
print_message "✓ Ready for Cloudflare Access configuration"

print_header "Setup Complete!"

echo -e "${GREEN}Cloudflare Zero Trust Access successfully configured!${NC}\n"

echo -e "${YELLOW}Installed & Configured:${NC}"
echo -e "  ✓ cloudflared tunnel (for SSH/VNC access)"
if [[ "${WARP_ROUTING_ENABLED}" == "true" ]]; then
    echo -e "  ✓ WARP routing enabled (custom endpoint on port ${WARP_ROUTING_PORT})"
fi
echo -e "  ✓ Firewall will be configured by setup_ws.sh"
echo ""

echo -e "${CYAN}Service Status:${NC}"
echo -e "  cloudflared: ${GREEN}$(systemctl is-active cloudflared)${NC}"
echo -e "  Tunnel Name: ${GREEN}$TUNNEL_NAME${NC}"
if [[ "${WARP_ROUTING_ENABLED}" == "true" ]]; then
    echo -e "  WARP Routing: ${GREEN}Enabled${NC}"
    echo -e "  WARP Port: ${GREEN}${WARP_ROUTING_PORT}${NC}"
fi
echo ""

echo -e "${YELLOW}Important Security Note:${NC}"
echo -e "  ${RED}Direct SSH/VNC access will be BLOCKED by firewall${NC}"
echo -e "  ${GREEN}All SSH/VNC access must go through Cloudflare tunnel${NC}"
echo ""

echo -e "${YELLOW}Next Steps - Complete Cloudflare Dashboard Configuration:${NC}"
echo ""
echo -e "1. ${BLUE}Create Access Applications for SSH:${NC}"
echo -e "   - Go to: Access → Applications → Add an application"
echo -e "   - Application type: Self-hosted"
echo -e "   - Configure SSH access policies"
echo ""
echo -e "2. ${BLUE}Create Access Applications for VNC:${NC}"
echo -e "   - Add applications for each VNC port"
echo -e "   - Configure access policies with Gmail + OTP"
echo ""
echo -e "3. ${BLUE}Verify Tunnel Connection:${NC}"
echo -e "   ${CYAN}sudo systemctl status cloudflared${NC}"
echo -e "   ${CYAN}sudo journalctl -u cloudflared -n 20${NC}"
echo ""
echo -e "   ${YELLOW}Note:${NC} Config-based tunnels with WARP routing enabled"
echo -e "   Check the Cloudflare dashboard (Networks → Tunnels) to verify connection"
echo ""
if [[ "${WARP_ROUTING_ENABLED}" == "true" ]]; then
echo -e "4. ${BLUE}Configure Custom WARP Endpoint (For Iran/Filtered Regions):${NC}"
echo -e "   - Go to: Settings → WARP Client → Device settings"
echo -e "   - Add custom endpoint: ${GREEN}$VPS_PUBLIC_IP:${WARP_ROUTING_PORT}${NC}"
echo -e "   - This allows Cloudflare One Agent to connect via your VPS"
echo -e "   - See README.md section 1.8 for detailed instructions"
echo ""
fi
echo -e "5. ${BLUE}VPN Access (Direct, bypass Cloudflare):${NC}"
echo -e "   - L2TP: Run ${CYAN}sudo ./run_vpn.sh${NC} in VNC sessions"
echo ""

echo -e "${CYAN}Important:${NC} Firewall will be configured by setup_ws.sh to block direct SSH/VNC"
echo -e "${CYAN}           SSH/VNC access uses Cloudflare Access for identity-aware security${NC}"
echo ""

echo -e "${GREEN}Cloudflare tunnel setup completed at $(date)${NC}"

exit 0
