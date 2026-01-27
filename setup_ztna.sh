#!/bin/bash

# ============================================================
# Cloudflare Zero Trust Access Setup (SSH/VNC only)
# ============================================================
# This script configures Cloudflare Access for SSH and VNC connections:
# - Installs cloudflared (Cloudflare Tunnel)
# - Configures tunnel for SSH/VNC access (NO traffic routing)
# - Opens firewall ports for WireGuard and L2TP (direct VPS access)
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

# Step 1: Configure Firewall (Allow VPN Ports for Direct Access)
print_header "Step 1/4: Configuring Firewall"

print_message "Configuring UFW firewall..."
ufw --force enable > /dev/null

# Allow SSH
ufw allow 22/tcp comment 'SSH' > /dev/null
print_message "  ✓ Allowed SSH (port 22)"

# Allow WireGuard (direct access, bypass Cloudflare)
ufw allow ${WG_SERVER_PORT:-51820}/udp comment 'WireGuard VPN' > /dev/null
print_message "  ✓ Allowed WireGuard (port ${WG_SERVER_PORT:-51820}/udp)"

# Allow L2TP/IPsec (direct access, bypass Cloudflare)
ufw allow 500/udp comment 'IPsec' > /dev/null
ufw allow 1701/udp comment 'L2TP' > /dev/null
ufw allow 4500/udp comment 'IPsec NAT-T' > /dev/null
print_message "  ✓ Allowed L2TP/IPsec (ports 500, 1701, 4500/udp)"

# Allow VNC ports (for direct access if needed)
for ((i=1; i<=VNC_USER_COUNT; i++)); do
    port_var="VNCUSER${i}_PORT"
    port="${!port_var}"
    if [[ -n "$port" ]]; then
        ufw allow ${port}/tcp comment "VNC User ${i}" > /dev/null
        print_message "  ✓ Allowed VNC port $port/tcp"
    fi
done

print_message "✓ Firewall configured"

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

# 4. Install cloudflared service with tunnel token
print_message "Installing cloudflared service with tunnel token..."
cloudflared service install "$CLOUDFLARE_TUNNEL_TOKEN"

print_message "✓ cloudflared service installed"

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
    
    # Try to get tunnel info
    print_message "Tunnel information:"
    cloudflared tunnel info 2>/dev/null || print_warning "  (Tunnel connected via token)"
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
echo -e "  ✓ Firewall rules (SSH, WireGuard, L2TP, VNC ports)"
echo -e "  ✓ VPN ports open for direct access (bypass Cloudflare)"
echo ""

echo -e "${CYAN}VPS Information:${NC}"
echo -e "  IP Address:   ${GREEN}$VPS_PUBLIC_IP${NC}"
echo -e "  SSH Port:     ${GREEN}22${NC}"
echo -e "  WireGuard:    ${GREEN}${WG_SERVER_PORT:-51820}/udp${NC}"
echo -e "  L2TP/IPsec:   ${GREEN}500, 1701, 4500/udp${NC}"
echo ""

echo -e "${CYAN}VNC Ports:${NC}"
for ((i=1; i<=VNC_USER_COUNT; i++)); do
    port_var="VNCUSER${i}_PORT"
    username_var="VNCUSER${i}_USERNAME"
    port="${!port_var}"
    username="${!username_var}"
    if [[ -n "$port" ]]; then
        echo -e "  ${username:-User $i}: ${GREEN}${port}/tcp${NC}"
    fi
done
echo ""

echo -e "${CYAN}Service Status:${NC}"
echo -e "  cloudflared: ${GREEN}$(systemctl is-active cloudflared)${NC}"
echo -e "  Tunnel Name: ${GREEN}$TUNNEL_NAME${NC}"
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
echo -e "   ${CYAN}sudo cloudflared tunnel info $TUNNEL_NAME${NC}"
echo ""
echo -e "4. ${BLUE}VPN Access (Direct, NOT via Cloudflare):${NC}"
echo -e "   - WireGuard: Connect using client configs in /etc/wireguard/clients/"
echo -e "   - L2TP: Run ${CYAN}sudo ./run_vpn.sh${NC}"
echo ""
echo -e "4. ${BLUE}VPN Access (Direct, NOT via Cloudflare):${NC}"
echo -e "   - WireGuard: Connect using client configs in /etc/wireguard/clients/"
echo -e "   - L2TP: Run ${CYAN}sudo ./run_vpn.sh${NC}"
echo ""

echo -e "${CYAN}Important:${NC} VPN traffic (WireGuard/L2TP) bypasses Cloudflare and connects directly to VPS"
echo -e "${CYAN}           SSH/VNC access uses Cloudflare Access for identity-aware security${NC}"
echo ""

echo -e "${GREEN}Setup completed at $(date)${NC}"
echo -e "${YELLOW}Read the complete guide in README.md${NC}"

exit 0
