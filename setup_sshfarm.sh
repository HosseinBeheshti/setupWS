#!/bin/bash

# ============================================================
# SSH Farm Setup Script
# ============================================================
# Creates multiple SSH servers using linuxserver/openssh-server
# Each server gets a unique port but shares the same password
# Includes badVPN-udpgw for UDP over TCP tunneling
# ============================================================

set -e  # Exit on any error

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

print_header "SSH Farm Setup with badVPN-udpgw"

# Validate configuration
if [[ -z "$SSH_FARM_PORTS" ]]; then
    print_error "SSH_FARM_PORTS is not set in workstation.env"
    exit 1
fi

# Generate password if not set or is placeholder
if [[ -z "$SSH_FARM_PASSWORD" ]] || [[ "$SSH_FARM_PASSWORD" == "<auto_generated_password>" ]]; then
    print_message "Generating random password for SSH farm..."
    SSH_FARM_PASSWORD=$(openssl rand -base64 24 | tr -d "/=+" | cut -c1-20)
    
    # Update workstation.env with generated password
    sed -i "s|SSH_FARM_PASSWORD=\".*\"|SSH_FARM_PASSWORD=\"$SSH_FARM_PASSWORD\"|g" "$ENV_FILE"
    print_message "✓ Password generated and saved to workstation.env"
fi

# Parse ports (remove trailing comma if exists)
SSH_FARM_PORTS="${SSH_FARM_PORTS%,}"
IFS=',' read -ra PORTS <<< "$SSH_FARM_PORTS"
NUM_SERVERS=${#PORTS[@]}

print_message "Creating $NUM_SERVERS SSH servers on ports: ${PORTS[*]}"
print_message "Using shared password for all servers"

# Create docker-compose file
COMPOSE_FILE="./docker-compose-sshfarm.yml"
print_message "Generating Docker Compose configuration..."

cat > "$COMPOSE_FILE" <<'EOF'
services:
EOF

# Add each SSH server container
for i in "${!PORTS[@]}"; do
    PORT="${PORTS[$i]}"
    USER_NUM=$((i + 1))
    USERNAME="sshfarm_user${USER_NUM}"
    CONTAINER_NAME="sshfarm_${PORT}"
    
    print_message "  Configuring $USERNAME on port $PORT..."
    
    # Create custom init script for badVPN
    mkdir -p "./sshfarm_data/${CONTAINER_NAME}/custom-cont-init.d"
    cat > "./sshfarm_data/${CONTAINER_NAME}/custom-cont-init.d/install-badvpn.sh" <<'INITSCRIPT'
#!/usr/bin/with-contenv bash

echo "Installing badVPN-udpgw..."

# Install dependencies
apk add --no-cache cmake gcc g++ make linux-headers git

# Check if already installed
if [ ! -f /usr/local/bin/badvpn-udpgw ]; then
    cd /tmp
    git clone https://github.com/ambrop72/badvpn.git
    cd badvpn
    mkdir build && cd build
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
    make install
    cd /
    rm -rf /tmp/badvpn
    echo "badVPN-udpgw installed successfully"
else
    echo "badVPN-udpgw already installed"
fi
INITSCRIPT
    
    chmod +x "./sshfarm_data/${CONTAINER_NAME}/custom-cont-init.d/install-badvpn.sh"
    
    # Create service script for badVPN
    mkdir -p "./sshfarm_data/${CONTAINER_NAME}/custom-services.d"
    cat > "./sshfarm_data/${CONTAINER_NAME}/custom-services.d/badvpn.sh" <<'SERVICESCRIPT'
#!/usr/bin/with-contenv bash

echo "Starting badVPN-udpgw service..."
exec /usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --loglevel info
SERVICESCRIPT
    
    chmod +x "./sshfarm_data/${CONTAINER_NAME}/custom-services.d/badvpn.sh"
    
    cat >> "$COMPOSE_FILE" <<EOF

  ${CONTAINER_NAME}:
    image: linuxserver/openssh-server:latest
    container_name: ${CONTAINER_NAME}
    hostname: ${CONTAINER_NAME}
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
      - SUDO_ACCESS=false
      - PASSWORD_ACCESS=true
      - USER_PASSWORD=${SSH_FARM_PASSWORD}
      - USER_NAME=${USERNAME}
    volumes:
      - ./sshfarm_data/${CONTAINER_NAME}:/config
    ports:
      - "${PORT}:2222"
    restart: unless-stopped
    networks:
      - sshfarm_network
    cap_add:
      - NET_ADMIN

EOF
done

# Add network configuration
cat >> "$COMPOSE_FILE" <<'EOF'

networks:
  sshfarm_network:
    driver: bridge
EOF

print_message "✓ Docker Compose configuration generated"

# Create data directories
print_message "Creating data directories..."
mkdir -p ./sshfarm_data
for i in "${!PORTS[@]}"; do
    PORT="${PORTS[$i]}"
    CONTAINER_NAME="sshfarm_${PORT}"
    mkdir -p "./sshfarm_data/${CONTAINER_NAME}"
done
print_message "✓ Data directories created"

# Stop existing containers if running
print_message "Stopping existing SSH farm containers..."
docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
print_message "✓ Existing containers stopped"

# Start the SSH farm
print_message "Starting SSH farm containers..."
docker compose -f "$COMPOSE_FILE" up -d

# Wait for containers to be ready
print_message "Waiting for containers to initialize (this may take 2-3 minutes for first-time setup)..."
sleep 15

# Monitor container status
print_message "Monitoring container startup..."
for attempt in {1..12}; do
    RUNNING_COUNT=$(docker compose -f "$COMPOSE_FILE" ps --format json 2>/dev/null | jq -r '.State' 2>/dev/null | grep -c "running" || echo "0")
    TOTAL_CONTAINERS=$NUM_SERVERS
    
    if [[ "$RUNNING_COUNT" -eq "$TOTAL_CONTAINERS" ]]; then
        print_message "✓ All $NUM_SERVERS SSH servers are running"
        break
    else
        if [[ $attempt -lt 12 ]]; then
            echo -e "  ${YELLOW}[$attempt/12]${NC} $RUNNING_COUNT/$TOTAL_CONTAINERS containers running, waiting..."
            sleep 10
        else
            print_warning "$RUNNING_COUNT/$TOTAL_CONTAINERS servers are running after 2 minutes"
            echo -e "  ${YELLOW}Note:${NC} badVPN compilation may still be in progress. Check logs if needed."
        fi
    fi
done

# Display connection information
print_header "SSH Farm Setup Complete!"
echo -e "${GREEN}SSH Farm Information:${NC}"
echo -e "-----------------------------------------------------"
echo -e "  ${GREEN}Total Servers:${NC}   $NUM_SERVERS"
echo -e "  ${GREEN}Shared Password:${NC} $SSH_FARM_PASSWORD"
echo -e "  ${GREEN}badVPN-udpgw:${NC}    Enabled on 127.0.0.1:7300 (all servers)"
echo -e ""
echo -e "${CYAN}Connection Details:${NC}"

for i in "${!PORTS[@]}"; do
    PORT="${PORTS[$i]}"
    USER_NUM=$((i + 1))
    USERNAME="sshfarm_user${USER_NUM}"
    echo -e "  ${BLUE}Server $USER_NUM:${NC}"
    echo -e "    User:       ${GREEN}$USERNAME${NC}"
    echo -e "    Port:       ${GREEN}$PORT${NC}"
    echo -e "    Connect:    ${YELLOW}ssh -p $PORT $USERNAME@$VPS_PUBLIC_IP${NC}"
    echo -e "    Tunnel:     ${YELLOW}ssh -p $PORT -D 1080 $USERNAME@$VPS_PUBLIC_IP${NC}"
    echo -e "    UDPGW:      ${GREEN}127.0.0.1:7300${NC}"
    echo ""
done

echo -e "-----------------------------------------------------"
echo -e "${YELLOW}SSH URLs (for easy import):${NC}"
echo -e ""
for i in "${!PORTS[@]}"; do
    PORT="${PORTS[$i]}"
    USER_NUM=$((i + 1))
    USERNAME="sshfarm_user${USER_NUM}"
    REMARK="SSHFarm${USER_NUM}_Port${PORT}"
    echo -e "${CYAN}ssh://${USERNAME}:${SSH_FARM_PASSWORD}@${VPS_PUBLIC_IP}:${PORT}#${REMARK}${NC}"
done
echo -e ""
echo -e "-----------------------------------------------------"
echo -e "${YELLOW}Management Commands:${NC}"
echo -e "  Start:   ${CYAN}docker compose -f $COMPOSE_FILE up -d${NC}"
echo -e "  Stop:    ${CYAN}docker compose -f $COMPOSE_FILE down${NC}"
echo -e "  Restart: ${CYAN}docker compose -f $COMPOSE_FILE restart${NC}"
echo -e "  Logs:    ${CYAN}docker compose -f $COMPOSE_FILE logs -f${NC}"
echo -e "  Status:  ${CYAN}docker compose -f $COMPOSE_FILE ps${NC}"
echo -e ""

# Update firewall to allow SSH farm ports
print_message "Configuring firewall rules for SSH farm ports..."
for PORT in "${PORTS[@]}"; do
    ufw allow "$PORT/tcp" comment "SSH Farm" 2>/dev/null || true
done
print_message "✓ Firewall rules configured for ports: ${PORTS[*]}"

# Verify setup
print_header "Verifying Setup"

# Check if ports are listening
print_message "Checking if SSH ports are accessible..."
sleep 3
for PORT in "${PORTS[@]}"; do
    if ss -tln | grep -q ":$PORT "; then
        echo -e "  ${GREEN}✓${NC} Port $PORT is listening"
    else
        echo -e "  ${RED}✗${NC} Port $PORT is NOT listening"
    fi
done

# Test local connection
print_message ""
print_message "Testing local connection to first server..."
FIRST_PORT="${PORTS[0]}"
FIRST_USER="sshfarm_user1"

if timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -p "$FIRST_PORT" "$FIRST_USER@localhost" exit 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Local SSH connection successful"
else
    echo -e "  ${YELLOW}⚠${NC} Local connection test failed (may need more initialization time)"
fi

print_message ""
print_message "SSH Farm setup completed at $(date)"
print_message ""
echo -e "${YELLOW}Troubleshooting:${NC}"
echo -e "  If connection fails from external:"
echo -e "  1. Check containers: ${CYAN}docker compose -f $COMPOSE_FILE ps${NC}"
echo -e "  2. Check ports: ${CYAN}sudo ss -tlnp | grep -E ':(${PORTS[0]}|${PORTS[1]})'${NC}"
echo -e "  3. Check firewall: ${CYAN}sudo ufw status${NC}"
echo -e "  4. View logs: ${CYAN}docker compose -f $COMPOSE_FILE logs -f${NC}"
echo -e "  5. Test locally: ${CYAN}ssh -p $FIRST_PORT $FIRST_USER@localhost${NC}"

exit 0
