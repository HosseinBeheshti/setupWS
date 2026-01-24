#!/bin/bash

################################################################################
# Cloudflare WARP Connector Setup Script
# Description: Install and configure WARP Connector on VPS to route user traffic
# Usage: sudo ./setup_warp_connector.sh
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

echo -e "${BLUE}========================================"
echo "Cloudflare WARP Connector Setup"
echo "========================================${NC}"
echo ""

# Load environment configuration
ENV_FILE="./workstation.env"
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: Configuration file not found: $ENV_FILE${NC}"
    exit 1
fi
source "$ENV_FILE"

# Detect OS and architecture
detect_system() {
    echo -e "${CYAN}→ Detecting system...${NC}"
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case "$ARCH" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            echo -e "${RED}Error: Unsupported architecture: $ARCH${NC}"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}  ✓ Detected: $OS $ARCH${NC}"
}

# Install WARP Connector package
install_warp_connector() {
    echo ""
    echo -e "${CYAN}→ Installing Cloudflare WARP Connector...${NC}"
    
    # Add Cloudflare GPG key
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    
    # Add Cloudflare WARP repository
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    
    # Update and install
    apt-get update
    apt-get install -y cloudflare-warp
    
    echo -e "${GREEN}  ✓ WARP Connector installed${NC}"
}

# Configure system for routing
configure_system() {
    echo ""
    echo -e "${CYAN}→ Configuring system for traffic routing...${NC}"
    
    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1
    sysctl -w net.ipv6.conf.all.forwarding=1
    
    # Make it persistent
    cat > /etc/sysctl.d/99-warp-routing.conf <<EOF
# WARP Connector routing configuration
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.rp_filter=2
EOF
    
    sysctl -p /etc/sysctl.d/99-warp-routing.conf
    
    echo -e "${GREEN}  ✓ System configured for routing${NC}"
}

# Configure firewall
configure_firewall() {
    echo ""
    echo -e "${CYAN}→ Configuring firewall (UFW)...${NC}"
    
    # Install UFW if not present
    if ! command -v ufw &> /dev/null; then
        apt-get install -y ufw
    fi
    
    # Reset UFW to clean state (non-interactive)
    echo "y" | ufw reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH access
    ufw allow 22/tcp comment 'SSH access'
    
    # VNC ports (from workstation.env)
    if [ -n "$VNC_PORT_WORKSTATION" ]; then
        ufw allow "$VNC_PORT_WORKSTATION/tcp" comment 'VNC Workstation'
    fi
    if [ -n "$VNC_PORT_DESIGN" ]; then
        ufw allow "$VNC_PORT_DESIGN/tcp" comment 'VNC Design'
    fi
    if [ -n "$VNC_PORT_TV" ]; then
        ufw allow "$VNC_PORT_TV/tcp" comment 'VNC TV'
    fi
    
    # Enable UFW (non-interactive)
    echo "y" | ufw enable
    
    ufw status verbose
    
    echo -e "${GREEN}  ✓ Firewall configured${NC}"
}

# Register WARP Connector with Cloudflare
register_warp_connector() {
    echo ""
    echo -e "${BLUE}========================================"
    echo "WARP Connector Registration"
    echo -e "========================================${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: You need to register this WARP Connector with your Cloudflare Zero Trust account${NC}"
    echo ""
    echo "Steps to complete registration:"
    echo ""
    echo "1. Run this command to register:"
    echo -e "   ${CYAN}warp-cli registration new${NC}"
    echo ""
    echo "2. Get the registration token from Cloudflare Dashboard:"
    echo "   a. Go to: https://one.dash.cloudflare.com/"
    echo "   b. Navigate to: Networks → Tunnels"
    echo "   c. Click: Create a tunnel"
    echo "   d. Select: Cloudflared (not Warp Connector)"
    echo ""
    echo "   WAIT! For WARP Connector, you need to:"
    echo "   a. Go to: Settings → WARP Client"
    echo "   b. Scroll to: Device settings"
    echo "   c. Click: Manage → Default"
    echo "   d. Under 'Service mode', enable: Gateway with WARP"
    echo ""
    echo "3. Then register the connector:"
    echo -e "   ${CYAN}warp-cli registration token <YOUR_TOKEN>${NC}"
    echo ""
    echo "4. Connect WARP Connector:"
    echo -e "   ${CYAN}warp-cli connect${NC}"
    echo ""
    echo "5. Verify connection:"
    echo -e "   ${CYAN}warp-cli status${NC}"
    echo ""
    echo -e "${YELLOW}Note: WARP Connector will route all user traffic through this VPS${NC}"
    echo ""
}

# Create post-installation guide
create_guide() {
    cat > /root/warp_connector_guide.txt <<'EOF'
Cloudflare WARP Connector - Post-Installation Guide
===================================================

1. REGISTER WARP CONNECTOR WITH CLOUDFLARE
   
   Get your team name from: https://one.dash.cloudflare.com/
   (You'll see it in the URL: https://one.dash.cloudflare.com/<TEAM_NAME>/)
   
   Register:
   sudo warp-cli registration new
   
   Connect with organization:
   sudo warp-cli registration token <YOUR_TOKEN>
   
   Connect:
   sudo warp-cli connect


2. CONFIGURE SPLIT TUNNELS IN CLOUDFLARE DASHBOARD
   
   a. Go to: Settings → WARP Client → Device settings → Manage → Default
   
   b. Scroll to: Split Tunnels
   
   c. Click: Manage → Add
   
   d. Mode: Exclude IPs and domains
   
   e. Add these exclusions:
      - 65.109.210.232/32  (this VPS IP - prevents routing loop)
      - 10.0.0.0/8          (private networks)
      - 172.16.0.0/12       (private networks)
      - 192.168.0.0/16      (private networks)


3. CONFIGURE GATEWAY NETWORK POLICIES
   
   a. Go to: Traffic policies → Firewall policies → Network tab
   
   b. Create policy: "Allow Authenticated Users"
      - Selector: User Email
      - Operator: matches regex
      - Value: .*
      - Action: Allow
   
   This ensures only authenticated users can use WARP Connector


4. VERIFY WARP CONNECTOR STATUS
   
   Check connection:
   sudo warp-cli status
   
   Check account:
   sudo warp-cli account
   
   Check settings:
   sudo warp-cli settings
   
   View logs:
   sudo journalctl -u warp-svc -f


5. CLIENT SETUP (Users)
   
   Install Cloudflare One Agent:
   - Android: com.cloudflare.cloudflareoneagent
   - iOS: id6443476492
   - Windows/Mac/Linux: https://1.1.1.1/
   
   Configure:
   - Open app → Settings → Account → Login with Cloudflare Zero Trust
   - Enter team name: noise-ztna
   - Authenticate with Gmail (One-time PIN)
   - Toggle connection ON


6. VERIFY TRAFFIC ROUTING THROUGH VPS
   
   From client device:
   curl ifconfig.me
   
   Should show VPS IP: 65.109.210.232


7. TROUBLESHOOTING
   
   If connection fails:
   sudo warp-cli registration delete
   sudo warp-cli registration new
   
   If traffic not routing:
   - Check Split Tunnels configuration
   - Verify Gateway Network Policies allow your user
   - Check WARP Connector status: sudo warp-cli status
   
   View detailed logs:
   sudo warp-cli debug-log on
   sudo journalctl -u warp-svc -f


8. USEFUL COMMANDS
   
   sudo warp-cli status              # Connection status
   sudo warp-cli connect             # Connect
   sudo warp-cli disconnect          # Disconnect
   sudo warp-cli account             # Account info
   sudo warp-cli settings            # Current settings
   sudo systemctl status warp-svc    # Service status
   sudo systemctl restart warp-svc   # Restart service

EOF

    echo -e "${GREEN}  ✓ Post-installation guide created at: /root/warp_connector_guide.txt${NC}"
}

# Main installation flow
main() {
    detect_system
    install_warp_connector
    configure_system
    configure_firewall
    create_guide
    
    echo ""
    echo -e "${GREEN}========================================"
    echo "Installation Complete!"
    echo -e "========================================${NC}"
    echo ""
    echo -e "${YELLOW}NEXT STEPS:${NC}"
    echo ""
    echo "1. Complete WARP Connector registration:"
    echo -e "   ${CYAN}sudo warp-cli registration new${NC}"
    echo ""
    echo "2. Get registration token from Cloudflare Dashboard"
    echo "   and register this connector"
    echo ""
    echo "3. Read the complete guide:"
    echo -e "   ${CYAN}cat /root/warp_connector_guide.txt${NC}"
    echo ""
    echo -e "${GREEN}Users can now connect via Cloudflare One Agent and route traffic through this VPS!${NC}"
    echo ""
}

# Run main function
main
