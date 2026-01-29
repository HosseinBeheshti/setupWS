#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

source "./workstation.env"

if [[ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]]; then
    echo "CLOUDFLARE_TUNNEL_TOKEN is not set in workstation.env"
    exit 1
fi

mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
apt-get update && apt-get install -y cloudflared
cloudflared service install "$CLOUDFLARE_TUNNEL_TOKEN"

echo "Cloudflare tunnel setup complete"
