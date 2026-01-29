#!/bin/bash
# OpenConnect VPN Server (ocserv) Setup
# This script installs and configures ocserv for secure VPN access

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}========================================${NC}\n"; }

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Load configuration
print_message "Loading configuration from workstation.env..."
source "./workstation.env"

# Validate configuration
if [[ -z "$OCSERV_HOSTNAME" || "$OCSERV_HOSTNAME" == "<vpn.yourdomain.com>" ]]; then
    print_error "OCSERV_HOSTNAME is not configured in workstation.env"
    exit 1
fi

print_header "OpenConnect VPN Server Setup"
echo -e "Hostname: ${GREEN}$OCSERV_HOSTNAME${NC}"
echo -e "Port: ${GREEN}$OCSERV_PORT${NC}"
echo -e "Max Clients: ${GREEN}$OCSERV_MAX_CLIENTS${NC}"
echo -e "Max Per User: ${GREEN}$OCSERV_MAX_SAME_CLIENTS${NC}"
echo ""

# Install ocserv
print_header "Step 1/4: Installing OpenConnect Server"
print_message "Installing ocserv and dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y ocserv gnutls-bin

print_message "✓ ocserv installed"

# Generate SSL certificate
print_header "Step 2/4: Generating SSL Certificate"
print_message "Generating self-signed certificate for $OCSERV_HOSTNAME..."

# Create certificate directory
mkdir -p /etc/ocserv/ssl
cd /etc/ocserv/ssl

# Generate CA key and certificate
cat > ca.tmpl <<EOF
cn = "VPN CA"
organization = "VPN Server"
serial = 1
expiration_days = 3650
ca
signing_key
cert_signing_key
crl_signing_key
EOF

certtool --generate-privkey --outfile ca-key.pem
certtool --generate-self-signed --load-privkey ca-key.pem --template ca.tmpl --outfile ca-cert.pem

# Generate server key and certificate
cat > server.tmpl <<EOF
cn = "$OCSERV_HOSTNAME"
organization = "VPN Server"
serial = 2
expiration_days = 3650
signing_key
encryption_key
tls_www_server
EOF

certtool --generate-privkey --outfile server-key.pem
certtool --generate-certificate --load-privkey server-key.pem --load-ca-certificate ca-cert.pem \
    --load-ca-privkey ca-key.pem --template server.tmpl --outfile server-cert.pem

# Set permissions
chmod 600 server-key.pem ca-key.pem
chmod 644 server-cert.pem ca-cert.pem

print_message "✓ SSL certificates generated"

# Configure ocserv
print_header "Step 3/4: Configuring OpenConnect Server"
print_message "Creating ocserv configuration..."

# Backup original config
if [[ -f /etc/ocserv/ocserv.conf ]]; then
    cp /etc/ocserv/ocserv.conf /etc/ocserv/ocserv.conf.backup
fi

# Create new configuration
cat > /etc/ocserv/ocserv.conf <<EOF
# OpenConnect VPN Server Configuration
# Authentication method: plain password file
auth = "plain[passwd=/etc/ocserv/ocpasswd]"

# TCP and UDP port number
tcp-port = $OCSERV_PORT
udp-port = $OCSERV_PORT

# Server certificate and key
server-cert = /etc/ocserv/ssl/server-cert.pem
server-key = /etc/ocserv/ssl/server-key.pem

# Certificate authority (CA) certificate
ca-cert = /etc/ocserv/ssl/ca-cert.pem

# Isolation: Prevent clients from seeing each other
isolate-workers = true

# Maximum clients
max-clients = $OCSERV_MAX_CLIENTS

# Maximum same clients (connections per username)
max-same-clients = $OCSERV_MAX_SAME_CLIENTS

# Server's hostname (for client verification)
# Comment out if using self-signed certificate
# cert-user-oid = 2.5.4.3

# Use plain for password authentication
# enable-auth = "certificate"
# enable-auth = "plain"

# Keep alive in seconds
keepalive = 32400

# Dead peer detection in seconds
dpd = 90

# MTU discovery
try-mtu-discovery = true

# TLS priorities
tls-priorities = "NORMAL:%SERVER_PRECEDENCE:%COMPAT:-RSA:-VERS-SSL3.0:-ARCFOUR-128"

# Authentication timeout in seconds
auth-timeout = 240

# Session timeout in seconds (0 = unlimited)
idle-timeout = 1200
mobile-idle-timeout = 1800

# Minimum time to reauthenticate in seconds
min-reauth-time = 300

# Session timeout for mobile devices
cookie-timeout = 86400

# Deny roaming between IPs
deny-roaming = false

# Rekey interval (in seconds)
rekey-time = 172800

# Rekey method
rekey-method = ssl

# Use compression
compression = true

# Disable DTLs
# no-compress-limit = 256

# Routes to push to client (default: all traffic through VPN)
# Comment out to split-tunnel specific routes only
route = default
# route = 192.168.1.0/255.255.255.0

# DNS servers to push to clients
EOF

# Add DNS servers
IFS=',' read -ra DNS_ARRAY <<< "$OCSERV_DNS"
for dns in "${DNS_ARRAY[@]}"; do
    echo "dns = $(echo $dns | xargs)" >> /etc/ocserv/ocserv.conf
done

cat >> /etc/ocserv/ocserv.conf <<EOF

# IPv4 network configuration
ipv4-network = $OCSERV_IPV4_NETWORK
ipv4-netmask = $OCSERV_IPV4_NETMASK

# Tunnel all DNS queries through VPN
tunnel-all-dns = true

# User profile configuration
# user-profile = /etc/ocserv/profile.xml

# Device and networking
device = vpns

# Predictable IP addresses (same IP for same user)
predictable-ips = true

# Default domain
# default-domain = example.com

# Custom headers (optional)
# custom-header = "X-My-Header: my-value"

# Cisco client compatibility
cisco-client-compat = true

# DTLS legacy mode (for older clients)
# dtls-legacy = true

# Firewall mark for routing
# fwmark = 10

# Per-user/group configurations
# config-per-user = /etc/ocserv/config-per-user/
# config-per-group = /etc/ocserv/config-per-group/

# Ban time for failed authentication attempts
# ban-reset-time = 300

# Maximum failed login attempts
# max-ban-score = 80

# Ban score for wrong password
# ban-score-authentication-failed = 10

# Logging
# output-buffer = 10
# log-level = 1

# PID file
pid-file = /run/ocserv.pid

# Socket for communication
socket-file = /run/ocserv-socket

# Run as specific user/group after initialization
run-as-user = nobody
run-as-group = daemon

# Networking settings
net-priority = 6
EOF

print_message "✓ ocserv configured"

# Enable IPv4 forwarding
print_header "Step 4/4: Enabling IP Forwarding and NAT"
print_message "Enabling IPv4 forwarding..."

# Enable IPv4 forwarding
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ocserv-forward.conf
sysctl -p /etc/sysctl.d/99-ocserv-forward.conf

# Get primary network interface
PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
print_message "Primary interface detected: $PRIMARY_INTERFACE"

# Configure iptables NAT for VPN traffic
print_message "Configuring iptables NAT rules..."

# Enable NAT/Masquerading for VPN clients
iptables -t nat -A POSTROUTING -s $OCSERV_IPV4_NETWORK/24 -o $PRIMARY_INTERFACE -j MASQUERADE

# Allow forwarding for VPN traffic
iptables -A FORWARD -s $OCSERV_IPV4_NETWORK/24 -j ACCEPT
iptables -A FORWARD -d $OCSERV_IPV4_NETWORK/24 -j ACCEPT

# Save iptables rules
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
elif command -v iptables-save &> /dev/null; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
fi

print_message "✓ NAT configured"

# Enable and start ocserv service
print_message "Enabling and starting ocserv service..."
systemctl enable ocserv
systemctl restart ocserv

# Wait for service to start
sleep 2

# Check service status
if systemctl is-active --quiet ocserv; then
    print_message "✓ ocserv service started successfully"
else
    print_error "ocserv service failed to start"
    print_message "Check logs with: journalctl -u ocserv -n 50"
    exit 1
fi

print_header "Setup Complete!"
echo -e "${GREEN}OpenConnect VPN Server configured successfully!${NC}\n"
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Server: ${GREEN}$OCSERV_HOSTNAME:$OCSERV_PORT${NC}"
echo -e "  Max Clients: ${GREEN}$OCSERV_MAX_CLIENTS${NC}"
echo -e "  Max Per User: ${GREEN}$OCSERV_MAX_SAME_CLIENTS${NC}"
echo -e "  VPN Network: ${GREEN}$OCSERV_IPV4_NETWORK/$OCSERV_IPV4_NETMASK${NC}"
echo -e "  DNS: ${GREEN}$OCSERV_DNS${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Add VPN users: ${GREEN}sudo ./manage_ocserv.sh add <username>${NC}"
echo -e "  2. Remove users: ${GREEN}sudo ./manage_ocserv.sh remove <username>${NC}"
echo -e "  3. List users: ${GREEN}sudo ./manage_ocserv.sh list${NC}"
echo -e "  4. Connect clients to: ${GREEN}$OCSERV_HOSTNAME:$OCSERV_PORT${NC}"
echo ""
echo -e "${YELLOW}Note:${NC} Port $OCSERV_PORT will be added to firewall by setup_fw.sh"

exit 0
