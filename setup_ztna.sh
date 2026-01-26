#!/bin/bash

# ============================================================
# Cloudflare WARP Connector VPN Replacement - Automated Setup
# ============================================================
# This script performs complete VPS setup for WARP Connector:
# - Installs Cloudflare WARP Connector
# - Configures WARP Connector with token from workstation.env
# - Enables IP forwarding for routing
# - Configures firewall
# - Starts all services automatically
#
# Prerequisites:
# 1. Complete Part 1 in README.md (Cloudflare dashboard setup)
# 2. Add CLOUDFLARE_WARP_TOKEN to workstation.env
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
if [[ -z "$CLOUDFLARE_WARP_TOKEN" ]]; then
    print_error "CLOUDFLARE_WARP_TOKEN is not set in workstation.env"
    print_error "Please complete Part 1 in README.md and add the token"
    exit 1
fi

# Detect VPS IP if not set
if [[ -z "$VPS_PUBLIC_IP" ]]; then
    VPS_PUBLIC_IP=$(hostname -I | awk '{print $1}')
    print_message "Auto-detected VPS IP: $VPS_PUBLIC_IP"
fi

print_header "Cloudflare WARP Connector - Automated Setup"
echo -e "${CYAN}VPS IP:${NC} $VPS_PUBLIC_IP"
echo -e "${CYAN}WARP Token:${NC} ${CLOUDFLARE_WARP_TOKEN:0:20}...${CLOUDFLARE_WARP_TOKEN: -10}"
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

# Step 3: Install and Configure Cloudflare WARP Connector
print_header "Step 3/4: Installing Cloudflare WARP Connector"

# 1. Setup pubkey, apt repo, and update/install WARP
print_message "Adding Cloudflare repository..."
curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list

print_message "Installing Cloudflare WARP..."
apt-get update && apt-get install cloudflare-warp

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

# Step 5: Run the WARP Connector with token
print_warning "⚠️  WARNING: The next command will disconnect your SSH session!"
print_warning "⚠️  This is expected behavior when WARP Connector activates."
print_warning "⚠️  Wait 30 seconds, then reconnect via SSH to verify setup."
echo ""
read -p "Press Enter to continue with WARP activation (this will drop SSH)..." -t 10 || true
echo ""

print_message "Running WARP Connector with token (SSH will disconnect)..."
warp-cli connector new "$CLOUDFLARE_WARP_TOKEN"

print_message "Connecting WARP Connector..."
warp-cli connect

# Check connection status
sleep 5
if warp-cli status | grep -q "Connected"; then
    print_message "✓ WARP Connector connected successfully"
    print_message ""
    print_warning "IMPORTANT: Configure Split Tunnels in Cloudflare Dashboard:"
    print_warning "  1. Go to: Settings → WARP Client → Device settings → Profile Settings"
    print_warning "  2. Split Tunnels: Select 'Tunnel all traffic' (Exclude mode)"
    print_warning "  3. Or add 0.0.0.0/0 to Include mode to route ALL traffic"
    print_warning "  4. Save and wait 1-2 minutes for clients to sync"
    print_warning ""
    print_warning "Without this, clients will NOT route traffic through VPS!"
else
    print_error "WARP Connector connection FAILED!"
    print_error "Check status with: sudo warp-cli status"
    print_error "Check logs with: journalctl -u warp-svc -n 50"
    exit 1
fi


print_header "Setup Complete!"

echo -e "${GREEN}All components successfully installed and configured!${NC}\n"
echo -e "${YELLOW}Installed & Configured:${NC}"
echo -e "  ✓ Cloudflare WARP Connector (registered & connected)"
echo -e "  ✓ System IP forwarding enabled"
echo -e "  ✓ Firewall rules configured"
echo ""

echo -e "${CYAN}VPS Information:${NC}"
echo -e "  IP Address:        ${GREEN}$VPS_PUBLIC_IP${NC}"
echo -e "  Network Interface: ${GREEN}$DEFAULT_INTERFACE${NC}"
echo -e "  SSH Port:          ${GREEN}22${NC}"
echo ""

echo -e "${CYAN}Service Status:${NC}"
echo -e "  WARP Connector: ${GREEN}$(warp-cli status 2>/dev/null | head -1 || echo 'Check with: sudo warp-cli status')${NC}"
echo ""

echo -e "${CYAN}NAT Configuration:${NC}"
echo -e "  NAT/Masquerading: ${GREEN}Enabled on $DEFAULT_INTERFACE${NC}"
echo -e "  Forwarding Rules: ${GREEN}Configured${NC}"
echo -e "  Exit IP:          ${GREEN}$VPS_PUBLIC_IP${NC}"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. ${BLUE}Verify WARP Connector:${NC}"
echo -e "   ${CYAN}sudo warp-cli status${NC}"
echo -e "   ${CYAN}sudo warp-cli account${NC}"
echo ""
echo -e "2. ${BLUE}Verify NAT is working:${NC}"
echo -e "   ${CYAN}sudo iptables -t nat -L -v -n${NC}"
echo -e "   (Check MASQUERADE rule on $DEFAULT_INTERFACE)"
echo ""
echo -e "3. ${BLUE}Configure Split Tunnels in Cloudflare Dashboard:${NC}"
echo -e "   - Go to: Settings → WARP Client → Device profiles → Default"
echo -e "   - Split Tunnels: Ensure mode is 'Exclude IPs and domains'"
echo -e "   - Do NOT exclude 0.0.0.0/0 (all traffic should go through WARP)"
echo ""
echo -e "4. ${BLUE}On client device, test exit IP:${NC}"
echo -e "   ${CYAN}curl ifconfig.me${NC}"
echo -e "   Should show: ${GREEN}$VPS_PUBLIC_IP${NC}"
echo -e "   If it shows Cloudflare IP, traffic is NOT routing through VPS!"
echo ""
echo -e "5. ${BLUE}Configure SSH Access (Part 3 in README.md):${NC}"
echo -e "   - Create SSH application in Cloudflare dashboard"
echo -e "   - Or use direct SSH: ${CYAN}ssh root@$VPS_PUBLIC_IP${NC}"
echo ""

echo -e "${GREEN}Setup completed at $(date)${NC}"
echo -e "${YELLOW}Read the complete guide in README.md${NC}"

exit 0
