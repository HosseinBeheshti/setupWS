#!/bin/bash
# ============================================================
# Xray User Management Script
# ============================================================
# This script manages Xray users (add, remove, list, show QR)
# ============================================================

set -e  # Exit on error

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workstation.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Xray configuration file
XRAY_CONFIG_DIR="/etc/xray"
XRAY_CONFIG_FILE="$XRAY_CONFIG_DIR/config.json"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (use sudo)"
    exit 1
fi

# Check if Xray config exists
if [ ! -f "$XRAY_CONFIG_FILE" ]; then
    print_error "Xray configuration file not found: $XRAY_CONFIG_FILE"
    print_error "Please run setup_xray.sh first"
    exit 1
fi

# Install jq for JSON parsing if not present
if ! command -v jq &> /dev/null; then
    print_info "Installing jq for JSON parsing..."
    apt-get update -qq
    apt-get install -y jq
fi

# Install qrencode for QR code generation if not present
if ! command -v qrencode &> /dev/null; then
    print_info "Installing qrencode for QR code generation..."
    apt-get update -qq
    apt-get install -y qrencode
fi

# ============================================================
# Helper Functions
# ============================================================

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

get_vless_url() {
    local uuid=$1
    local email=$2
    local flow=$XRAY_FLOW
    local security=$XRAY_SECURITY
    local network=$XRAY_NETWORK
    local port=$XRAY_PORT
    
    # Get server IP
    local server_ip=$(hostname -I | awk '{print $1}')
    if [ -z "$server_ip" ]; then
        server_ip="YOUR_SERVER_IP"
    fi
    
    # Build VLESS URL based on security type
    local url="vless://${uuid}@${server_ip}:${port}?"
    
    if [ "$security" = "reality" ]; then
        # Reality protocol parameters
        local sni="${XRAY_REALITY_SERVER_NAMES%%,*}"  # Get first server name
        local public_key="$XRAY_REALITY_PUBLIC_KEY"
        local short_id="$XRAY_REALITY_SHORT_IDS"
        
        url="${url}security=reality"
        url="${url}&sni=${sni}"
        url="${url}&fp=chrome"
        url="${url}&pbk=${public_key}"
        url="${url}&sid=${short_id}"
        url="${url}&type=${network}"
        url="${url}&flow=${flow}"
    else
        # TLS protocol parameters
        url="${url}security=${security}"
        url="${url}&sni=${XRAY_PANEL_DOMAIN}"
        url="${url}&type=${network}"
        if [ -n "$flow" ]; then
            url="${url}&flow=${flow}"
        fi
    fi
    
    url="${url}#${email}"
    echo "$url"
}

restart_xray() {
    print_info "Restarting Xray container..."
    docker restart xray-server
    sleep 2
    print_success "Xray container restarted"
}

# ============================================================
# Add User Function
# ============================================================
add_user() {
    local email=$1
    
    if [ -z "$email" ]; then
        print_error "Email/username is required"
        echo "Usage: $0 add <email/username>"
        exit 1
    fi
    
    # Check if user already exists
    if jq -e ".inbounds[0].settings.clients[] | select(.email==\"$email\")" "$XRAY_CONFIG_FILE" > /dev/null 2>&1; then
        print_error "User '$email' already exists"
        exit 1
    fi
    
    # Generate UUID for new user
    local new_uuid=$(generate_uuid)
    
    print_info "Adding new user: $email"
    print_info "Generated UUID: $new_uuid"
    
    # Add user to config using jq
    local temp_file=$(mktemp)
    jq ".inbounds[0].settings.clients += [{
        \"id\": \"$new_uuid\",
        \"flow\": \"$XRAY_FLOW\",
        \"level\": 0,
        \"email\": \"$email\"
    }]" "$XRAY_CONFIG_FILE" > "$temp_file"
    
    # Backup original config
    cp "$XRAY_CONFIG_FILE" "${XRAY_CONFIG_FILE}.backup"
    
    # Replace config with updated version
    mv "$temp_file" "$XRAY_CONFIG_FILE"
    
    print_success "User '$email' added successfully"
    
    # Restart Xray
    restart_xray
    
    # Display connection info
    local server_ip=$(hostname -I | awk '{print $1}')
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}User Connection Information${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${BLUE}Email:${NC} $email"
    echo -e "${BLUE}UUID:${NC} $new_uuid"
    echo -e "${BLUE}Server IP:${NC} $server_ip"
    echo -e "${BLUE}Port:${NC} $XRAY_PORT"
    echo -e "${BLUE}Network:${NC} $XRAY_NETWORK"
    echo -e "${BLUE}Security:${NC} $XRAY_SECURITY"
    echo -e "${BLUE}Flow:${NC} $XRAY_FLOW"
    
    if [ "$XRAY_SECURITY" = "reality" ]; then
        echo -e "${BLUE}SNI:${NC} ${XRAY_REALITY_SERVER_NAMES%%,*}"
        echo -e "${BLUE}Fingerprint:${NC} chrome"
        echo -e "${BLUE}Public Key:${NC} $XRAY_REALITY_PUBLIC_KEY"
        echo -e "${BLUE}Short ID:${NC} $XRAY_REALITY_SHORT_IDS"
    fi
    echo ""
    
    # Generate and display VLESS URL
    local vless_url=$(get_vless_url "$new_uuid" "$email")
    echo -e "${GREEN}VLESS Connection String:${NC}"
    echo "$vless_url"
    echo ""
    
    # Generate and display QR code
    echo -e "${GREEN}QR Code:${NC}"
    qrencode -t ANSIUTF8 "$vless_url"
    echo ""
    echo -e "${YELLOW}Scan this QR code with v2rayNG or compatible client${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

# ============================================================
# Remove User Function
# ============================================================
remove_user() {
    local email=$1
    
    if [ -z "$email" ]; then
        print_error "Email/username is required"
        echo "Usage: $0 remove <email/username>"
        exit 1
    fi
    
    # Check if user exists
    if ! jq -e ".inbounds[0].settings.clients[] | select(.email==\"$email\")" "$XRAY_CONFIG_FILE" > /dev/null 2>&1; then
        print_error "User '$email' not found"
        exit 1
    fi
    
    print_info "Removing user: $email"
    
    # Remove user from config using jq
    local temp_file=$(mktemp)
    jq ".inbounds[0].settings.clients |= map(select(.email != \"$email\"))" "$XRAY_CONFIG_FILE" > "$temp_file"
    
    # Backup original config
    cp "$XRAY_CONFIG_FILE" "${XRAY_CONFIG_FILE}.backup"
    
    # Replace config with updated version
    mv "$temp_file" "$XRAY_CONFIG_FILE"
    
    print_success "User '$email' removed successfully"
    
    # Restart Xray
    restart_xray
}

# ============================================================
# List Users Function
# ============================================================
list_users() {
    print_info "Current Xray Users:"
    echo ""
    
    local count=0
    while IFS= read -r line; do
        local email=$(echo "$line" | jq -r '.email')
        local uuid=$(echo "$line" | jq -r '.id')
        local flow=$(echo "$line" | jq -r '.flow')
        
        count=$((count + 1))
        echo -e "${CYAN}User #$count${NC}"
        echo -e "${BLUE}  Email:${NC} $email"
        echo -e "${BLUE}  UUID:${NC} $uuid"
        echo -e "${BLUE}  Flow:${NC} $flow"
        echo ""
    done < <(jq -c '.inbounds[0].settings.clients[]' "$XRAY_CONFIG_FILE")
    
    if [ $count -eq 0 ]; then
        print_warning "No users configured"
    else
        print_success "Total users: $count"
    fi
}

# ============================================================
# Show User QR Code Function
# ============================================================
show_qr() {
    local email=$1
    
    if [ -z "$email" ]; then
        print_error "Email/username is required"
        echo "Usage: $0 qr <email/username>"
        exit 1
    fi
    
    # Get user UUID
    local user_data=$(jq -r ".inbounds[0].settings.clients[] | select(.email==\"$email\")" "$XRAY_CONFIG_FILE")
    
    if [ -z "$user_data" ]; then
        print_error "User '$email' not found"
        exit 1
    fi
    
    local uuid=$(echo "$user_data" | jq -r '.id')
    local flow=$(echo "$user_data" | jq -r '.flow')
    
    # Generate VLESS URL
    local vless_url=$(get_vless_url "$uuid" "$email")
    local server_ip=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}User Connection Information${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${BLUE}Email:${NC} $email"
    echo -e "${BLUE}UUID:${NC} $uuid"
    echo -e "${BLUE}Server IP:${NC} $server_ip"
    echo -e "${BLUE}Port:${NC} $XRAY_PORT"
    echo -e "${BLUE}Network:${NC} $XRAY_NETWORK"
    echo -e "${BLUE}Security:${NC} $XRAY_SECURITY"
    echo -e "${BLUE}Flow:${NC} $flow"
    
    if [ "$XRAY_SECURITY" = "reality" ]; then
        echo -e "${BLUE}SNI:${NC} ${XRAY_REALITY_SERVER_NAMES%%,*}"
        echo -e "${BLUE}Fingerprint:${NC} chrome"
        echo -e "${BLUE}Public Key:${NC} $XRAY_REALITY_PUBLIC_KEY"
        echo -e "${BLUE}Short ID:${NC} $XRAY_REALITY_SHORT_IDS"
    fi
    echo ""
    
    echo -e "${GREEN}VLESS Connection String:${NC}"
    echo "$vless_url"
    echo ""
    echo -e "${GREEN}QR Code:${NC}"
    qrencode -t ANSIUTF8 "$vless_url"
    echo ""
    echo -e "${YELLOW}Scan this QR code with v2rayNG or compatible client${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

# ============================================================
# Show Status Function
# ============================================================
show_status() {
    print_info "Xray Server Status:"
    echo ""
    
    # Check if container is running
    if docker ps | grep -q xray-server; then
        print_success "Xray container is running"
        echo ""
        docker ps --filter name=xray-server --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        
        # Show recent logs
        print_info "Recent logs (last 10 lines):"
        docker logs --tail 10 xray-server
    else
        print_error "Xray container is not running"
        print_info "Start it with: docker start xray-server"
    fi
}

# ============================================================
# Update Config Function
# ============================================================
update_config() {
    local server_ip=$(hostname -I | awk '{print $1}')
    print_info "Current configuration:"
    echo -e "${BLUE}Server IP:${NC} $server_ip"
    echo -e "${BLUE}Port:${NC} $XRAY_PORT"
    echo -e "${BLUE}Network:${NC} $XRAY_NETWORK"
    echo -e "${BLUE}Security:${NC} $XRAY_SECURITY"
    echo -e "${BLUE}Flow:${NC} $XRAY_FLOW"
    
    if [ "$XRAY_SECURITY" = "reality" ]; then
        echo ""
        echo -e "${BLUE}Reality Settings:${NC}"
        echo -e "${BLUE}  Destination:${NC} $XRAY_REALITY_DEST"
        echo -e "${BLUE}  Server Names:${NC} $XRAY_REALITY_SERVER_NAMES"
        echo -e "${BLUE}  Public Key:${NC} $XRAY_REALITY_PUBLIC_KEY"
        echo -e "${BLUE}  Short IDs:${NC} $XRAY_REALITY_SHORT_IDS"
    fi
    
    echo ""
    print_warning "To update configuration, edit workstation.env and run setup_xray.sh again"
}

# ============================================================
# Main Menu
# ============================================================
show_usage() {
    echo ""
    echo -e "${CYAN}Xray User Management Script${NC}"
    echo ""
    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  add <email>       Add a new user"
    echo "  remove <email>    Remove an existing user"
    echo "  list              List all users"
    echo "  qr <email>        Show QR code for a user"
    echo "  status            Show Xray server status"
    echo "  config            Show current configuration"
    echo "  help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo $0 add user@example.com"
    echo "  sudo $0 remove user@example.com"
    echo "  sudo $0 list"
    echo "  sudo $0 qr user@example.com"
    echo "  sudo $0 status"
    echo ""
}

# ============================================================
# Main Script Logic
# ============================================================

if [ $# -eq 0 ]; then
    show_usage
    exit 0
fi

case "$1" in
    add)
        add_user "$2"
        ;;
    remove)
        remove_user "$2"
        ;;
    list)
        list_users
        ;;
    qr)
        show_qr "$2"
        ;;
    status)
        show_status
        ;;
    config)
        update_config
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        print_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
