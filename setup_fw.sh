#!/bin/bash
# Firewall Configuration for Secure Remote Access Gateway
# This script configures UFW firewall rules based on workstation.env settings
# By default, all ports are blocked except those explicitly allowed

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Load configuration
print_message "Loading firewall configuration from workstation.env..."
source "./workstation.env"

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    print_error "UFW is not installed"
    exit 1
fi

# Reset UFW to clean slate
print_message "Resetting firewall to defaults..."
ufw --force reset

# Set default policies: deny incoming, allow outgoing
print_message "Setting default policies (deny incoming, allow outgoing)..."
ufw default deny incoming
ufw default allow outgoing

# Allow ports from configuration (if set)
if [[ -n "$FIREWALL_ALLOWED_PORTS" ]]; then
    print_message "Allowing configured ports: $FIREWALL_ALLOWED_PORTS"
    IFS=',' read -ra PORTS <<< "$FIREWALL_ALLOWED_PORTS"
    for port in "${PORTS[@]}"; do
        port=$(echo "$port" | xargs)  # Trim whitespace
        if [[ "$port" =~ ^[0-9]+/(tcp|udp)$ ]]; then
            ufw allow "$port" comment "Custom allowed port"
            print_message "  ✓ Allowed: $port"
        elif [[ "$port" =~ ^[0-9]+$ ]]; then
            ufw allow "$port" comment "Custom allowed port"
            print_message "  ✓ Allowed: $port (tcp/udp)"
        else
            print_warning "  ✗ Invalid port format: $port (use 'port/protocol' or 'port')"
        fi
    done
else
    print_message "No custom ports to allow (FIREWALL_ALLOWED_PORTS not set)"
fi

# Enable firewall
print_message "Enabling firewall..."
ufw --force enable

# Display status
print_message "Firewall configuration complete!"
echo ""
print_message "Current firewall status:"
ufw status verbose | grep -v "^$" || true
echo ""
print_warning "Access to services is restricted to Cloudflare tunnel only"
print_warning "Direct SSH/VNC access is BLOCKED for security"

exit 0
