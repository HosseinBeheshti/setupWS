#!/bin/bash

# Universal VPN Connection Script
# Supports L2TP and OpenVPN with dynamic app selection

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Helper Functions ---
print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${CYAN}[SELECT]${NC} $1"; }

# --- Load Configuration ---
ENV_FILE="./workstation.env"
if [[ ! -f "$ENV_FILE" ]]; then
    print_error "Configuration file not found: $ENV_FILE"
    exit 1
fi
source "$ENV_FILE"

# --- Check if running as root ---
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# --- L2TP Connection Functions ---
connect_l2tp() {
    L2TP_TABLE="vpn_l2tp"
    L2TP_FWMARK="200"
    
    print_message "Starting L2TP VPN services..."
    systemctl restart strongswan-starter
    systemctl restart xl2tpd
    sleep 3

    print_message "Loading IPsec configuration..."
    ipsec reload 2>/dev/null || ipsec restart 2>/dev/null || true
    sleep 2

    print_message "Establishing L2TP VPN connection..."
    ipsec up l2tpvpn
    sleep 3
    echo "c l2tpvpn" > /var/run/xl2tpd/l2tp-control

    print_message "Waiting for VPN connection..."
    for i in {1..15}; do
        if ip addr show | grep -q ppp0; then
            print_message "VPN interface ppp0 is UP!"
            break
        fi
        sleep 1
    done

    if ip addr show | grep -q ppp0; then
        PPP_LOCAL_IP=$(ip addr show ppp0 | grep -oP 'inet \K[0-9.]+' | head -n1)
        print_message "=== L2TP VPN Connected Successfully ==="
        echo ""
        echo -e "${YELLOW}VPN Type:${NC} L2TP/IPsec"
        echo -e "${YELLOW}Interface:${NC} ppp0"
        echo -e "${YELLOW}Local IP:${NC} $PPP_LOCAL_IP"
        echo -e "${YELLOW}Gateway:${NC} ${L2TP_PPP_GATEWAY}"
        echo -e "${YELLOW}Routing Table:${NC} $L2TP_TABLE"
        
        if [[ -n "$VPN_APPS" ]]; then
            echo -e "${YELLOW}Routing Apps:${NC} $VPN_APPS"
        fi
        
        if [[ -n "$L2TP_REMOTE_PC_IP" ]]; then
            echo -e "${YELLOW}Remote PC:${NC} $L2TP_REMOTE_PC_IP"
            print_message "Testing connectivity to $L2TP_REMOTE_PC_IP..."
            if ping -c 2 -W 3 "$L2TP_REMOTE_PC_IP" >/dev/null 2>&1; then
                print_message "✓ Remote PC is reachable"
            else
                print_warning "✗ Remote PC is not reachable"
            fi
        fi
        
        echo ""
        display_status_info
        
        # Keep the script running
        while ip addr show | grep -q ppp0; do
            sleep 5
        done
        
        print_warning "VPN connection lost!"
    else
        print_error "VPN connection failed!"
        print_error "Check logs with: journalctl -xeu strongswan-starter"
        print_error "                 journalctl -xeu xl2tpd"
        exit 1
    fi
}

disconnect_l2tp() {
    print_message "Disconnecting L2TP VPN..."
    
    # Disconnect L2TP
    echo "d l2tpvpn" > /var/run/xl2tpd/l2tp-control 2>/dev/null || true
    sleep 2
    
    # Stop IPsec
    ipsec down l2tpvpn 2>/dev/null || true
    
    # Clean up routing rules
    ip rule del fwmark 200 table vpn_l2tp 2>/dev/null || true
    ip route flush table vpn_l2tp 2>/dev/null || true
    ip route flush cache 2>/dev/null || true
    
    print_message "L2TP VPN disconnected."
}


# --- Display Status Info ---
display_status_info() {
    echo -e "${GREEN}VPN is active and will disconnect when you close this terminal${NC}"
    echo -e "Press ${YELLOW}Ctrl+C${NC} to disconnect and exit"
    echo ""
    echo -e "${GREEN}Useful Commands (in another terminal):${NC}"
    echo -e "  Check VPN status: ${GREEN}ip addr show ppp0${NC}"
    echo -e "  Check routing: ${GREEN}ip route show table vpn_l2tp${NC}"
    echo -e "  Check IPsec: ${GREEN}sudo ipsec statusall${NC}"   
    
    if [[ -n "$VPN_APPS" ]]; then
        echo ""
        echo -e "${GREEN}Apps routed through VPN:${NC}"
        for app in $VPN_APPS; do
            echo -e "  ${GREEN}${app}${NC}"
        done
    fi
    echo ""
}

# --- Cleanup Function ---
cleanup() {
    echo ""
    disconnect_l2tp
    exit 0
}

# Set trap to disconnect on exit
trap cleanup EXIT INT TERM

# --- Main Script ---
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   VPN Connection Manager${NC}"
echo -e "${CYAN}========================================${NC}"



echo ""
print_message "Starting VPN connection..."

connect_l2tp

exit 0
