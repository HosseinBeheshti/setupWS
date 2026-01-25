#!/bin/bash

# VPS Setup Script for Cloudflare WARP Connector VPN Replacement
# Installs required applications WITHOUT configuring Cloudflare services
# Configuration must be done manually following README.md
# Run with: sudo ./setup_server.sh

# Exit on any error
set -e

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

# --- Load Configuration ---
print_message "Loading configuration from workstation.env..."
ENV_FILE="./workstation.env"
if [[ ! -f "$ENV_FILE" ]]; then
    print_error "Configuration file not found: $ENV_FILE"
    exit 1
fi
source "$ENV_FILE"
print_message "Configuration loaded successfully."

# --- Check if running as root ---
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# --- Main Execution ---
print_header "VPS Application Setup - NO Cloudflare Configuration"
print_warning "This script ONLY installs applications."
print_warning "You must configure Cloudflare services manually (see README.md)"
echo ""

# Step 1: Update System
print_header "Step 1/5: Updating System"
print_message "Updating package lists..."
apt-get update
print_message "Upgrading packages..."
apt-get upgrade -y
print_message "✓ System updated"

# Step 2: Install Desktop Environment and VNC
print_header "Step 2/5: Installing Desktop Environment and VNC"

print_message "Installing Ubuntu Desktop and XFCE4..."
apt-get install -y ubuntu-desktop xfce4 xfce4-goodies

print_message "Installing VNC Server..."
apt-get install -y tigervnc-standalone-server tigervnc-common

print_message "✓ Desktop environment and VNC installed"
print_warning "Configure VNC manually: vncpasswd, create ~/.vnc/xstartup (see README.md section 2.2)"

# Step 3: Install L2TP/IPSec VPN
print_header "Step 3/5: Installing L2TP/IPSec VPN (Fallback)"

if [[ -f "./setup_l2tp.sh" ]]; then
    chmod +x "./setup_l2tp.sh"
    print_message "Running L2TP setup script..."
    ./setup_l2tp.sh
    if [[ $? -eq 0 ]]; then
        print_message "✓ L2TP/IPSec VPN installed"
    else
        print_warning "L2TP setup encountered issues, continuing..."
    fi
else
    print_warning "setup_l2tp.sh not found, skipping L2TP installation"
fi

# Step 4: Install Cloudflare WARP Client
print_header "Step 4/5: Installing Cloudflare WARP Client"

print_message "Adding Cloudflare repository..."
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list

print_message "Installing Cloudflare WARP..."
apt-get update && apt-get install -y cloudflare-warp

print_message "✓ Cloudflare WARP client installed"
print_warning "DO NOT register WARP yet! Follow README.md section 2.3 for configuration"

# Enable IP forwarding
print_message "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
fi
print_message "✓ IP forwarding enabled"

# Configure UFW firewall
print_message "Configuring firewall..."
ufw --force enable
ufw allow 22/tcp comment 'SSH'
print_message "✓ Firewall configured"

print_message "✓ Base Infrastructure setup completed"

# Step 1: Setup WARP Connector
print_header "Step 1/4: Setting up WARP Connector"
./setup_warp_connector.sh
if [[ $? -ne 0 ]]; then
    print_error "WARP Connector setup failed!"
    exit 1
fi
print_message "✓ WARP Connector setup completed successfully"

# Step 2: Setup VNC Server with Users
print_header "Step 2/4: Setting up VNC Server and Users"
./setup_vnc.sh
if [[ $? -ne 0 ]]; then
    print_error "VNC setup failed!"
    exit 1
fi
print_message "✓ VNC setup completed successfully"

# Step 3: Setup L2TP VPN for Infrastructure (Optional)
print_header "Step 3/4: Setting up L2TP VPN for Infrastructure Management"
if [[ -f "./setup_l2tp.sh" ]]; then
    read -p "Do you want to setup L2TP VPN for infrastructure access (virtual router, xRDP)? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ./setup_l2tp.sh
  Step 5: Configure System and Firewall
print_header "Step 5/5: Configuring System and Firewall"

# Enable IP forwarding
print_message "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null

# Make persistent
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
fi
sysctl -p > /dev/null

print_message "✓ IP forwarding enabled"

# Configure UFW firewall
print_message "Configuring firewall..."
ufw --force enable

# Allow SSH
ufw allow 22/tcp comment 'SSH'

# Allow VNC ports from configuration
for ((i=1; i<=VNC_USER_COUNT; i++)); do
    port_var="VNCUSER${i}_PORT"
    username_var="VNCUSER${i}_USERNAME"
    port="${!port_var}"
    username="${!username_var}"
    
    if [[ -n "$port" ]]; then
        ufw allow ${port}/tcp comment "VNC-${username}"
        print_message "  ✓ Allowed VNC port ${port} for user ${username}"
    fi
done

# Allow L2TP/IPSec
ufw allow 500/udp comment 'L2TP-IKE'
ufw allow 4500/udp comment 'L2TP-NAT-T'
ufw allow 1701/udp comment 'L2TP'

print_message "✓ Firewall configured"

# --- Installation Complete ---
print_header "Application Installation Complete!"

IP_ADDRESS=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}All applications have been successfully installed!${NC}\n"
echo -e "${YELLOW}Installed Components:${NC}"
echo -e "  ✓ Ubuntu Desktop + XFCE4"
echo -e "  ✓ TigerVNC Server"
echo -e "  ✓ L2TP/IPSec VPN"
echo -e "  ✓ Cloudflare WARP Client"
echo -e "  ✓ System IP forwarding enabled"
echo -e "  ✓ Firewall rules configured"
echo ""

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  IMPORTANT: CLOUDFLARE CONFIGURATION NOT DONE!${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}You must follow README.md to configure Cloudflare services:${NC}"
echo ""
echo -e "${CYAN}Part 1: Cloudflare Dashboard Setup${NC}"
echo -e "  1. Create WARP Connector tunnel (section 1.2)"
echo -e "  2. Configure device enrollment (section 1.3)"
echo -e "  3. Configure split tunnels (section 1.4)"
echo ""
echo -e "${CYAN}Part 2: VPS Configuration${NC}"
echo -e "  1. Configure VNC (section 2.2):"
echo -e "     ${GREEN}vncpasswd${NC}"
echo -e "     ${GREEN}mkdir -p ~/.vnc && vi ~/.vnc/xstartup${NC}"
echo -e "     ${GREEN}vncserver :1 -geometry 1920x1080 -depth 24${NC}"
echo ""
echo -e "  2. Register WARP Connector (section 2.3):"
echo -e "     ${GREEN}sudo warp-cli registration new --accept-tos${NC}"
echo -e "     ${GREEN}sudo warp-cli registration token <YOUR-TOKEN>${NC}"
echo -e "     ${GREEN}sudo warp-cli connect${NC}"
echo ""
echo -e "${CYAN}VPS Information:${NC}"
echo -e "  IP Address: ${GREEN}$IP_ADDRESS${NC}"
echo -e "  SSH Port:   ${GREEN}22${NC}"
echo -e "  VNC Ports:  ${GREEN}"
for ((i=1; i<=VNC_USER_COUNT; i++)); do
    port_var="VNCUSER${i}_PORT"
    username_var="VNCUSER${i}_USERNAME"
    port="${!port_var}"
    username="${!username_var}"
    if [[ -n "$port" ]]; then
        echo -e "              ${port} (${username})${NC}"
    fi
done
echo ""
echo -e "${YELLOW}Next: Follow README.md Part 2, section 2.2 onwards${NC}"
echo "