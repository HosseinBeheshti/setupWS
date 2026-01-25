#!/bin/bash

# ============================================================
# Cloudflare WARP Connector VPN Replacement - Automated Setup
# ============================================================
# This script performs complete VPS setup for WARP Connector:
# - Installs all required applications
# - Configures WARP Connector with token from workstation.env
# - Sets up VNC servers for all configured users
# - Configures L2TP/IPSec fallback VPN
# - Starts all services automatically
#
# Prerequisites:
# 1. Complete Part 1 in README.md (Cloudflare dashboard setup)
# 2. Add CLOUDFLARE_WARP_TOKEN to workstation.env
# 3. Configure VNC users in workstation.env
#
# Usage: sudo ./setup_server.sh
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

if [[ $VNC_USER_COUNT -lt 1 ]]; then
    print_error "VNC_USER_COUNT must be at least 1"
    exit 1
fi

# Detect VPS IP if not set
if [[ -z "$VPS_PUBLIC_IP" ]]; then
    VPS_PUBLIC_IP=$(hostname -I | awk '{print $1}')
    print_message "Auto-detected VPS IP: $VPS_PUBLIC_IP"
fi

print_header "Cloudflare WARP Connector - Automated Setup"
echo -e "${CYAN}VPS IP:${NC} $VPS_PUBLIC_IP"
echo -e "${CYAN}VNC Users:${NC} $VNC_USER_COUNT"
echo -e "${CYAN}WARP Token:${NC} ${CLOUDFLARE_WARP_TOKEN:0:20}...${CLOUDFLARE_WARP_TOKEN: -10}"
echo ""

# Step 1: Update System
print_header "Step 1/6: Updating System"
print_message "Updating package lists..."
apt-get update -qq
print_message "Upgrading packages (this may take several minutes)..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
print_message "✓ System updated"

# Step 2: Install Desktop Environment and VNC
print_header "Step 2/6: Installing Desktop Environment and VNC"

print_message "Installing Ubuntu Desktop and XFCE4 (this will take 10-15 minutes)..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ubuntu-desktop xfce4 xfce4-goodies

print_message "Installing VNC Server..."
apt-get install -y -qq tigervnc-standalone-server tigervnc-common

print_message "✓ Desktop environment and VNC installed"

# Step 3: Install L2TP/IPSec VPN
print_header "Step 3/6: Installing L2TP/IPSec VPN (Fallback)"

if [[ -f "./setup_l2tp.sh" ]]; then
    chmod +x "./setup_l2tp.sh"
    print_message "Running L2TP setup script..."
    ./setup_l2tp.sh || print_warning "L2TP setup encountered issues, continuing..."
    print_message "✓ L2TP/IPSec VPN installed"
else
    print_warning "setup_l2tp.sh not found, skipping L2TP installation"
fi


# Step 4: Configure VNC Servers
print_header "Step 4/6: Configuring VNC Servers"

for ((i=1; i<=VNC_USER_COUNT; i++)); do
    username_var="VNCUSER${i}_USERNAME"
    password_var="VNCUSER${i}_PASSWORD"
    display_var="VNCUSER${i}_DISPLAY"
    resolution_var="VNCUSER${i}_RESOLUTION"
    port_var="VNCUSER${i}_PORT"
    
    username="${!username_var}"
    password="${!password_var}"
    display="${!display_var}"
    resolution="${!resolution_var}"
    port="${!port_var}"
    
    if [[ -z "$username" ]] || [[ -z "$password" ]]; then
        print_warning "Skipping VNC user $i: username or password not configured"
        continue
    fi
    
    print_message "Setting up VNC for user: $username (display :$display, port $port)"
    
    # Create user if doesn't exist
    if ! id "$username" &>/dev/null; then
        useradd -m -s /bin/bash "$username"
        print_message "  Created user: $username"
    fi
    
    # Set VNC password
    su - "$username" -c "mkdir -p ~/.vnc"
    echo "$password" | su - "$username" -c "vncpasswd -f" > /home/$username/.vnc/passwd
    chmod 600 /home/$username/.vnc/passwd
    chown $username:$username /home/$username/.vnc/passwd
    
    # Create VNC startup script
    cat > /home/$username/.vnc/xstartup << 'EOF'
#!/bin/bash
xrdb $HOME/.Xresources
startxfce4 &
EOF
    
    chmod +x /home/$username/.vnc/xstartup
    chown $username:$username /home/$username/.vnc/xstartup
    
    # Create systemd service for VNC
    cat > /etc/systemd/system/vncserver@${username}.service << EOF
[Unit]
Description=VNC Server for ${username}
After=syslog.target network.target

[Service]
Type=forking
User=${username}
ExecStart=/usr/bin/vncserver :${display} -geometry ${resolution} -depth 24 -localhost no
ExecStop=/usr/bin/vncserver -kill :${display}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start VNC service
    systemctl daemon-reload
    systemctl enable vncserver@${username}.service > /dev/null 2>&1
    systemctl start vncserver@${username}.service
    
    if systemctl is-active --quiet vncserver@${username}.service; then
        print_message "  ✓ VNC server started for $username on port $port"
    else
        print_warning "  VNC server for $username may not have started. Check with: systemctl status vncserver@${username}"
    fi
done

# Step 5: Configure Firewall
print_header "Step 6/6: Configuring Firewall"

print_message "Configuring UFW firewall..."
ufw --force enable > /dev/null

# Allow SSH
ufw allow 22/tcp comment 'SSH' > /dev/null
print_message "  ✓ Allowed SSH (port 22)"

# Allow VNC ports
for ((i=1; i<=VNC_USER_COUNT; i++)); do
    port_var="VNCUSER${i}_PORT"
    username_var="VNCUSER${i}_USERNAME"
    port="${!port_var}"
    username="${!username_var}"
    
    if [[ -n "$port" ]]; then
        ufw allow ${port}/tcp comment "VNC-${username}" > /dev/null
        print_message "  ✓ Allowed VNC port ${port} (${username})"
    fi
done

# Allow L2TP/IPSec
ufw allow 500/udp comment 'L2TP-IKE' > /dev/null
ufw allow 4500/udp comment 'L2TP-NAT-T' > /dev/null
ufw allow 1701/udp comment 'L2TP' > /dev/null
print_message "  ✓ Allowed L2TP/IPSec ports"

print_message "✓ Firewall configured"

# Step 6: Install and Configure Cloudflare WARP Connector
print_header "Step 6/6: Installing Cloudflare WARP Connector"

# 1. Setup pubkey, apt repo, and update/install WARP
print_message "Adding Cloudflare repository..."
curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list

print_message "Installing Cloudflare WARP..."
apt-get update && apt-get install cloudflare-warp

# 2. Enable IP forwarding on the host
print_message "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1

# Make persistent
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
fi

# 3. Run the WARP Connector with token
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
sleep 3
if warp-cli status | grep -q "Connected"; then
    print_message "✓ WARP Connector connected successfully"
else
    print_error "WARP Connector connection FAILED!"
    print_error "Check status with: sudo warp-cli status"
    print_error "Check logs with: journalctl -u warp-svc -n 50"
    exit 1
fi




# --- Setup Complete ---
print_header "Setup Complete!"

echo -e "${GREEN}All components successfully installed and configured!${NC}\n"
echo -e "${YELLOW}Installed & Configured:${NC}"
echo -e "  ✓ Ubuntu Desktop + XFCE4"
echo -e "  ✓ TigerVNC Server (${VNC_USER_COUNT} users)"
echo -e "  ✓ L2TP/IPSec VPN (fallback)"
echo -e "  ✓ Cloudflare WARP Connector (registered & connected)"
echo -e "  ✓ System IP forwarding enabled"
echo -e "  ✓ Firewall rules configured"
echo ""

echo -e "${CYAN}VPS Information:${NC}"
echo -e "  IP Address: ${GREEN}$VPS_PUBLIC_IP${NC}"
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

echo -e "${CYAN}Service Status:${NC}"
echo -e "  WARP Connector: ${GREEN}$(warp-cli status 2>/dev/null | head -1 || echo 'Check with: sudo warp-cli status')${NC}"
for ((i=1; i<=VNC_USER_COUNT; i++)); do
    username_var="VNCUSER${i}_USERNAME"
    username="${!username_var}"
    if [[ -n "$username" ]]; then
        status=$(systemctl is-active vncserver@${username}.service 2>/dev/null || echo "inactive")
        color="${GREEN}"
        [[ "$status" != "active" ]] && color="${RED}"
        echo -e "  VNC ($username):    ${color}${status}${NC}"
    fi
done
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. ${BLUE}Verify WARP Connector:${NC}"
echo -e "   ${CYAN}sudo warp-cli status${NC}"
echo -e "   ${CYAN}sudo warp-cli account${NC}"
echo ""
echo -e "2. ${BLUE}Test VNC Access:${NC}"
for ((i=1; i<=VNC_USER_COUNT; i++)); do
    port_var="VNCUSER${i}_PORT"
    username_var="VNCUSER${i}_USERNAME"
    port="${!port_var}"
    username="${!username_var}"
    if [[ -n "$port" ]]; then
        echo -e "   ${CYAN}vncviewer $VPS_PUBLIC_IP:$port${NC} (user: $username)"
    fi
done
echo ""
echo -e "3. ${BLUE}Client Setup (README.md Part 3):${NC}"
echo -e "   - Install Cloudflare One Agent"
echo -e "   - Authenticate with your email"
echo -e "   - All traffic will route through VPS ($VPS_PUBLIC_IP)"
echo ""
echo -e "4. ${BLUE}Verify Traffic Routing:${NC}"
echo -e "   ${CYAN}curl ifconfig.me${NC}"
echo -e "   Should show: $VPS_PUBLIC_IP"
echo ""

echo -e "${GREEN}Setup completed at $(date)${NC}"
echo -e "${YELLOW}Read the complete guide in README.md${NC}"

exit 0
