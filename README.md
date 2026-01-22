# Cloudflare Zero Trust VPS Setup Guide

This guide provides complete step-by-step instructions for deploying **Cloudflare Zero Trust Network Access (ZTNA)** on your VPS with dual-tier access control:

- **Admin Tier:** SSH, VNC, and VPN management access with TOTP 2FA + device posture checks
- **User Tier:** WireGuard VPN for secure traffic routing through VPS

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Part 1: Cloudflare Zero Trust Setup](#part-1-cloudflare-zero-trust-setup)
- [Part 2: VPS Server Setup](#part-2-vps-server-setup)
- [Part 3: Admin Access Configuration](#part-3-admin-access-configuration)
- [Part 4: User Access with WireGuard](#part-4-user-access-with-wireguard)
- [Part 5: Admin Workflows](#part-5-admin-workflows)
- [Part 6: Backup & Recovery](#part-6-backup--recovery)
- [Part 7: Monitoring & Troubleshooting](#part-7-monitoring--troubleshooting)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         ADMIN ACCESS TIER                            │
│                                                                       │
│  Admin Device (with WARP Client + 2FA)                              │
│         │                                                             │
│         ├─► Cloudflare Access (TOTP + Device Posture Check)         │
│         │                                                             │
│         ├─► Cloudflare Tunnel ──► VPS Services:                     │
│         │                           ├─ SSH (port 22)                 │
│         │                           ├─ VNC (1370, 1377, 1380)        │
│         │                           └─ Admin Scripts (L2TP/OpenVPN)  │
│         │                                                             │
└─────────┴─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                         USER ACCESS TIER                             │
│                                                                       │
│  User Devices                                                        │
│         │                                                             │
│         └─► WireGuard Client                                         │
│                  └─► VPS WireGuard Server (port 51820/udp)          │
│                           └─► Internet via VPS                       │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Features

- **Zero Trust Security:** All access requires authentication + device verification
- **TOTP 2FA:** Time-based one-time passwords (Google Authenticator/Authy)
- **Device Posture Checks:** Only registered devices with WARP client can access
- **WireGuard VPN:** High-performance VPN for secure traffic routing
- **Automated Management:** Scripts for user provisioning, monitoring, and backups
- **SQLite Database:** Track users, devices, and connections

---

## Prerequisites

### Server Requirements

- **VPS with Ubuntu 22.04 or 24.04 LTS**
- **Minimum:** 2 CPU cores, 4GB RAM, 50GB storage
- **Root or sudo access**
- **Public IP address**
- **Open ports:** 22 (SSH), 51820 (WireGuard)

### Cloudflare Requirements

- **Cloudflare account** (free tier is sufficient)
- **Domain name** pointed to Cloudflare nameservers
- **Cloudflare Zero Trust** account (free up to 50 users)

### Client Requirements

**For Admins:**
- **Cloudflare WARP client** installed
- **Authenticator app** (Google Authenticator, Authy, Microsoft Authenticator)
- **VNC client** (TigerVNC, RealVNC, Remmina)

**For Users:**
- **WireGuard client** (Windows, macOS, Linux, iOS, Android)

---

## Part 1: Cloudflare Zero Trust Setup

### Step 1.1: Create Zero Trust Organization

1. **Sign up for Zero Trust:**
   - Navigate to [Cloudflare One Dashboard](https://one.dash.cloudflare.com/)
   - On the onboarding screen, select **Zero Trust**
   
2. **Choose team name:**
   ```
   Team name: your-company-ztna
   ```
   - This creates your team domain: `https://your-company-ztna.cloudflareaccess.com`
   - Your team name is a unique identifier for your organization
   - Users will enter this when enrolling devices

3. **Select subscription plan:**
   - Choose **Free** plan (up to 50 users)
   - Complete payment details (required but no charge for Free plan)

### Step 1.2: Configure Identity Provider

1. **Add identity provider:**
   - Go to **Integrations** → **Identity providers**
   - Select **Add new identity provider**

2. **Choose authentication method:**
   
   **Option A: One-time PIN (OTP)** - Quick setup, good for testing:
   - Select **One-time PIN**
   - Enable **TOTP (Time-based OTP)**
   - Users will receive email codes or scan QR codes
   - Compatible with Google Authenticator, Authy, Microsoft Authenticator
   
   **Option B: Enterprise IdP** - For production environments:
   - Select your IdP (Okta, Microsoft Entra ID, Google Workspace, etc.)
   - Follow provider-specific setup instructions
   - Supports SAML or OIDC protocols

### Step 1.3: Create Cloudflare Tunnel

1. **Navigate to Tunnels:**
   - Go to **Networks** → **Connectors** → **Cloudflare Tunnels**
   - Select **Create a tunnel**

2. **Choose connector type:**
   - Select **Cloudflared**
   - Click **Next**

3. **Name your tunnel:**
   ```
   Tunnel name: vps-ztna-tunnel
   ```
   - Click **Save tunnel**

4. **Install connector (save for VPS setup):**
   - Copy the installation command shown
   - Example: `cloudflared tunnel run --token eyJhIjoiMTIzNC...`
   - **Save the token** (starts with `eyJh...`) - you'll need it in Step 2

5. **Configure public hostname routes:**
   
   Go to **Published applications** tab and add:

   **SSH Access:**
   - Subdomain: `ssh`
   - Domain: `yourdomain.com` (select from dropdown)
   - Service Type: `SSH`
   - URL: `localhost:22`
   - Click **Save**

   **VNC Applications (repeat for each user):**
   
   For hossein:
   - Subdomain: `vnc-hossein`
   - Domain: `yourdomain.com`
   - Service Type: `HTTP`
   - URL: `localhost:1370`
   - Save

   For asal:
   - Subdomain: `vnc-asal`
   - Domain: `yourdomain.com`
   - Service Type: `HTTP`
   - URL: `localhost:1377`
   - Save

   For hassan:
   - Subdomain: `vnc-hassan`
   - Domain: `yourdomain.com`
   - Service Type: `HTTP`
   - URL: `localhost:1380`
   - Save

6. **Complete tunnel setup:**
   - Select **Next**
   - Your tunnel should show **Healthy** status once the connector runs on your VPS

### Step 1.4: Enable Device Posture Checks

**Important:** Complete this step BEFORE creating Access applications so posture checks are available in policies.

1. **Enable the WARP posture check:**
   - Go to **Reusable components** → **Posture checks**
   - In **WARP client checks** section, select **Add a check**
   - Select **WARP** (to allow any WARP client including consumer version)
   - OR select **Gateway** (to require Zero Trust enrolled devices only - recommended)
   - Click **Save**

### Step 1.5: Create Access Applications & Policies

Now that posture checks are enabled, you can use them in Access policies.

#### Access Policies 
1. **Admin Access policy:**
   ```
   Policy name: Admin Policy
   Action: Allow
   ```
   **Include rule:**
   - Selector: **Emails**
   - Value: `admin@yourdomain.com`
   
   **Require rules:**
   - Selector: **Login Methods** → Value: `One-time PIN`
   - Selector: **WARP** or **Gateway** (whichever you enabled in Step 1.4)


#### SSH Access Application

1. **Create application:**
   - Go to **Access controls** → **Applications**
   - Select **Add an application**
   - Choose **Self-hosted**

2. **Configure application:**
   ```
   Application name: Admin SSH Access
   Session Duration: 12 hours
   ```

3. **Add public hostname:**
   - Select **Add public hostname**
   - Domain: `ssh.yourdomain.com`
   - Click **Next**

4. **Apply the Admin Policy:**
   - In the **Policies** tab, select **Add a policy**
   - Select **Admin Policy** from the existing policies dropdown
   - Click **Next**

5. **Finalize settings:**
   - Configure App Launcher visibility (optional)
   - Set block page behavior
   - Click **Save**

#### VNC Access Application - Hossein

1. **Create application:**
   - Go to **Access controls** → **Applications**
   - Select **Add an application**
   - Choose **Self-hosted**

2. **Configure application:**
   ```
   Application name: VNC - Hossein
   Session Duration: 12 hours
   ```

3. **Add public hostname:**
   - Select **Add public hostname**
   - Domain: `vnc-hossein.yourdomain.com`
   - Click **Next**

4. **Apply the Admin Policy:**
   - In the **Policies** tab, select **Add a policy**
   - Select **Admin Policy** from the existing policies dropdown
   - Click **Next**

5. **Finalize settings:**
   - Under **Experience settings**, select **Show application in App Launcher** (optional)
   - Set block page behavior
   - Click **Save**

#### Verify All Applications

After creating all applications:
- Go to **Access controls** → **Applications**
- You should see 4 applications listed:
  - Admin SSH Access
  - VNC - Hossein
  - VNC - Asal
  - VNC - Hassan
- Each should show status as **Active**
- All should be using the same **Admin Policy**

---

## Part 2: VPS Server Setup

### Step 2.1: Clone Repository

SSH to your VPS and clone the setupWS repository:

```bash
# SSH to VPS
ssh root@your-vps-ip

# Clone repository
cd /root
git clone https://github.com/HosseinBeheshti/setupWS.git
cd setupWS
```

### Step 2.2: Configure Environment Variables

Edit the `workstation.env` file:

```bash
vim workstation.env
```

### Step 2.3: Run Setup Script

Execute the master setup script:

```bash
sudo ./setup_server.sh
```

**What this does:**
- Installs Docker, Docker Compose, `cloudflared`, `qrencode`, `sqlite3`
- Creates directory structure (`/etc/cloudflare/`, `/var/lib/ztna/`, `/etc/wireguard/`)
- Initializes SQLite database with schema
- Deploys Docker containers (WireGuard, cloudflared)
- Configures UFW firewall rules
- Sets up VNC users and virtual router (existing functionality)
- Starts all services

**Installation time:** ~10-15 minutes

### Step 2.4: Verify Services

Check that all Docker containers are running:

```bash
docker ps
```

Expected output:
```
CONTAINER ID   IMAGE                              STATUS
def789ghi012   linuxserver/wireguard              Up 2 minutes
ghi345jkl678   cloudflare/cloudflared:latest      Up 2 minutes
```

Verify Cloudflare tunnel connection:

```bash
docker logs cloudflared
```

Look for:
```
Registered tunnel connection
```

---

## Part 3: Admin Access Configuration

### Step 3.1: Install WARP Client (Admin Device)

**On Windows:**
1. Download from: https://1.1.1.1/
2. Install and run `Cloudflare WARP.exe`
3. Click **Settings** → **Preferences** → **Gateway with WARP**

**On macOS:**
1. Download from: https://1.1.1.1/
2. Install `Cloudflare_WARP.pkg`
3. Open WARP app → **Preferences** → **Account** → **Login to Cloudflare Zero Trust**

**On Linux:**
```bash
# Ubuntu/Debian
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
sudo apt update && sudo apt install cloudflare-warp

# Register and connect
warp-cli register
warp-cli set-mode warp
warp-cli connect
```

### Step 3.2: Enroll Device with Zero Trust

1. **Login to Zero Trust:**
   - Open browser and navigate to: `https://your-company-ztna.cloudflareaccess.com`
   - Enter your admin email
   - Check email and click verification link

2. **Setup TOTP 2FA:**
   - On first login, you'll see QR code
   - Open authenticator app (Google Authenticator/Authy)
   - Scan QR code
   - Enter 6-digit code to verify
   - **Save backup codes** securely

3. **Register device:**
   - WARP client will show "Connected to Zero Trust"
   - Your device is now registered with serial number/identifier
   - Device posture checks are active

### Step 3.3: Access VNC via Cloudflare

**Option 1: Web Browser (noVNC)**

1. Navigate to: `https://vnc-hossein.yourdomain.com`
2. Enter TOTP code when prompted
3. Browser-based VNC session starts

**Option 2: VNC Client (SSH Tunnel)**

1. **Create SSH tunnel:**
   ```bash
   ssh -L 5901:localhost:1370 ssh.yourdomain.com
   ```
   - Enter TOTP code when prompted

2. **Connect VNC client:**
   ```bash
   vncviewer localhost:5901
   ```
   - Enter VNC password for user `hossein`

**Option 3: Direct VNC over Cloudflare Tunnel**

Configure VNC client to use Cloudflare Access:
```bash
# Install cloudflared on client machine
# Access VNC through tunnel
cloudflared access ssh --hostname vnc-hossein.yourdomain.com --destination localhost:1370
```

### Step 3.4: Access SSH via Cloudflare

**Using cloudflared proxy:**

1. **Install cloudflared on client:**
   ```bash
   # Linux/macOS
   brew install cloudflare/cloudflare/cloudflared
   
   # Or download from: https://github.com/cloudflare/cloudflared/releases
   ```

2. **SSH through tunnel:**
   ```bash
   cloudflared access ssh --hostname ssh.yourdomain.com
   ```
   - Browser opens for authentication
   - Enter TOTP code
   - SSH session established

3. **Configure SSH client (optional):**
   
   Add to `~/.ssh/config`:
   ```
   Host vps-ztna
       HostName ssh.yourdomain.com
       ProxyCommand cloudflared access ssh --hostname %h
       User root
   ```
   
   Then simply:
   ```bash
   ssh vps-ztna
   ```

---

## Part 4: User Access with WireGuard

### Step 4.1: Provision WireGuard Peer

On the VPS (as root/admin), run the provisioning script:

```bash
cd /root/setupWS
sudo ./add_wg_peer.sh john_doe
```

**Output:**
```
========================================
WireGuard Peer Provisioning
========================================
Username: john_doe
Assigned IP: 10.13.13.2
Public Key: ABC123...
Private Key: (saved in config)

Config file: /var/lib/ztna/clients/john_doe.conf
Database record: Created

========================================
CLIENT CONFIGURATION
========================================
[Interface]
PrivateKey = XYZ789...
Address = 10.13.13.2/32
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = ServerPublicKeyHere...
Endpoint = your.vps.public.ip:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25

========================================
QR CODE (Scan with mobile device)
========================================
█████████████████████████████████
█████████████████████████████████
████ ▄▄▄▄▄ █▀█ █▄▄▀▀ ▄▄▄▄▄ ████
████ █   █ █▀▀▀█ ▄ █ █   █ ████
...
```

### Step 4.2: Distribute Configuration to User

**Method 1: Config File (Desktop/Laptop)**

Send the user the config file:
```bash
# Copy from VPS
scp root@vps-ip:/var/lib/ztna/clients/john_doe.conf ~/john_doe.conf
```

**Method 2: QR Code (Mobile)**

User scans QR code with WireGuard app:
- Take screenshot of QR code
- Or share terminal output securely

### Step 4.3: Client Setup

**On Windows:**
1. Download WireGuard: https://www.wireguard.com/install/
2. Install and open WireGuard app
3. Click **Add Tunnel** → **Import from file**
4. Select `john_doe.conf`
5. Click **Activate**

**On macOS:**
1. Download from App Store: "WireGuard"
2. Open app → **Import tunnel(s) from file**
3. Select config file
4. Toggle connection on

**On Linux:**
```bash
# Install WireGuard
sudo apt install wireguard

# Copy config
sudo cp john_doe.conf /etc/wireguard/wg0.conf

# Start connection
sudo wg-quick up wg0

# Enable on boot
sudo systemctl enable wg-quick@wg0
```

**On iOS/Android:**
1. Install "WireGuard" app from App Store/Play Store
2. Open app → **+** → **Create from QR code**
3. Scan QR code from terminal
4. Toggle connection on

### Step 4.4: Verify Connection

**On Client:**
```bash
# Check connection status
ping 10.13.13.1  # VPS gateway

# Verify public IP (should show VPS IP)
curl ifconfig.me
```

**On Server:**
```bash
# List active peers
sudo wg show

# Query database
sudo ./query_users.sh
# Select option 1: List all peers
```

---

## Part 5: Admin Workflows

### Workflow 1: Add New WireGuard User

```bash
# SSH to VPS
ssh vps-ztna

# Navigate to repo
cd /root/setupWS

# Provision new user
sudo ./add_wg_peer.sh alice_smith

# Send config to user securely
# Option 1: Email the .conf file
# Option 2: Share QR code screenshot
# Option 3: Use secure file transfer
```

### Workflow 2: List Active Users

```bash
# Run query script
sudo ./query_users.sh

# Select option: 1 (List all peers)
```

**Output:**
```
========================================
ALL WIREGUARD PEERS
========================================
ID | Username    | Device ID | Peer IP      | Created At           | Last Seen
---+-------------+-----------+--------------+----------------------+----------------------
1  | john_doe    | ABC123    | 10.13.13.2   | 2026-01-21 10:30:00 | 2026-01-21 14:20:00
2  | alice_smith | DEF456    | 10.13.13.3   | 2026-01-21 11:15:00 | 2026-01-21 14:18:00
3  | bob_jones   | GHI789    | 10.13.13.4   | 2026-01-21 12:00:00 | Never
```

### Workflow 3: Remove User

```bash
# Run query script
sudo ./query_users.sh

# Select option: 3 (Remove peer)
# Enter username when prompted: bob_jones

# Script will:
# - Remove from SQLite database
# - Remove from WireGuard config
# - Restart WireGuard container
# - Confirm deletion
```

### Workflow 4: Provision L2TP/OpenVPN for User

Admins can use existing scripts to set up VPN services for their managed users:

```bash
# Access VNC via Cloudflare
# Open terminal in VNC session

# Setup L2TP VPN
cd /root/setupWS
sudo ./setup_l2tp.sh

# Or setup OpenVPN client
sudo ./setup_ovpn.sh

# Run VPN connection manager
sudo ./run_vpn.sh
# Select VPN type and applications to route
```

### Workflow 5: Monitor Connections

**Real-time WireGuard status:**
```bash
# Show all peers and bandwidth
sudo wg show all

# Continuous monitoring
watch -n 5 'sudo wg show all'
```

**Query connection logs:**
```bash
sudo ./query_users.sh
# Select option: 2 (Show active connections)
```

**Docker container stats:**
```bash
# Resource usage
docker stats

# Service logs
docker logs -f wireguard
docker logs -f shadowsocks
docker logs -f cloudflared
```

### Workflow 6: Update User Last Seen

The `add_wg_peer.sh` script automatically updates last seen on each handshake. Manual update:

```bash
# Run query script
sudo ./query_users.sh
# Select option: 4 (Update last seen)
```

---

## Part 6: Backup & Recovery

### Automated Backups

The `backup_ztna.sh` script runs daily at 2 AM via cron.

**Setup cron job:**
```bash
# Edit crontab
sudo crontab -e

# Add this line:
0 2 * * * /root/setupWS/backup_ztna.sh
```

**Backup includes:**
- SQLite database (`/var/lib/ztna/users.db`)
- WireGuard configuration (`/etc/wireguard/`)
- Cloudflare credentials (`/etc/cloudflare/`)
- Docker Compose file (`docker-compose-ztna.yml`)
- Environment variables (`workstation.env`)

**Backup location:**
```
/var/lib/ztna/backups/ztna-backup-YYYYMMDD-HHMMSS.tar.gz
```

**Retention:** Last 30 days kept automatically.

### Manual Backup

```bash
# Run backup script manually
sudo /root/setupWS/backup_ztna.sh

# Verify backup created
ls -lh /var/lib/ztna/backups/
```

### Restore from Backup

```bash
# List available backups
ls -lh /var/lib/ztna/backups/

# Extract backup
cd /tmp
sudo tar -xzf /var/lib/ztna/backups/ztna-backup-20260121-020000.tar.gz

# Stop services
docker-compose -f /root/setupWS/docker-compose-ztna.yml down

# Restore database
sudo cp tmp/var/lib/ztna/users.db /var/lib/ztna/users.db

# Restore WireGuard config
sudo cp -r tmp/etc/wireguard/* /etc/wireguard/

# Restore Cloudflare config
sudo cp -r tmp/etc/cloudflare/* /etc/cloudflare/

# Restart services
docker-compose -f /root/setupWS/docker-compose-ztna.yml up -d

# Verify restoration
sudo wg show
sudo ./query_users.sh
```

### Remote Backup (Optional)

Configure automatic sync to remote storage:

**Using rsync to remote server:**
```bash
# Edit backup_ztna.sh
vim /root/setupWS/backup_ztna.sh

# Add at the end:
# rsync -avz --delete /var/lib/ztna/backups/ user@backup-server:/backups/vps-ztna/
```

**Using rclone to cloud storage (S3/B2/R2):**
```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Configure remote
rclone config

# Add to backup_ztna.sh:
# rclone sync /var/lib/ztna/backups/ remote:vps-ztna-backups/
```

---

## Part 7: Monitoring & Troubleshooting

### Health Checks

**1. Check all services:**
```bash
# Docker containers
docker ps -a

# Expected: All containers with status "Up"
```

**2. Check Cloudflare tunnel:**
```bash
docker logs cloudflared | tail -20

# Look for: "Registered tunnel connection"
# No errors about authentication or connectivity
```

**3. Check WireGuard:**
```bash
sudo wg show

# Should show interface, peers, and handshakes
```

**4. Check Shadowsocks:**
```bash
docker logs shadowsocks | tail -20

# Should show: "listening on 0.0.0.0:8388"
```

**5. Check firewall:**
```bash
sudo ufw status

# Verify ports open:
# 22/tcp (SSH)
# 443/tcp (Shadowsocks)
# 51820/udp (WireGuard)
```

### Common Issues

#### Issue 1: Cloudflare Tunnel Not Connecting

**Symptoms:**
- Cannot access `ssh.yourdomain.com` or VNC URLs
- Browser shows "502 Bad Gateway"

**Diagnosis:**
```bash
docker logs cloudflared
```

**Solutions:**

1. **Invalid token:**
   ```bash
   # Re-generate token in Cloudflare dashboard
   # Update workstation.env
   vim /root/setupWS/workstation.env
   # Change CLOUDFLARE_TUNNEL_TOKEN
   
   # Restart container
   docker-compose -f docker-compose-ztna.yml restart cloudflared
   ```

2. **Network connectivity:**
   ```bash
   # Test connectivity to Cloudflare
   ping 1.1.1.1
   curl https://www.cloudflare.com
   
   # Check DNS
   nslookup yourdomain.com
   ```

3. **DNS not propagated:**
   - Wait 5-10 minutes for DNS propagation
   - Verify DNS records in Cloudflare dashboard
   - Use `dig` to check: `dig ssh.yourdomain.com`

#### Issue 2: WireGuard Peer Can't Connect

**Symptoms:**
- Client shows "connecting..." but never establishes
- No handshake in `wg show`

**Diagnosis:**
```bash
sudo wg show
# Look for peer entry
# Check if "latest handshake" exists
```

**Solutions:**

1. **Firewall blocking:**
   ```bash
   # Verify UFW allows WireGuard port
   sudo ufw status | grep 51820
   
   # If missing:
   sudo ufw allow 51820/udp
   ```

2. **Wrong endpoint:**
   - Verify client config has correct `Endpoint = your.vps.public.ip:51820`
   - Check VPS public IP: `curl ifconfig.me`

3. **IP forwarding disabled:**
   ```bash
   # Check IP forwarding
   sysctl net.ipv4.ip_forward
   
   # If 0, enable:
   sudo sysctl -w net.ipv4.ip_forward=1
   echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
   ```

4. **NAT not configured:**
   ```bash
   # Check iptables NAT rule
   sudo iptables -t nat -L POSTROUTING
   
   # Should show: MASQUERADE rule for 10.13.13.0/24
   # If missing, add:
   sudo iptables -t nat -A POSTROUTING -s 10.13.13.0/24 -o eth0 -j MASQUERADE
   ```

#### Issue 3: Can't Access VNC After 2FA

**Symptoms:**
- TOTP code accepted
- But VNC connection fails

**Diagnosis:**
```bash
# Check if VNC service is running
systemctl status vncserver-hossein@1

# Check VNC port listening
sudo netstat -tlnp | grep 1370
```

**Solutions:**

1. **VNC service not started:**
   ```bash
   # Start VNC service
   sudo systemctl start vncserver-hossein@1
   sudo systemctl enable vncserver-hossein@1
   ```

2. **Wrong port in tunnel config:**
   - Verify Cloudflare tunnel config
   - Should point to correct localhost port (1370 for hossein)

3. **Firewall blocking locally:**
   ```bash
   # Check local firewall
   sudo iptables -L INPUT | grep 1370
   
   # Allow if needed (local only)
   sudo iptables -A INPUT -p tcp --dport 1370 -s 127.0.0.1 -j ACCEPT
   ```

#### Issue 5: Database Corruption

**Symptoms:**
- `query_users.sh` fails with SQLite errors
- `add_wg_peer.sh` can't insert records

**Solutions:**

1. **Check database integrity:**
   ```bash
   sqlite3 /var/lib/ztna/users.db "PRAGMA integrity_check;"
   ```

2. **Restore from backup:**
   ```bash
   # List backups
   ls -lh /var/lib/ztna/backups/
   
   # Restore latest
   sudo cp /var/lib/ztna/backups/ztna-backup-*.tar.gz /tmp/
   cd /tmp
   sudo tar -xzf ztna-backup-*.tar.gz
   sudo cp tmp/var/lib/ztna/users.db /var/lib/ztna/users.db
   
   # Verify
   sqlite3 /var/lib/ztna/users.db "SELECT * FROM users;"
   ```

3. **Rebuild database (last resort):**
   ```bash
   # Backup existing (corrupted) DB
   sudo mv /var/lib/ztna/users.db /var/lib/ztna/users.db.corrupted
   
   # Recreate from setup script
   # Run the database initialization section from setup_server.sh
   ```

### Performance Monitoring

**System resources:**
```bash
# CPU and memory
htop

# Disk usage
df -h

# Network bandwidth
iftop
```

**WireGuard bandwidth:**
```bash
# Install vnstat
sudo apt install vnstat

# Monitor interface
vnstat -i wg0
```

**Docker resource usage:**
```bash
docker stats

# Shows CPU, memory, network I/O for each container
```

### Log Files

**Important log locations:**
```bash
# Cloudflare tunnel
docker logs cloudflared

# WireGuard
docker logs wireguard
journalctl -u wg-quick@wg0

# Shadowsocks
docker logs shadowsocks

# System logs
/var/log/syslog
/var/log/auth.log  # SSH attempts

# VNC logs
~/.vnc/*.log

# Custom scripts
/var/log/ztna/  # If logging enabled
```

---

## Security Best Practices

### 1. Regular Updates

```bash
# Update system packages monthly
sudo apt update && sudo apt upgrade -y

# Update Docker images quarterly
docker-compose -f docker-compose-ztna.yml pull
docker-compose -f docker-compose-ztna.yml up -d

# Update cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared
```

### 2. Password Management

- **Use strong, unique passwords** for:
  - Root/sudo
  - VNC users
  - Shadowsocks
  - L2TP VPN
  - Database encryption (if implemented)

- **Store passwords securely:**
  - Use password manager (1Password, Bitwarden)
  - Encrypt `workstation.env` file
  - Never commit passwords to git

### 3. Rotate Credentials

**Every 90 days:**
- Change Shadowsocks password
- Regenerate Cloudflare tunnel token
- Update VNC passwords
- Rotate TOTP secrets (re-enroll devices)

### 4. Audit Logs

```bash
# Check SSH login attempts
sudo cat /var/log/auth.log | grep sshd

# Check Cloudflare Access logs
# (in Cloudflare dashboard → Zero Trust → Logs → Access)

# Check WireGuard connections
sudo ./query_users.sh
# Select option: View audit logs
```

### 5. Principle of Least Privilege

- **Admin access:** Only for trusted personnel
- **User access:** VPN only, no SSH/VNC
- **Service accounts:** Minimal permissions
- **Firewall:** Only open required ports

### 6. Disaster Recovery Plan

1. **Document all credentials** securely
2. **Test backup restoration** quarterly
3. **Have secondary admin** with access
4. **Keep offline copy** of tunnel token
5. **Document recovery steps**

---

## FAQ

### Q: Can I use WireGuard and Shadowsocks simultaneously?

**A:** Yes! Users can have both configured. WireGuard for normal use (faster), Shadowsocks as backup when WireGuard gets blocked.

Client can switch between them as needed.

### Q: How many users can this setup handle?

**A:** Depends on VPS specs:
- **2 CPU, 4GB RAM:** ~20-30 concurrent WireGuard users
- **4 CPU, 8GB RAM:** ~50-75 concurrent users
- **8 CPU, 16GB RAM:** ~150+ concurrent users

Shadowsocks and Cloudflare Tunnel add minimal overhead.

### Q: What if Cloudflare blocks my region?

**A:** Admins can still access via:
1. Direct SSH (if port 22 is open without Cloudflare)
2. VPN into another country → then access Cloudflare URLs
3. Emergency backdoor: Keep one SSH key-based access without Cloudflare

### Q: Can I use custom domain for WireGuard/Shadowsocks?

**A:** WireGuard uses IP:port directly (can't use domain due to UDP).

Shadowsocks can use domain:
- Create DNS A record pointing to VPS
- Use domain in client config instead of IP
- Enable Cloudflare proxy for obfuscation

### Q: How do I handle device theft/loss?

**Admin device:**
1. Immediately revoke device from Cloudflare Zero Trust dashboard
2. Device will lose access within minutes
3. Re-enroll with new device

**User device (WireGuard):**
1. Run: `sudo ./query_users.sh`
2. Select option 3: Remove peer
3. Enter username
4. Connection terminates immediately

### Q: Can I integrate with existing LDAP/Active Directory?

**A:** Yes, Cloudflare Access supports SAML/OIDC:
- Configure identity provider in Zero Trust dashboard
- Connect to Azure AD, Okta, Google Workspace, etc.
- Users authenticate with corporate credentials
- 2FA can come from IdP instead of Cloudflare

### Q: What's the latency impact?

- **Cloudflare Tunnel (admin):** +5-15ms (routed through Cloudflare edge)
- **WireGuard (user):** +1-5ms (direct VPS connection)
- **Shadowsocks (user):** +2-10ms (TCP overhead)

WireGuard is fastest, Cloudflare Tunnel adds latency but provides security.

### Q: Can I host other services through the tunnel?

**A:** Yes! Add more applications in Cloudflare dashboard:
- Web servers (HTTP/HTTPS)
- Databases (with Access policies)
- Internal tools
- APIs

All protected with same 2FA + device posture checks.

---

## Conclusion

You now have a production-ready **Cloudflare Zero Trust VPS** with:

✅ **Admin tier:** SSH/VNC access with TOTP 2FA + device whitelisting
✅ **User tier:** WireGuard VPN with automated provisioning
✅ **Iran bypass:** Shadowsocks on port 443 with DPI resistance
✅ **Management tools:** Scripts for user provisioning, monitoring, backups
✅ **Security:** Zero Trust architecture, encrypted tunnels, audit logs
✅ **Reliability:** Automated backups, health checks, failover options

**Next steps:**
1. Provision your first admin device
2. Test VNC access through Cloudflare
3. Add first WireGuard user
4. Set up automated backups
5. Monitor and optimize

**Support:**
- Cloudflare Zero Trust docs: https://developers.cloudflare.com/cloudflare-one/
- WireGuard documentation: https://www.wireguard.com/
- Shadowsocks wiki: https://shadowsocks.org/

---

**Last Updated:** January 21, 2026  
**Version:** 1.0.0  
**Author:** Infrastructure Team
