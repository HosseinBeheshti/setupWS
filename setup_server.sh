#!/bin/bash

# Master Setup Script for Cloudflare Zero Trust Network Access
# Implements Cloudflare One Agent with WARP Connector for VPN replacement
# Run with: sudo ./setup_server.sh

# Exit on any error
set -e

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

# --- Check if all required scripts exist ---
REQUIRED_SCRIPTS=("setup_vnc.sh" "setup_warp_connector.sh")
for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [[ ! -f "./$script" ]]; then
        print_error "Required script not found: $script"
        exit 1
    fi
    # Make sure scripts are executable
    chmod +x "./$script"
done

# Optional scripts
if [[ -f "./setup_l2tp.sh" ]]; then
    chmod +x "./setup_l2tp.sh"
fi

# --- Main Execution ---
print_header "Starting Cloudflare Zero Trust ZTNA Setup"

# Step 0: Setup Base Infrastructure (Cloudflare, Docker)
print_header "Step 0/4: Setting up Base Infrastructure"

print_message "Installing required packages..."
apt-get update
apt-get install -y \
    ca-certificates \
    gnupg \
    lsb-release \
    curl \
    wget \
    iptables \
    net-tools

print_message "✓ System packages installed"

# Install Docker using official method
print_message "Installing Docker..."
if ! command -v docker &> /dev/null; then
    # Remove old Docker installations
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Setup Docker repository
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    print_message "✓ Docker installed and started"
else
    print_message "✓ Docker already installed"
    # Ensure Docker is running
    if ! systemctl is-active --quiet docker; then
        systemctl start docker
        print_message "✓ Docker service started"
    fi
fi

# Verify Docker is working
if docker ps &> /dev/null; then
    print_message "✓ Docker is operational"
else
    print_error "Docker installation failed or service not running"
    print_message "Attempting to fix Docker service..."
    systemctl daemon-reload
    systemctl restart docker.socket
    systemctl restart docker
    sleep 5
    if ! docker ps &> /dev/null; then
        print_error "Docker still not working. Check logs: journalctl -xeu docker"
        exit 1
    fi
fi

print_message "✓ Packages installed"

# Install cloudflared
print_message "Installing cloudflared..."
if [[ ! -f "/usr/local/bin/cloudflared" ]]; then
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /tmp/cloudflared
    elif [[ "$ARCH" == "aarch64" ]]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -O /tmp/cloudflared
    else
        print_error "Unsupported architecture: $ARCH"
        exit 1
    fi
    chmod +x /tmp/cloudflared
    mv /tmp/cloudflared /usr/local/bin/cloudflared
    print_message "✓ cloudflared installed"
else
    print_message "✓ cloudflared already installed"
fi

# Create directory structure
print_message "Creating directory structure..."
mkdir -p /etc/cloudflare
chmod 700 /etc/cloudflare
print_message "✓ Directories created"

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
        if [[ $? -ne 0 ]]; then
            print_warning "L2TP VPN setup failed, but continuing..."
        else
            print_message "✓ L2TP VPN setup completed successfully"
        fi
    else
        print_message "Skipping L2TP VPN setup"
    fi
else
    print_message "setup_l2tp.sh not found, skipping L2TP setup"
fi

# Step 4: Configure Cloudflare Tunnel for VNC Access
print_header "Step 4/4: Configuring Cloudflare Tunnel for VNC Access"

print_message "Installing cloudflared if not present..."
if [[ ! -f "/usr/local/bin/cloudflared" ]]; then
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /tmp/cloudflared
    elif [[ "$ARCH" == "aarch64" ]]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -O /tmp/cloudflared
    else
        print_error "Unsupported architecture: $ARCH"
        exit 1
    fi
    chmod +x /tmp/cloudflared
    mv /tmp/cloudflared /usr/local/bin/cloudflared
    print_message "✓ cloudflared installed"
else
    print_message "✓ cloudflared already installed"
fi

print_message ""
print_message "IMPORTANT: You need to manually setup Cloudflare Tunnel for VNC access"
print_message "Follow the instructions at: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/create-remote-tunnel/"
print_message ""

# --- Final Summary ---
print_header "Setup Complete!"
echo -e "${GREEN}All components have been successfully installed and configured!${NC}\n"

echo -e "${YELLOW}Summary:${NC}"
echo -e "  ✓ WARP Connector for VPN replacement"
echo -e "  ✓ VNC Server with users"
echo -e "  ✓ Cloudflare Tunnel for VNC access (manual setup required)"
if [[ -f "./setup_l2tp.sh" ]] && [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "  ✓ L2TP VPN for infrastructure management"
fi
echo ""

# Display WARP Connector information
echo -e "${YELLOW}WARP Connector Status:${NC}"
echo -e "-----------------------------------------------------"
echo -e "  ${GREEN}Run this to check:${NC} sudo warp-cli status"
echo -e "  ${GREEN}Register:${NC}          sudo warp-cli registration new"
echo -e "  ${GREEN}Connect:${NC}           sudo warp-cli connect"
echo ""

# Display VNC user information
IP_ADDRESS=$(hostname -I | awk '{print $1}')
echo -e "${YELLOW}VNC Connection Details:${NC}"
echo -e "-----------------------------------------------------"

for ((i=1; i<=VNC_USER_COUNT; i++)); do
    username_var="VNCUSER${i}_USERNAME"
    display_var="VNCUSER${i}_DISPLAY"
    resolution_var="VNCUSER${i}_RESOLUTION"
    port_var="VNCUSER${i}_PORT"
    
    username="${!username_var}"
    display="${!display_var}"
    resolution="${!resolution_var}"
    port="${!port_var}"
    
    if [[ -n "$username" ]]; then
        echo -e "  ${GREEN}User:${NC}       $username"
        echo -e "  ${GREEN}Password:${NC}   [configured]"
        echo -e "  ${GREEN}Address:${NC}    $IP_ADDRESS:$port (Display :$display)"
        echo -e "  ${GREEN}Resolution:${NC} $resolution"
        echo ""
    fi
done

echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. ${BLUE}Complete WARP Connector Registration:${NC}"
echo -e "   ${CYAN}sudo warp-cli registration new${NC}"
echo -e "   Follow prompts to link to Cloudflare Zero Trust"
echo ""
echo -e "2. ${BLUE}Configure Split Tunnels in Cloudflare Dashboard:${NC}"
echo -e "   - Go to: Settings → WARP Client → Device settings → Split Tunnels"
echo -e "   - Exclude VPS IP: $IP_ADDRESS/32"
echo -e "   - See README.md for details"
echo ""
echo -e "3. ${BLUE}Setup Cloudflare Tunnel for VNC (Admin Access):${NC}"
echo -e "   - Go to: Networks → Tunnels → Create tunnel"
echo -e "   - Add routes for VNC ports"
echo -e "   - See README.md for complete setup"
echo ""
echo -e "4. ${BLUE}Configure Access Policies:${NC}"
echo -e "   - ${GREEN}Admin Policy:${NC} Access to VNC via Cloudflare Tunnel"
echo -e "   - ${GREEN}User Policy:${NC}  Route web traffic through WARP Connector"
echo -e "   - See README.md for policy configuration"
echo ""
echo -e "5. ${BLUE}Client Setup:${NC}"
echo -e "   - ${GREEN}Admins:${NC} Install Cloudflare One Agent, authenticate, access VNC"
echo -e "   - ${GREEN}Users:${NC}  Install Cloudflare One Agent, authenticate, browse web"
echo -e "   - Traffic exits through VPS IP: $IP_ADDRESS"
echo ""

echo -e "${GREEN}Setup completed at $(date)${NC}"
echo -e "${YELLOW}Read the complete guide in README.md${NC}"

exit 0
