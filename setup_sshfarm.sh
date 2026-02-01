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

if [[ -z "$SSH_FARM_PASSWORD" ]]; then
    print_error "SSH_FARM_PASSWORD is not set in workstation.env"
    exit 1
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
version: '3.8'

services:
EOF

# Add each SSH server container
for i in "${!PORTS[@]}"; do
    PORT="${PORTS[$i]}"
    USER_NUM=$((i + 1))
    USERNAME="sshfarm_user${USER_NUM}"
    CONTAINER_NAME="sshfarm_${PORT}"
    
    print_message "  Configuring $USERNAME on port $PORT..."
    
    cat >> "$COMPOSE_FILE" <<EOF

  ${CONTAINER_NAME}:
    image: linuxserver/openssh-server:latest
    container_name: ${CONTAINER_NAME}
    hostname: ${CONTAINER_NAME}
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
      - PUBLIC_KEY_FILE=/config/ssh_host_keys/authorized_keys
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
    command: >
      sh -c "
        apk add --no-cache cmake gcc g++ make linux-headers git &&
        if [ ! -f /usr/local/bin/badvpn-udpgw ]; then
          cd /tmp &&
          git clone https://github.com/ambrop72/badvpn.git &&
          cd badvpn &&
          mkdir build && cd build &&
          cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 &&
          make install &&
          rm -rf /tmp/badvpn
        fi &&
        /usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --loglevel info &
        /init
      "

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
print_message "Waiting for containers to initialize..."
sleep 10

# Check container status
print_message "Checking container status..."
RUNNING_COUNT=$(docker compose -f "$COMPOSE_FILE" ps --format json | grep -c "running" || echo "0")

if [[ "$RUNNING_COUNT" -eq "$NUM_SERVERS" ]]; then
    print_message "✓ All $NUM_SERVERS SSH servers are running"
else
    print_warning "$RUNNING_COUNT/$NUM_SERVERS servers are running"
fi

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
    echo -e "    User:     ${GREEN}$USERNAME${NC}"
    echo -e "    Port:     ${GREEN}$PORT${NC}"
    echo -e "    Command:  ${YELLOW}ssh $USERNAME@$VPS_PUBLIC_IP -p $PORT${NC}"
    echo -e "    UDPGW:    ${GREEN}127.0.0.1:7300${NC}"
    echo ""
done

echo -e "-----------------------------------------------------"
echo -e "${YELLOW}Management Commands:${NC}"
echo -e "  Start:   ${CYAN}docker compose -f $COMPOSE_FILE up -d${NC}"
echo -e "  Stop:    ${CYAN}docker compose -f $COMPOSE_FILE down${NC}"
echo -e "  Restart: ${CYAN}docker compose -f $COMPOSE_FILE restart${NC}"
echo -e "  Logs:    ${CYAN}docker compose -f $COMPOSE_FILE logs -f${NC}"
echo -e "  Status:  ${CYAN}docker compose -f $COMPOSE_FILE ps${NC}"
echo -e ""

# Update firewall to allow SSH farm ports
if [[ -n "$FIREWALL_ALLOWED_PORTS" ]]; then
    print_message "Updating firewall rules for SSH farm ports..."
    for PORT in "${PORTS[@]}"; do
        ufw allow "$PORT/tcp" comment "SSH Farm" 2>/dev/null || true
    done
    print_message "✓ Firewall rules updated"
fi

print_message "SSH Farm setup completed at $(date)"

exit 0
