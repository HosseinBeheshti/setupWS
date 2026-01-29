#!/bin/bash
# Cloudflare Tunnel Setup for Zero Trust Access
# This script installs and configures cloudflared for secure SSH/VNC access

set -e

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Load configuration
source "./workstation.env"

# Validate tunnel token
if [[ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]]; then
    echo "CLOUDFLARE_TUNNEL_TOKEN is not set in workstation.env"
    exit 1
fi

# Add Cloudflare GPG key
mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null

# Add Cloudflare repository
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list

# Install cloudflared
apt-get update && apt-get install -y cloudflared

# Install and start cloudflared service with tunnel token
cloudflared service install "$CLOUDFLARE_TUNNEL_TOKEN"

echo "Cloudflare tunnel setup complete"
