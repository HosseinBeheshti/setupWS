#!/bin/bash

# Master Setup Script for Secure Remote Desktop Gateway
# This script orchestrates all setup scripts in the correct order
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
REQUIRED_SCRIPTS=("setup_vnc.sh" "setup_virtual_router.sh" "setup_l2tp.sh" "setup_ovpn.sh")
for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [[ ! -f "./$script" ]]; then
        print_error "Required script not found: $script"
        exit 1
    fi
    # Make sure scripts are executable
    chmod +x "./$script"
done

# --- Main Execution ---
print_header "Starting Secure Remote Desktop Gateway Setup"

# Step 0: Setup ZTNA Infrastructure (Cloudflare, Docker, WireGuard)
print_header "Step 0/5: Setting up ZTNA Infrastructure"

print_message "Installing required packages..."
apt-get update
apt-get install -y \
    ca-certificates \
    gnupg \
    lsb-release \
    qrencode \
    sqlite3 \
    uuid-runtime \
    curl \
    wget \
    iptables \
    net-tools \
    wireguard-tools

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
mkdir -p /var/lib/ztna/clients
mkdir -p /var/lib/ztna/backups
mkdir -p /etc/wireguard
chmod 700 /var/lib/ztna
chmod 700 /etc/cloudflare
chmod 700 /etc/wireguard
print_message "✓ Directories created"

# Initialize SQLite database
print_message "Initializing SQLite database..."
DB_PATH="${DB_PATH:-/var/lib/ztna/users.db}"

if [[ ! -f "$DB_PATH" ]]; then
    sqlite3 "$DB_PATH" << 'EOSQL'
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    device_id TEXT NOT NULL,
    public_key TEXT NOT NULL,
    peer_ip TEXT UNIQUE NOT NULL,
    created_at TIMESTAMP NOT NULL,
    last_seen TIMESTAMP
);

CREATE INDEX idx_username ON users(username);
CREATE INDEX idx_device_id ON users(device_id);
CREATE INDEX idx_peer_ip ON users(peer_ip);
EOSQL
    print_message "✓ Database initialized: $DB_PATH"
else
    print_message "✓ Database already exists: $DB_PATH"
fi

# Generate WireGuard server keys if not exist
print_message "Configuring WireGuard server..."
if [[ ! -f "/etc/wireguard/server_private.key" ]]; then
    wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
    chmod 600 /etc/wireguard/server_private.key
    print_message "✓ WireGuard server keys generated"
else
    print_message "✓ WireGuard keys already exist"
fi

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
ufw allow 51820/udp comment 'WireGuard'
print_message "✓ Firewall configured"

# Start Docker services
print_message "Starting ZTNA Docker services..."
if [[ -f "./docker-compose-ztna.yml" ]]; then
    # Check if CLOUDFLARE_TUNNEL_TOKEN is set
    if [[ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]]; then
        print_warning "CLOUDFLARE_TUNNEL_TOKEN not set in workstation.env"
        print_warning "Cloudflare tunnel will not start. Set token and run:"
        print_warning "  docker compose -f docker-compose-ztna.yml up -d cloudflared"
    fi
    
    # Export environment variables for docker compose
    export CLOUDFLARE_TUNNEL_TOKEN
    export WG_SERVER_PUBLIC_IP
    export WG_PORT
    export WG_SUBNET
    export WG_DNS
    
    # Use 'docker compose' (v2) instead of 'docker-compose' (v1)
    docker compose -f docker-compose-ztna.yml up -d
    print_message "✓ Docker services started"
    
    # Wait for containers to be ready
    sleep 5
    
    # Check container status
    if docker ps | grep -q wireguard; then
        print_message "✓ WireGuard container running"
    else
        print_warning "WireGuard container not running, check logs: docker logs wireguard"
    fi
    
    if docker ps | grep -q cloudflared; then
        print_message "✓ Cloudflare tunnel container running"
        
        # Verify tunnel is connected by checking logs
        sleep 3
        if docker logs cloudflared 2>&1 | grep -q "Registered tunnel connection"; then
            print_message "✓ Cloudflare tunnel connected successfully"
        else
            print_warning "Cloudflare tunnel may not be connected. Check logs: docker logs cloudflared"
        fi
    else
        print_warning "Cloudflare tunnel not running, check logs: docker logs cloudflared"
    fi
else
    print_warning "docker-compose-ztna.yml not found, skipping Docker deployment"
fi

print_message "✓ ZTNA Infrastructure setup completed"

# Step 1: Setup VNC Server with Users
print_header "Step 1/5: Setting up VNC Server and Users"
./setup_vnc.sh
if [[ $? -ne 0 ]]; then
    print_error "VNC setup failed!"
    exit 1
fi
print_message "✓ VNC setup completed successfully"

# Step 2: Setup Virtual Router
print_header "Step 2/5: Setting up Virtual Router"
./setup_virtual_router.sh
if [[ $? -ne 0 ]]; then
    print_error "Virtual Router setup failed!"
    exit 1
fi
print_message "✓ Virtual Router setup completed successfully"

# Step 3: Setup L2TP VPN (if configured)
if [[ " $VPN_LIST " =~ " l2tp " ]]; then
    print_header "Step 3/5: Setting up L2TP VPN"
    ./setup_l2tp.sh
    if [[ $? -ne 0 ]]; then
        print_error "L2TP VPN setup failed!"
        exit 1
    fi
    print_message "✓ L2TP VPN setup completed successfully"
else
    print_warning "Step 3/5: L2TP VPN not in VPN_LIST, skipping..."
fi

# Step 4: Setup OpenVPN (if configured)
if [[ " $VPN_LIST " =~ " ovpn " ]]; then
    print_header "Step 4/5: Setting up OpenVPN"
    ./setup_ovpn.sh
    if [[ $? -ne 0 ]]; then
        print_error "OpenVPN setup failed!"
        exit 1
    fi
    print_message "✓ OpenVPN setup completed successfully"
else
    print_warning "Step 4/5: OpenVPN not in VPN_LIST, skipping..."
fi

# Step 5: Setup Backup Automation
print_header "Step 5/5: Setting up Automated Backups"

if [[ -f "./backup_ztna.sh" ]]; then
    chmod +x ./backup_ztna.sh
    
    # Setup cron job for daily backups at 2 AM
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CRON_JOB="0 2 * * * $SCRIPT_DIR/backup_ztna.sh >> /var/log/ztna_backup.log 2>&1"
    
    if ! crontab -l 2>/dev/null | grep -q "backup_ztna.sh"; then
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        print_message "✓ Backup cron job installed (runs daily at 2 AM)"
    else
        print_message "✓ Backup cron job already exists"
    fi
    
    # Run initial backup
    print_message "Running initial backup..."
    ./backup_ztna.sh
    print_message "✓ Initial backup completed"
else
    print_warning "backup_ztna.sh not found, skipping backup setup"
fi

print_message "✓ Backup automation setup completed"

# --- Final Summary ---
print_header "Setup Complete!"
echo -e "${GREEN}All components have been successfully installed and configured!${NC}\n"

echo -e "${YELLOW}Summary:${NC}"
echo -e "  ✓ ZTNA Infrastructure (Cloudflare Tunnel, WireGuard)"
echo -e "  ✓ VNC Server with users"
echo -e "  ✓ Virtual Router for VPN traffic"
if [[ " $VPN_LIST " =~ " l2tp " ]]; then
    echo -e "  ✓ L2TP VPN configured"
fi
if [[ " $VPN_LIST " =~ " ovpn " ]]; then
    echo -e "  ✓ OpenVPN configured"
fi
echo -e "  ✓ Automated backups scheduled"
echo ""

# Display ZTNA information
echo -e "${YELLOW}ZTNA Services:${NC}"
echo -e "-----------------------------------------------------"
echo -e "  ${GREEN}WireGuard:${NC}         Port ${WG_PORT:-51820}/udp"
echo -e "  ${GREEN}Cloudflare Tunnel:${NC} Dynamic port (access via CF Access)"
echo -e "  ${GREEN}Database:${NC}          $DB_PATH"
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
echo -e "1. ${BLUE}Admin Access:${NC}"
echo -e "   - Install WARP client on your device"
echo -e "   - Enroll with Cloudflare Zero Trust"
echo -e "   - Access VNC via: https://vnc-<username>.${CLOUDFLARE_DOMAIN:-yourdomain.com}"
echo -e "   - Access SSH via: cloudflared access ssh --hostname ssh.${CLOUDFLARE_DOMAIN:-yourdomain.com}"
echo ""
echo -e "2. ${BLUE}User Provisioning:${NC}"
echo -e "   - Add WireGuard users: ${GREEN}sudo ./add_wg_peer.sh <username>${NC}"
echo -e "   - Manage users: ${GREEN}sudo ./query_users.sh${NC}"
echo ""
echo -e "3. ${BLUE}VPN Management (Admins):${NC}"
echo -e "   - Run VPN: ${GREEN}sudo ./run_vpn.sh${NC}"
echo -e "   - Check services: systemctl status vncserver-<username>@<display>.service"
echo ""
echo -e "4. ${BLUE}Monitoring:${NC}"
echo -e "   - Docker status: docker ps"
echo -e "   - WireGuard peers: sudo wg show"
echo -e "   - Logs: docker logs wireguard | cloudflared"
echo ""
echo -e "5. ${BLUE}Backups:${NC}"
echo -e "   - Automated daily at 2 AM to: /var/lib/ztna/backups/"
echo -e "   - Manual backup: ${GREEN}sudo ./backup_ztna.sh${NC}"
echo ""

# --- Cleanup: Remove workstation.env from root ---
if [[ -f "/root/workstation.env" ]]; then
    print_message "Removing workstation.env from root directory for security..."
    rm -f /root/workstation.env
    print_message "✓ Configuration file cleaned up"
fi

echo -e "${GREEN}Setup completed at $(date)${NC}"

exit 0
