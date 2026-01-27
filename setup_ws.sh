#!/bin/bash

# ============================================================
# Master Workstation Setup Script
# ============================================================
# This script orchestrates the complete VPS setup in the correct order:
# 1. Install all required packages (consolidated from all scripts)
# 2. Run setup_virtual_router.sh
# 3. Run setup_l2tp.sh (always installed for VPN_APPS)
# 4. Run setup_vnc.sh
# 5. Run setup_wg.sh (always installed for client VPN service)
# 6. Run setup_ztna.sh
#
# Run with: sudo ./setup_ws.sh
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

# --- Check if all required scripts exist ---
REQUIRED_SCRIPTS=("setup_virtual_router.sh" "setup_l2tp.sh" "setup_vnc.sh" "setup_wg.sh" "setup_ztna.sh")
for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [[ ! -f "./$script" ]]; then
        print_error "Required script not found: $script"
        exit 1
    fi
    # Make sure scripts are executable
    chmod +x "./$script"
done

# --- Main Execution ---
print_header "Starting Secure Remote Access Gateway Setup"
echo -e "${CYAN}Configuration:${NC}"
echo -e "  VPS IP: ${GREEN}${VPS_PUBLIC_IP:-auto-detect}${NC}"
echo -e "  VNC Users: ${GREEN}$VNC_USER_COUNT${NC}"
echo -e "  WireGuard Port: ${GREEN}${WG_SERVER_PORT:-51820}${NC}"
echo -e "  L2TP Apps: ${GREEN}${VPN_APPS:-none}${NC}"
echo ""

# ============================================================
# Step 1: Install All Required Packages
# ============================================================
print_header "Step 1/6: Installing All Required Packages"

print_message "This will install packages needed by all setup scripts..."
print_message "Updating package lists..."
apt-get update -qq

# Core system utilities (from APPS_TO_INSTALL + common requirements)
print_message "Installing core utilities..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    vim \
    htop \
    curl \
    wget \
    net-tools \
    ca-certificates \
    gnupg \
    software-properties-common \
    apt-transport-https

# Networking tools (from setup_virtual_router.sh)
print_message "Installing networking tools..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    iproute2 \
    iptables \
    iptables-persistent \
    netfilter-persistent

# VNC server packages (from setup_vnc.sh)
print_message "Installing VNC server and desktop environment..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    xfce4 \
    xfce4-goodies \
    dbus-x11 \
    tigervnc-standalone-server \
    firefox

# L2TP/IPsec packages (always installed for VPN_APPS routing)
print_message "Installing L2TP/IPsec VPN client packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    strongswan \
    xl2tpd \
    network-manager-l2tp \
    netcat-openbsd \
    iptables-persistent

# VPN Apps (from setup_l2tp.sh VPN_APPS)
if [[ -n "$VPN_APPS" ]]; then
    print_message "Installing VPN applications: $VPN_APPS"
    for app in $VPN_APPS; do
        case $app in
            "xrdp")
                DEBIAN_FRONTEND=noninteractive apt-get install -y xrdp
                ;;
            "remmina")
                DEBIAN_FRONTEND=noninteractive apt-get install -y remmina remmina-plugin-rdp remmina-plugin-vnc freerdp2-x11
                ;;
            *)
                DEBIAN_FRONTEND=noninteractive apt-get install -y "$app" || print_warning "Failed to install $app"
                ;;
        esac
    done
fi

# WireGuard packages (from setup_wg.sh)
print_message "Installing WireGuard VPN..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wireguard \
    wireguard-tools \
    qrencode

# UFW firewall
print_message "Installing UFW firewall..."
DEBIAN_FRONTEND=noninteractive apt-get install -y ufw

print_message "✓ All packages installed successfully"

# ============================================================
# Step 2: Install Docker (from setup_vnc.sh embedded install)
# ============================================================
print_header "Step 2/6: Installing Docker"

if ! command -v docker &> /dev/null; then
    print_message "Adding Docker GPG key and repository..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
    
    print_message "Installing Docker Engine and Docker Compose..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    print_message "✓ Docker installed successfully"
else
    print_message "✓ Docker already installed"
fi

# ============================================================
# Step 3: Install VS Code (from setup_vnc.sh embedded install)
# ============================================================
print_header "Step 3/6: Installing VS Code"

if ! command -v code &> /dev/null; then
    print_message "Adding Microsoft GPG key and repository..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg
    
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
    
    print_message "Installing VS Code..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y code
    
    print_message "✓ VS Code installed successfully"
else
    print_message "✓ VS Code already installed"
fi

# ============================================================
# Step 4: Install Google Chrome (from setup_vnc.sh embedded install)
# ============================================================
print_header "Step 4/6: Installing Google Chrome"

if ! command -v google-chrome &> /dev/null; then
    print_message "Adding Google Chrome signing key and repository..."
    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add -
    
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
    
    print_message "Installing Google Chrome..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y google-chrome-stable
    
    print_message "✓ Google Chrome installed successfully"
else
    print_message "✓ Google Chrome already installed"
fi

# ============================================================
# Step 5: Run Configuration Scripts
# ============================================================
print_header "Step 5/6: Running Configuration Scripts"

# 5.1: Setup Virtual Router
print_message "--- Running setup_virtual_router.sh ---"
./setup_virtual_router.sh
if [[ $? -ne 0 ]]; then
    print_error "Virtual Router setup failed!"
    exit 1
fi
print_message "✓ Virtual Router configured"
echo ""

# 5.2: Setup L2TP VPN (always installed for VPN_APPS)
print_message "--- Running setup_l2tp.sh ---"
./setup_l2tp.sh
if [[ $? -ne 0 ]]; then
    print_error "L2TP VPN setup failed!"
    exit 1
fi
print_message "✓ L2TP VPN configured for VPN_APPS"
echo ""

# 5.3: Setup VNC Server
print_message "--- Running setup_vnc.sh ---"
./setup_vnc.sh
if [[ $? -ne 0 ]]; then
    print_error "VNC setup failed!"
    exit 1
fi
print_message "✓ VNC Server configured"
echo ""

# 5.4: Setup WireGuard VPN
print_message "--- Running setup_wg.sh ---"
./setup_wg.sh
if [[ $? -ne 0 ]]; then
    print_error "WireGuard setup failed!"
    exit 1
fi
print_message "✓ WireGuard VPN configured"
echo ""

# 5.5: Setup Cloudflare Zero Trust Access
print_message "--- Running setup_ztna.sh ---"
./setup_ztna.sh
if [[ $? -ne 0 ]]; then
    print_error "Cloudflare Zero Trust setup failed!"
    exit 1
fi
print_message "✓ Cloudflare Zero Trust Access configured"
echo ""

# ============================================================
# Step 6: Configure Final Firewall Rules
# ============================================================
print_header "Step 6/6: Configuring Secure Firewall"

print_message "Configuring firewall to block direct SSH/VNC access..."
print_message "Access to SSH/VNC will ONLY be allowed through Cloudflare tunnel"

# Reset UFW to defaults
ufw --force reset

# Deny all incoming by default
ufw default deny incoming
ufw default allow outgoing

# Allow only WireGuard VPN
ufw allow ${WG_SERVER_PORT:-51820}/udp comment 'WireGuard VPN'
print_message "  ✓ WireGuard port ${WG_SERVER_PORT:-51820}/udp allowed"

# Allow L2TP/IPsec VPN
if [[ " $VPN_LIST " =~ " l2tp " ]]; then
    ufw allow 500/udp comment 'IPsec'
    ufw allow 1701/udp comment 'L2TP'
    ufw allow 4500/udp comment 'IPsec NAT-T'
    print_message "  ✓ L2TP/IPsec ports allowed"
fi

# Enable firewall
ufw --force enable

print_message "✓ Firewall configured - SSH/VNC only accessible via Cloudflare"
print_warning "Direct SSH/VNC access is BLOCKED. Access only via Cloudflare tunnel."
echo ""

# ============================================================
# Step 7: Final Summary
# ============================================================
print_header "Setup Complete!"

echo -e "${GREEN}All components have been successfully installed and configured!${NC}\n"

echo -e "${YELLOW}Installed Components:${NC}"
echo -e "  ✓ Core system utilities and networking tools"
echo -e "  ✓ Docker Engine and Docker Compose"
echo -e "  ✓ VS Code and Google Chrome"
echo -e "  ✓ VNC Server with $VNC_USER_COUNT user(s)"
echo -e "  ✓ WireGuard VPN Server (for client devices)"
echo -e "  ✓ L2TP/IPsec VPN (for VPN_APPS in VNC sessions)"
echo -e "  ✓ Cloudflare Zero Trust Access (SSH/VNC)"
echo -e "  ✓ Virtual Router for VPN traffic"
echo ""

# Display VNC connection details
IP_ADDRESS=$(hostname -I | awk '{print $1}')
echo -e "${CYAN}VNC Connection Details:${NC}"
echo -e "-----------------------------------------------------"

for ((i=1; i<=VNC_USER_COUNT; i++)); do
    username_var="VNCUSER${i}_USERNAME"
    port_var="VNCUSER${i}_PORT"
    display_var="VNCUSER${i}_DISPLAY"
    resolution_var="VNCUSER${i}_RESOLUTION"
    
    username="${!username_var}"
    port="${!port_var}"
    display="${!display_var}"
    resolution="${!resolution_var}"
    
    if [[ -n "$username" ]]; then
        echo -e "  ${GREEN}User:${NC}       $username"
        echo -e "  ${GREEN}Address:${NC}    $IP_ADDRESS:$port (Display :$display)"
        echo -e "  ${GREEN}Resolution:${NC} $resolution"
        echo ""
    fi
done

echo -e "-----------------------------------------------------"
echo ""

# Display WireGuard details
echo -e "${CYAN}WireGuard VPN Details:${NC}"
echo -e "-----------------------------------------------------"
echo -e "  ${GREEN}Server IP:${NC}    $VPS_PUBLIC_IP"
echo -e "  ${GREEN}VPN Port:${NC}     ${WG_SERVER_PORT}"
echo -e "  ${GREEN}Management:${NC}   Use ./manage_wg_client.sh"
echo -e "-----------------------------------------------------"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo -e ""
echo -e "1. ${BLUE}Connect to VNC:${NC}"
echo -e "   Use the connection details above with your VNC client"
echo -e ""
echo -e "2. ${BLUE}Add WireGuard clients:${NC}"
echo -e "   ${CYAN}sudo ./manage_wg_client.sh add laptop${NC}"
echo -e "   ${CYAN}sudo ./manage_wg_client.sh add phone${NC}"
echo -e ""
echo -e "3. ${BLUE}Test WireGuard VPN:${NC}"
echo -e "   - Connect with WireGuard client"
echo -e "   - Verify exit IP: ${CYAN}curl ifconfig.me${NC}"
echo -e "   - Should show: ${GREEN}$VPS_PUBLIC_IP${NC}"
echo -e ""
echo -e "4. ${BLUE}Use L2TP for VPN_APPS (in VNC session):${NC}"
echo -e "   Run: ${CYAN}sudo ./run_vpn.sh${NC}"
echo -e "   Routes apps: ${GREEN}$VPN_APPS${NC}"
echo -e ""
echo -e "5. ${BLUE}Monitor services:${NC}"
echo -e "   - WireGuard: ${CYAN}sudo wg show${NC}"
echo -e "   - VNC: ${CYAN}systemctl status vncserver-<username>@<display>${NC}"
echo -e "   - Cloudflare: ${CYAN}systemctl status cloudflared${NC}"
echo -e ""

echo -e "${GREEN}Setup completed at $(date)${NC}"
echo -e "${YELLOW}Read the complete guide in README.md${NC}"

exit 0
