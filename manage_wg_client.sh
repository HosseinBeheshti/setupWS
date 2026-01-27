#!/bin/bash

# ============================================================
# WireGuard Client Management Script
# ============================================================
# This script manages WireGuard client configurations:
# - Add new clients
# - Remove existing clients
# - List all clients
# - Show client configuration
# - Regenerate client QR codes
#
# Prerequisites:
# 1. WireGuard server must be set up (run ./setup_wg.sh first)
# 2. Configuration in workstation.env
#
# Usage: sudo ./manage_wg_client.sh [add|remove|list|show|qr] [client-name]
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
ENV_FILE="./workstation.env"
if [[ ! -f "$ENV_FILE" ]]; then
    print_error "Configuration file not found: $ENV_FILE"
    exit 1
fi
source "$ENV_FILE"

# --- Validate WireGuard is set up ---
if [[ ! -f /etc/wireguard/wg0.conf ]]; then
    print_error "WireGuard server not configured. Run ./setup_wg.sh first!"
    exit 1
fi

# --- Get server information ---
WG_SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private.key 2>/dev/null || echo "")
WG_SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key 2>/dev/null || echo "")
WG_NETWORK_PREFIX=$(echo $WG_SERVER_ADDRESS | cut -d'.' -f1-3)

if [[ -z "$VPS_PUBLIC_IP" ]]; then
    VPS_PUBLIC_IP=$(hostname -I | awk '{print $1}')
fi

# --- Function: Get next available IP ---
get_next_available_ip() {
    local used_ips=$(grep -oP 'AllowedIPs = \K[0-9.]+' /etc/wireguard/wg0.conf | cut -d'/' -f1)
    local last_octet=1
    
    for octet in {2..254}; do
        local test_ip="${WG_NETWORK_PREFIX}.${octet}"
        if ! echo "$used_ips" | grep -q "^${test_ip}$"; then
            echo "$test_ip"
            return 0
        fi
    done
    
    print_error "No available IP addresses in subnet!"
    exit 1
}

# --- Function: Add Client ---
add_client() {
    local client_name="$1"
    
    if [[ -z "$client_name" ]]; then
        print_error "Client name is required!"
        echo "Usage: sudo ./manage_wg_client.sh add <client-name>"
        exit 1
    fi
    
    # Validate client name (alphanumeric, dash, underscore only)
    if ! [[ "$client_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Invalid client name. Use only alphanumeric characters, dash, and underscore."
        exit 1
    fi
    
    # Check if client already exists
    if [[ -f /etc/wireguard/clients/${client_name}.conf ]]; then
        print_error "Client '$client_name' already exists!"
        exit 1
    fi
    
    print_header "Adding WireGuard Client: $client_name"
    
    # Get next available IP
    CLIENT_IP=$(get_next_available_ip)
    print_message "Assigned IP: $CLIENT_IP"
    
    # Generate client keypair
    print_message "Generating client keypair..."
    wg genkey | tee /etc/wireguard/clients/${client_name}_private.key | wg pubkey > /etc/wireguard/clients/${client_name}_public.key
    chmod 600 /etc/wireguard/clients/${client_name}_private.key
    
    CLIENT_PRIVATE_KEY=$(cat /etc/wireguard/clients/${client_name}_private.key)
    CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/clients/${client_name}_public.key)
    
    # Create client configuration file
    print_message "Creating client configuration..."
    cat > /etc/wireguard/clients/${client_name}.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/32
DNS = $WG_CLIENT_DNS

[Peer]
PublicKey = $WG_SERVER_PUBLIC_KEY
Endpoint = $VPS_PUBLIC_IP:$WG_SERVER_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    
    # Generate QR code
    if command -v qrencode &> /dev/null; then
        print_message "Generating QR code..."
        qrencode -t ansiutf8 < /etc/wireguard/clients/${client_name}.conf > /etc/wireguard/clients/${client_name}_qr.txt
    fi
    
    # Add peer to server configuration
    print_message "Adding peer to server configuration..."
    cat >> /etc/wireguard/wg0.conf <<EOF

# Client: $client_name
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $CLIENT_IP/32

EOF
    
    # Reload WireGuard to apply changes
    print_message "Reloading WireGuard service..."
    wg syncconf wg0 <(wg-quick strip wg0)
    
    print_header "Client Added Successfully!"
    echo -e "${CYAN}Client Name:${NC}     ${GREEN}$client_name${NC}"
    echo -e "${CYAN}VPN IP:${NC}          ${GREEN}$CLIENT_IP${NC}"
    echo -e "${CYAN}Config File:${NC}     ${GREEN}/etc/wireguard/clients/${client_name}.conf${NC}"
    echo -e "${CYAN}QR Code:${NC}         ${GREEN}/etc/wireguard/clients/${client_name}_qr.txt${NC}"
    echo -e "${CYAN}Public Key:${NC}      ${GREEN}$CLIENT_PUBLIC_KEY${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "1. Copy config to client: ${CYAN}scp root@$VPS_PUBLIC_IP:/etc/wireguard/clients/${client_name}.conf .${NC}"
    echo -e "2. Show QR code: ${CYAN}sudo ./manage_wg_client.sh qr $client_name${NC}"
    echo ""
}

# --- Function: Remove Client ---
remove_client() {
    local client_name="$1"
    
    if [[ -z "$client_name" ]]; then
        print_error "Client name is required!"
        echo "Usage: sudo ./manage_wg_client.sh remove <client-name>"
        exit 1
    fi
    
    # Check if client exists
    if [[ ! -f /etc/wireguard/clients/${client_name}.conf ]]; then
        print_error "Client '$client_name' does not exist!"
        exit 1
    fi
    
    print_header "Removing WireGuard Client: $client_name"
    
    # Get client public key
    CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/clients/${client_name}_public.key 2>/dev/null || echo "")
    
    if [[ -n "$CLIENT_PUBLIC_KEY" ]]; then
        # Remove peer from server configuration
        print_message "Removing peer from server configuration..."
        
        # Create temporary config without the client
        grep -v "PublicKey = $CLIENT_PUBLIC_KEY" /etc/wireguard/wg0.conf > /etc/wireguard/wg0.conf.tmp || true
        
        # Remove the [Peer] section and AllowedIPs line for this client
        awk -v pk="$CLIENT_PUBLIC_KEY" '
        /^\[Peer\]/ { peer=1; buffer=$0"\n"; next }
        peer && /^PublicKey/ { 
            if ($3 == pk) { skip=1 } 
            else { print buffer $0; buffer=""; peer=0 }
            next
        }
        peer { buffer=buffer $0"\n"; next }
        skip && /^$/ { skip=0; next }
        skip { next }
        { print }
        ' /etc/wireguard/wg0.conf > /etc/wireguard/wg0.conf.tmp
        
        mv /etc/wireguard/wg0.conf.tmp /etc/wireguard/wg0.conf
        
        # Reload WireGuard
        print_message "Reloading WireGuard service..."
        wg syncconf wg0 <(wg-quick strip wg0)
    fi
    
    # Remove client files
    print_message "Removing client files..."
    rm -f /etc/wireguard/clients/${client_name}.conf
    rm -f /etc/wireguard/clients/${client_name}_private.key
    rm -f /etc/wireguard/clients/${client_name}_public.key
    rm -f /etc/wireguard/clients/${client_name}_qr.txt
    
    print_header "Client Removed Successfully!"
    echo -e "${GREEN}Client '$client_name' has been removed.${NC}"
    echo ""
}

# --- Function: List Clients ---
list_clients() {
    print_header "WireGuard Clients"
    
    if [[ ! -d /etc/wireguard/clients ]] || [[ -z "$(ls -A /etc/wireguard/clients/*.conf 2>/dev/null)" ]]; then
        print_warning "No clients found."
        return 0
    fi
    
    echo -e "${CYAN}Client Name          VPN IP           Status${NC}"
    echo -e "------------------------------------------------------"
    
    for conf_file in /etc/wireguard/clients/*.conf; do
        if [[ -f "$conf_file" ]]; then
            client_name=$(basename "$conf_file" .conf)
            client_ip=$(grep "^Address" "$conf_file" | awk '{print $3}' | cut -d'/' -f1)
            
            # Check if client is currently connected
            if wg show wg0 | grep -q "$(cat /etc/wireguard/clients/${client_name}_public.key 2>/dev/null)"; then
                status="${GREEN}Connected${NC}"
            else
                status="${YELLOW}Disconnected${NC}"
            fi
            
            printf "%-20s %-16s %b\n" "$client_name" "$client_ip" "$status"
        fi
    done
    
    echo ""
    total_clients=$(ls -1 /etc/wireguard/clients/*.conf 2>/dev/null | wc -l)
    echo -e "${CYAN}Total clients:${NC} $total_clients"
    echo ""
}

# --- Function: Show Client Configuration ---
show_client() {
    local client_name="$1"
    
    if [[ -z "$client_name" ]]; then
        print_error "Client name is required!"
        echo "Usage: sudo ./manage_wg_client.sh show <client-name>"
        exit 1
    fi
    
    if [[ ! -f /etc/wireguard/clients/${client_name}.conf ]]; then
        print_error "Client '$client_name' does not exist!"
        exit 1
    fi
    
    print_header "Client Configuration: $client_name"
    cat /etc/wireguard/clients/${client_name}.conf
    echo ""
}

# --- Function: Show Client QR Code ---
show_qr() {
    local client_name="$1"
    
    if [[ -z "$client_name" ]]; then
        print_error "Client name is required!"
        echo "Usage: sudo ./manage_wg_client.sh qr <client-name>"
        exit 1
    fi
    
    if [[ ! -f /etc/wireguard/clients/${client_name}.conf ]]; then
        print_error "Client '$client_name' does not exist!"
        exit 1
    fi
    
    if [[ ! -f /etc/wireguard/clients/${client_name}_qr.txt ]]; then
        if command -v qrencode &> /dev/null; then
            print_message "Generating QR code..."
            qrencode -t ansiutf8 < /etc/wireguard/clients/${client_name}.conf > /etc/wireguard/clients/${client_name}_qr.txt
        else
            print_error "qrencode not installed. Install it with: apt install qrencode"
            exit 1
        fi
    fi
    
    print_header "QR Code for: $client_name"
    cat /etc/wireguard/clients/${client_name}_qr.txt
    echo ""
    echo -e "${YELLOW}Scan this QR code with your WireGuard mobile app${NC}"
    echo ""
}

# --- Function: Show Usage ---
show_usage() {
    echo -e "${CYAN}WireGuard Client Management Script${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  sudo ./manage_wg_client.sh              # Interactive menu"
    echo -e "  sudo ./manage_wg_client.sh [command] [client-name]  # Direct command"
    echo ""
    echo -e "${YELLOW}Commands:${NC}"
    echo -e "  ${GREEN}add${NC} <client-name>     Add a new WireGuard client"
    echo -e "  ${GREEN}remove${NC} <client-name>  Remove an existing client"
    echo -e "  ${GREEN}list${NC}                  List all clients and their status"
    echo -e "  ${GREEN}show${NC} <client-name>    Display client configuration"
    echo -e "  ${GREEN}qr${NC} <client-name>      Display QR code for mobile client"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  sudo ./manage_wg_client.sh              # Start interactive menu"
    echo -e "  sudo ./manage_wg_client.sh add laptop"
    echo -e "  sudo ./manage_wg_client.sh list"
    echo ""
}

# --- Function: Interactive Menu ---
interactive_menu() {
    while true; do
        clear
        print_header "WireGuard Client Management"
        echo -e "${CYAN}Select an option:${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC} List all clients"
        echo -e "  ${GREEN}2.${NC} Add new client"
        echo -e "  ${GREEN}3.${NC} Remove client"
        echo -e "  ${GREEN}4.${NC} Show client configuration"
        echo -e "  ${GREEN}5.${NC} Show QR code for client"
        echo -e "  ${GREEN}6.${NC} Show WireGuard status"
        echo -e "  ${GREEN}0.${NC} Exit"
        echo ""
        echo -ne "${YELLOW}Enter your choice [0-6]:${NC} "
        read -r choice
        
        case "$choice" in
            1)
                echo ""
                list_clients
                echo ""
                echo -ne "${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
            2)
                echo ""
                echo -ne "${CYAN}Enter client name:${NC} "
                read -r client_name
                if [[ -n "$client_name" ]]; then
                    echo ""
                    add_client "$client_name"
                    echo ""
                    echo -ne "${YELLOW}Press Enter to continue...${NC}"
                    read -r
                else
                    print_error "Client name cannot be empty!"
                    sleep 2
                fi
                ;;
            3)
                echo ""
                list_clients
                echo ""
                echo -ne "${CYAN}Enter client name to remove:${NC} "
                read -r client_name
                if [[ -n "$client_name" ]]; then
                    echo ""
                    echo -ne "${YELLOW}Are you sure you want to remove '$client_name'? (yes/no):${NC} "
                    read -r confirm
                    if [[ "$confirm" == "yes" || "$confirm" == "y" ]]; then
                        echo ""
                        remove_client "$client_name"
                    else
                        print_message "Removal cancelled."
                    fi
                    echo ""
                    echo -ne "${YELLOW}Press Enter to continue...${NC}"
                    read -r
                else
                    print_error "Client name cannot be empty!"
                    sleep 2
                fi
                ;;
            4)
                echo ""
                list_clients
                echo ""
                echo -ne "${CYAN}Enter client name:${NC} "
                read -r client_name
                if [[ -n "$client_name" ]]; then
                    echo ""
                    show_client "$client_name"
                    echo ""
                    echo -ne "${YELLOW}Press Enter to continue...${NC}"
                    read -r
                else
                    print_error "Client name cannot be empty!"
                    sleep 2
                fi
                ;;
            5)
                echo ""
                list_clients
                echo ""
                echo -ne "${CYAN}Enter client name:${NC} "
                read -r client_name
                if [[ -n "$client_name" ]]; then
                    echo ""
                    show_qr "$client_name"
                    echo ""
                    echo -ne "${YELLOW}Press Enter to continue...${NC}"
                    read -r
                else
                    print_error "Client name cannot be empty!"
                    sleep 2
                fi
                ;;
            6)
                echo ""
                print_header "WireGuard Status"
                wg show wg0
                echo ""
                echo -ne "${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
            0)
                echo ""
                print_message "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid choice! Please select 0-6."
                sleep 2
                ;;
        esac
    done
}

# --- Main Script ---
COMMAND="${1:-}"
CLIENT_NAME="${2:-}"

# If no arguments provided, start interactive menu
if [[ -z "$COMMAND" ]]; then
    interactive_menu
fi

# Otherwise, process command-line arguments
case "$COMMAND" in
    add)
        add_client "$CLIENT_NAME"
        ;;
    remove)
        remove_client "$CLIENT_NAME"
        ;;
    list)
        list_clients
        ;;
    show)
        show_client "$CLIENT_NAME"
        ;;
    qr)
        show_qr "$CLIENT_NAME"
        ;;
    help|--help|-h)
        show_usage
        exit 0
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        echo ""
        show_usage
        exit 1
        ;;
esac

exit 0
