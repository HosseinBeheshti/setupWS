# Cloudflare Zero Trust Network Access (ZTNA)

Replace your VPN with **Cloudflare One Agent + WARP Connector**.

> **🚀 What You Get:**  
> **System-wide VPN Replacement** - ALL your device traffic (web, DNS, SSH, games, apps, every protocol) routes through your VPS using **Gateway with WARP** mode. Your entire system appears to be at your VPS location. This is NOT just a web proxy - it's a complete VPN replacement that works on all platforms without conflicts.

> **📚 Quick Start Guides:**
> - **[QUICK-REFERENCE.md](QUICK-REFERENCE.md)** - Essential config & 30-second verification
> - **[SYSTEM-WIDE-ROUTING.md](SYSTEM-WIDE-ROUTING.md)** - Complete setup guide & troubleshooting

## Architecture Overview

```
┌───────────────────────────────────────────────────────────────┐
│                    Cloudflare Zero Trust                      │
│                                                               │
│  Admin Users                          Regular Users           │
│  ┌──────────────┐                    ┌──────────────┐         │
│  │ Cloudflare   │                    │ Cloudflare   │         │
│  │  One Agent   │                    │  One Agent   │         │
│  └──────┬───────┘                    └──────┬───────┘         │
│         │                                   │                 │
│         │ Authenticated                     │ Authenticated   │
│         ▼                                   ▼                 │
│  ┌──────────────┐                    ┌──────────────┐         │
│  │   Gateway    │                    │   Gateway    │         │
│  │   Policy:    │                    │   Policy:    │         │
│  │   ADMIN      │                    │   USER       │         │
│  └──────┬───────┘                    └──────┬───────┘         │
│         │                                   │                 │
│         │ Access VNC                        │ Route Traffic   │
│         ▼                                   ▼                 │
│  ┌──────────────┐                    ┌──────────────┐         │
│  │  Cloudflare  │                    │     WARP     │         │
│  │    Tunnel    │                    │  Connector   │         │
│  └──────┬───────┘                    └──────┬───────┘         │
└─────────┼───────────────────────────────────┼─────────────────┘
          ▼                                   ▼
     ┌───────────┐                        ┌───────────┐
     │    VPS    │                        │    VPS    │
     │ SSH:22    │                        │  Gateway  │
     │ VNC:5901  │                        │  Routes   │
     └───────────┘                        └───────────┘
```

## Two-Tier Access Control

### Admin Users 🔐
**Policy: SSH & VNC Access + System-wide Traffic Routing**
- **What they get**: 
  - SSH terminal access
  - Remote desktop access via VNC
  - **ALL system traffic** (web, DNS, applications) routed through VPS
- **How**: 
  - SSH/VNC: Cloudflare Tunnel → SSH port 22 & VNC port 5901
  - Traffic: Gateway with WARP mode routes **every connection** through VPS
- **Authentication**: Gmail with One-time PIN
- **Device checks**: OS version, firewall, disk encryption
- **Access method**: 
  - SSH: `cloudflared access ssh ssh.yourdomain.com`
  - VNC: Browser-based VNC viewer at `vnc-admin.yourdomain.com`
  - System connections: ALL traffic exits via VPS IP

**Use case**: System administrators need full access to VPS + complete system-wide traffic routing

### Regular Users 🌐
**Policy: System-wide Traffic Routing Only**
- **What they get**: 
  - **ALL system traffic** routed through VPS (web, DNS, applications)
  - NO administrative access
- **How**: 
  - Gateway with WARP mode routes **every connection** through VPS
  - Cannot access SSH or VNC
- **Authentication**: Gmail with One-time PIN
- **Device checks**: OS version, firewall, disk encryption
- **Exit IP**: VPS location (your VPS IP)
- **Traffic types**: HTTP, HTTPS, DNS, FTP, SSH, all protocols

**Use case**: Users need complete system-wide traffic routing through VPS exit point, without server access

---

## Benefits

✅ **Single App**: Cloudflare One Agent for both admin and users  
✅ **All Platforms**: Desktop (Windows/macOS/Linux) + Mobile (Android/iOS)  
✅ **No VPN Conflicts**: One app, no dual-VPN issues  
✅ **Identity-based**: Gmail authentication, no shared keys  
✅ **Device Posture**: Automatic security checks  
✅ **System-wide Routing**: ALL traffic (not just web) routes through VPS  
✅ **VPS Exit IP**: All connections exit with your VPS IP  
✅ **Zero config files**: No VPN configs to manage  
✅ **Gateway with WARP**: Full tunnel mode for complete traffic control  

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Part 1: Cloudflare Zero Trust Setup](#part-1-cloudflare-zero-trust-setup)
  - [1.1 Configure Identity Provider](#11-configure-identity-provider)
  - [1.2 Enable Device Enrollment](#12-enable-device-enrollment)
  - [1.2.1 Configure Gateway with WARP Mode](#121-configure-gateway-with-warp-mode-system-wide-routing)
  - [1.3 Create Device Posture Checks](#13-create-device-posture-checks)
  - [1.4 Create Gateway Policies](#14-create-gateway-policies)
  - [1.5 Create Cloudflare Tunnel](#15-create-cloudflare-tunnel)
  - [1.6 Create Access Applications](#16-create-access-applications)
- [Part 2: VPS Server Setup](#part-2-vps-server-setup)
  - [2.1 Run Automated Setup](#21-run-automated-setup)
  - [2.2 Register WARP Connector](#22-register-warp-connector)
  - [2.3 Configure Split Tunnels](#23-configure-split-tunnels)
- [Part 3: Client Setup](#part-3-client-setup)
  - [3.1 Install Cloudflare One Agent](#31-install-cloudflare-one-agent)
  - [3.2 Authenticate](#32-authenticate)
- [Part 4: Verification](#part-4-verification)
- [How It All Works Together](#how-it-all-works-together)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### VPS Server
- **OS**: Ubuntu 24.04 LTS
- **RAM**: 2GB minimum
- **Public IPv4**: Required
- **Your VPS IP**: `65.109.210.232`

### Cloudflare Account
- Free Cloudflare account
- Zero Trust: **Free tier (50 users)**
- Domain managed by Cloudflare
- **Your team name**: `noise-ztna`

### Admin Gmail Addresses
Create a list of admin emails (example):
- `admin1@gmail.com`
- `admin2@gmail.com`

---

## Part 1: Cloudflare Zero Trust Setup

### 1.1 Configure Identity Provider

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to: **Integrations → Identity providers**
3. Click **Add an identity provider**
4. Select: **One-time PIN**

---

### 1.2 Enable Device Enrollment

1. Go to: **Team & Resources → Devices Settings**
3. Click: **Device enrollment**
3. Click: **Manage**
4. Under **Device enrollment permissions**, click **Add a rule**
5. Configure:
   - **Rule name**: `Allow Gmail Users`
   - **Rule action**: `Allow`
   - **Selector**: `Emails ending in`
   - **Value**: `gmail.com`
   - Click **Save**

---

### 1.2.1 Configure Gateway with WARP Mode (System-wide Routing)

**CRITICAL**: This ensures ALL traffic (not just web) routes through your VPS.

1. Go to: **Settings → WARP Client → Device settings**
2. Click: **Manage** on the **Default** profile
3. Scroll to: **Service mode**
4. Verify it's set to: **Gateway with WARP** (this is the default)
5. Under **Device tunnel protocol**, ensure: **MASQUE** or **WireGuard**
6. Click **Save profile**

**What this enables:**
- ✅ DNS filtering through Gateway
- ✅ Network traffic routing (all protocols)
- ✅ HTTP/HTTPS traffic inspection
- ✅ Complete system-wide traffic control

**Other modes (DON'T use these):**
- ❌ Gateway with DoH: DNS only, no network traffic
- ❌ Proxy mode: Only traffic sent to localhost proxy
- ❌ Secure Web Gateway without DNS: Network/HTTP only, no DNS

---

### 1.3 Create Device Posture Checks

1. Go to: **Reusable components → Posture checks**
2. Click: **Add new**

#### OS Version Check
- **Check name**: `OS Version Check`
- **Check type**: `OS version`
- **Operating system**: Select all (macOS, Windows, Linux, Android, iOS)
- **Operator**: `>=`
- **Version**:
  - macOS: `13.0`
  - Windows: `10.0.19041`
  - Linux: `5.0`
  - Android: `10.0`
  - iOS: `15.0`
- Click **Save**

#### Firewall Check
- **Check name**: `Firewall Enabled`
- **Check type**: `Firewall`
- **Enabled**: ✅
- Click **Save**

#### Disk Encryption Check
- **Check name**: `Disk Encryption`
- **Check type**: `Disk encryption`
- **Encryption detected**: ✅
- Click **Save**

---

### 1.4 Create Gateway Policies

Create TWO distinct policies: one for admins, one for regular users.

#### Policy 1: Admin Policy (SSH/VNC Access + System-wide Traffic Routing)

This policy allows admins to:
- Access SSH and VNC via Cloudflare Tunnel
- Route **ALL system traffic** (DNS, Network, HTTP) through VPS

1. Go to: **Traffic policies → Firewall policies → Network** tab
2. Click: **Add a policy**
3. Configure:
   - **Policy name**: `Admin - Full Access + System-wide Routing`
   - **Selector**: `User Email`
   - **Operator**: `is`
   - **Value**: `admin1@gmail.com`
   - Click **Or** to add more admin emails: `admin2@gmail.com`, etc.
   - **Action**: `Allow`
4. Under **Device posture**, add:
   - ✅ OS Version Check
   - ✅ Firewall Enabled
   - ✅ Disk Encryption
5. Click **Save**

**What this enables for admins:**
- ✅ SSH access via `ssh.yourdomain.com`
- ✅ VNC access via `vnc-admin.yourdomain.com`
- ✅ **ALL system traffic** routes through WARP Connector (VPS exit IP)
- ✅ DNS queries, network connections, HTTP/HTTPS, all protocols

#### Policy 2: User Policy (System-wide Traffic Routing Only)

This policy allows regular users to:
- Route **ALL system traffic** (DNS, Network, HTTP) through VPS
- NO SSH/VNC access

1. Click: **Add a policy**
2. Configure:
   - **Policy name**: `User - System-wide Routing Only`
   - **Selector**: `User Email`
   - **Operator**: `matches regex`
   - **Value**: `.*@gmail\.com` (matches all Gmail users)
   - **Action**: `Allow`
3. Under **Device posture**, add:
   - ✅ OS Version Check
   - ✅ Firewall Enabled
   - ✅ Disk Encryption
4. Click **Save**

**What this enables for users:**
- ✅ **ALL system traffic** routes through WARP Connector (VPS exit IP)
- ✅ DNS queries, network connections, HTTP/HTTPS, all protocols
- ❌ NO SSH access
- ❌ NO VNC access

**Result:** 
- **Admins**: SSH + VNC access + system-wide traffic routing through VPS
- **Users**: System-wide traffic routing through VPS only

---

### 1.5 Create Cloudflare Tunnel

This provides admin access to VNC services.

#### Step 1: Create Tunnel

1. Go to: **Networks → Tunnels**
2. Click: **Create a tunnel**
3. Select: **Cloudflared**
4. **Tunnel name**: `vps-admin-services`
5. Click **Save tunnel**

#### Step 2: Install on VPS

The setup script will install cloudflared. Alternatively, manually:

```bash
sudo cloudflared service install <YOUR_TUNNEL_TOKEN>
```

#### Step 3: Configure Routes

Add SSH and VNC routes in tunnel dashboard:

**SSH Access:**
- **Subdomain**: `ssh`
- **Domain**: `yourdomain.com`
- **Service**: `ssh://localhost:22`
- Click **Save**

**VNC Admin:**
- **Subdomain**: `vnc-admin`
- **Domain**: `yourdomain.com`
- **Service**: `http://localhost:5901`
- Click **Save**

---

### 1.6 Create Access Applications

Protect SSH and VNC services with admin-only access.

#### SSH Access Application

1. Go to: **Access → Applications**
2. Click: **Add an application**
3. Select: **Self-hosted**
4. Configure:
   - **Application name**: `VPS SSH`
   - **Application domain**: `ssh.yourdomain.com`
   - Click **Next**

5. Add policy:
   - **Policy name**: `Admins Only`
   - **Action**: `Allow`
   - **Selector**: `User Email`
   - **Operator**: `is`
   - **Value**: Add all admin emails
   - Click **Next**

6. Click **Add application**

#### VNC Access Application

1. Click: **Add an application**
2. Select: **Self-hosted**
3. Configure:
   - **Application name**: `VNC Admin`
   - **Application domain**: `vnc-admin.yourdomain.com`
   - Click **Next**

4. Add policy:
   - **Policy name**: `Admins Only`
   - **Action**: `Allow`
   - **Selector**: `User Email`
   - **Operator**: `is`
   - **Value**: Add all admin emails
   - Click **Next**

5. Click **Add application**

**Result:** Only admin emails can access SSH and VNC services.

---

## Part 2: VPS Server Setup

### 2.1 Run Automated Setup

SSH into your VPS and run:

```bash
# Clone repository
git clone https://github.com/HosseinBeheshti/setupWS.git
cd setupWS

# Edit configuration
vim workstation.env

# Run setup
sudo ./setup_server.sh
```

This script will:
- Install WARP Connector
- Setup VNC server with users
- Configure firewall
- Install cloudflared

---

### 2.2 Register WARP Connector

After setup completes:

```bash
# Register with Cloudflare
sudo warp-cli registration new
```

Follow the prompts to link to your Cloudflare Zero Trust account.

**Verify:**
```bash
sudo warp-cli status
# Should show: Status: Connected
```

---

### 2.3 Configure Split Tunnels

Prevent routing loops:

1. Go to: **Settings → WARP Client → Device settings → Manage → Default**
2. Scroll to: **Split Tunnels**
3. Click: **Manage**
4. Set mode: **Exclude IPs and domains**
5. Add exclusions:
   ```
   65.109.210.232/32    (your VPS IP)
   10.0.0.0/8
   172.16.0.0/12
   192.168.0.0/16
   ```
6. Click **Save**

---

## Part 3: Client Setup

### 3.1 Install Cloudflare One Agent

**Android:**
- Package: `com.cloudflare.cloudflareoneagent`
- [Download from Play Store](https://play.google.com/store/apps/details?id=com.cloudflare.cloudflareoneagent)

**iOS:**
- App ID: `id6443476492`
- [Download from App Store](https://apps.apple.com/app/id6443476492)

**Windows/macOS/Linux:**
- Download: [https://1.1.1.1/](https://1.1.1.1/)

⚠️ **IMPORTANT**: Use **Cloudflare One Agent** (NOT the old 1.1.1.1 consumer app)

---

### 3.2 Authenticate

After installing:

1. Open **Cloudflare One Agent**
2. Go to: **Settings → Account**
3. Click: **Login with Cloudflare Zero Trust**
4. Enter team name: `noise-ztna`
5. Select: **One-time PIN**
6. Enter your Gmail address
7. Check Gmail for PIN
8. Enter PIN to authenticate

**Device Posture Check:**
The app will automatically check OS version, firewall, and disk encryption.

**Connect:**
Toggle connection **ON**.

---

## Part 4: Verification

### For Admin Users

**Check Exit IP (HTTP traffic):**
```bash
curl ifconfig.me
```

**Expected:** `65.109.210.232` (your VPS IP)

**Check DNS Resolution:**
```bash
nslookup cloudflare.com
# DNS server should be Gateway resolver: 172.64.36.1 or 172.64.36.2
```

**Check All Traffic Routing:**
```bash
# Test FTP (if available)
curl ftp://ftp.example.com

# Test SSH to external server
ssh user@external-server.com
# Connection goes through VPS

# Any protocol routes through VPS
```

All system traffic (DNS, HTTP, SSH, FTP, everything) routes through your VPS!

**Access SSH:**

First, install cloudflared on your local machine:

```bash
# macOS (Homebrew)
brew install cloudflared

# Linux
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# Windows (download from GitHub releases)
# https://github.com/cloudflare/cloudflared/releases
```

Then connect via SSH:

```bash
cloudflared access ssh ssh.yourdomain.com
```

You'll be prompted to authenticate in browser (Gmail + PIN), then SSH session opens.

**Access VNC:**
Open browser and visit:
- `https://vnc-admin.yourdomain.com`

You'll be prompted to authenticate (Gmail + PIN), then access VNC.

---

### For Regular Users

**Check Exit IP:**
```bash
curl ifconfig.me
```

**Expected:** `65.109.210.232` (your VPS IP)

**Check DNS Resolution:**
```bash
nslookup cloudflare.com
# DNS server should be Gateway resolver: 172.64.36.1 or 172.64.36.2
```

**Verify System-wide Routing:**
- Open any app on your device
- All connections (web, games, messaging, etc.) route through VPS
- Every DNS query goes through Gateway
- Every network connection exits with VPS IP

**This applies to:**
- ✅ Regular users: Complete system-wide traffic routing (all protocols)
- ✅ Admin users: System-wide traffic routing + SSH/VNC access

---

### For VPS Admin

**Check WARP Connector:**
```bash
sudo warp-cli status
# Status: Connected

sudo warp-cli account
# Shows account info
```

**Check enrolled devices:**
1. Go to: **My Team → Devices**
2. View all enrolled devices with user emails

---

## How It All Works Together

### Architecture Layers

**Layer 0: WARP Service Mode (Gateway with WARP)**
- Configured in Device Profile settings
- **Mode**: Gateway with WARP (default)
- **What it does**: Routes ALL traffic (DNS, Network, HTTP) through Cloudflare Gateway
- **Result**: Complete system-wide traffic control, not just web browsing

**Layer 1: Gateway Network Policies (Traffic Routing)**
- Controls who can route traffic through WARP Connector
- **Admin Policy**: Specific admin emails → Allow system-wide traffic routing
- **User Policy**: All Gmail users → Allow system-wide traffic routing
- **Result**: ALL users route complete system traffic through VPS

**Layer 2: Access Applications (Service Access)**
- Controls who can access SSH and VNC via Cloudflare Tunnel
- **SSH Application**: Only admin emails → Allow SSH access
- **VNC Application**: Only admin emails → Allow VNC access
- **Result**: Only admins can access server services

### Traffic Flow Breakdown

**For Admin Users:**
```
Admin Device with Cloudflare One Agent (Gateway with WARP mode)
│
├─→ ALL System Traffic (HTTP, DNS, SSH, FTP, games, apps, everything)
│   └─→ Gateway with WARP → WARP Connector → VPS → Internet (Exit IP: VPS)
│
├─→ SSH Access to VPS (terminal)
│   └─→ Cloudflare Tunnel → VPS:22 (authenticated via Access App)
│
└─→ VNC Access to VPS (GUI)
    └─→ Cloudflare Tunnel → VPS:5901 (authenticated via Access App)
```

**For Regular Users:**
```
User Device with Cloudflare One Agent (Gateway with WARP mode)
│
└─→ ALL System Traffic (HTTP, DNS, SSH, FTP, games, apps, everything)
    └─→ Gateway with WARP → WARP Connector → VPS → Internet (Exit IP: VPS)
    
    ❌ SSH Access to VPS: Denied by Access Application
    ❌ VNC Access to VPS: Denied by Access Application
```

### Why This Design Works

1. **Gateway with WARP Mode**: Device profile set to route ALL traffic (DNS + Network + HTTP)
2. **Single App**: Both admins and users install the same Cloudflare One Agent
3. **System-wide Routing**: Gateway Network Policy ensures ALL users route complete system traffic
4. **Selective Access**: Access Applications restrict SSH/VNC to admins only
5. **Zero Trust**: Every access requires authentication + device posture check
6. **Platform Agnostic**: Works on Desktop and Mobile without VPN conflicts
7. **True VPN Replacement**: Every connection (not just web) goes through VPS

---

## Troubleshooting

### WARP Connector Not Connected

```bash
# Restart service
sudo systemctl restart warp-svc

# Reconnect
sudo warp-cli connect

# Check logs
sudo journalctl -u warp-svc -f
```

---

### User Traffic Not Routing Through VPS

**Check Service Mode (Most Common Issue):**
1. Go to: **Settings → WARP Client → Device settings**
2. Click: **Manage** on your device profile
3. Verify **Service mode** is set to: **Gateway with WARP** (NOT Proxy mode or DoH)
4. This is CRITICAL for system-wide traffic routing

**Check Gateway Policy:**
1. Go to: **Traffic policies → Firewall policies → Network**
2. Verify these policies exist:
   - `Admin - Full Access + System-wide Routing`
   - `User - System-wide Routing Only`
3. Check user email matches one of the policies

**Check Split Tunnels:**
1. Verify VPS IP is excluded: `65.109.210.232/32`
2. Verify private networks are excluded
3. Mode should be: **Exclude IPs and domains**

**Verify on Client:**
```bash
# Check DNS is using Gateway
nslookup cloudflare.com
# Should show Gateway DNS: 172.64.36.1 or 172.64.36.2

# Check exit IP
curl ifconfig.me
# Should show VPS IP: 65.109.210.232
```

**Check WARP Connection Status:**
On client device:
- Open Cloudflare One Agent
- Verify status shows: **Connected**
- Check Settings → Preferences → Gateway with WARP

---

### Admin Cannot Access VNC

**Check Access Application:**
1. Go to: **Access → Applications**
2. Verify admin email is in policy
3. Check tunnel is connected:
   ```bash
   sudo systemctl status cloudflared
   ```

---

### Admin Cannot Access SSH

**Check Cloudflared on Local Machine:**
```bash
# Verify cloudflared is installed
cloudflared --version

# Test SSH access with verbose logging
cloudflared access ssh --verbose ssh.yourdomain.com
```

**Check Tunnel Route:**
1. Go to: **Networks → Tunnels → vps-admin-services**
2. Verify SSH route exists: `ssh://localhost:22`
3. Check tunnel is running on VPS:
   ```bash
   sudo systemctl status cloudflared
   ```

**Check Access Application:**
1. Go to: **Access → Applications → VPS SSH**
2. Verify admin email is in policy

---

### Device Posture Check Fails

**OS Version:**
Update your OS to meet minimum requirements.

**Firewall:**
- Windows: Settings → Security → Firewall → Turn ON
- macOS: System Preferences → Firewall → Turn ON
- Linux: `sudo ufw enable`

**Disk Encryption:**
- Windows: Enable BitLocker
- macOS: Enable FileVault
- Linux: Use LUKS

---

## Policy Summary

| User Type | Authentication | SSH/VNC Access | Traffic Routing | DNS | Exit IP |
|-----------|---------------|----------------|-----------------|-----|---------|
| **Admin** | Gmail + PIN | ✅ SSH + VNC via Tunnel | ✅ System-wide (all protocols) | ✅ Gateway | VPS IP |
| **Regular User** | Gmail + PIN | ❌ No server access | ✅ System-wide (all protocols) | ✅ Gateway | VPS IP |

**Key Points:**
- ✅ **Gateway with WARP mode** ensures ALL traffic (not just web) routes through VPS
- ✅ **ALL users** route complete system traffic (DNS + Network + HTTP) through WARP Connector
- ✅ **ALL users** see VPS IP as their exit IP for every connection
- ✅ **Only admins** can access SSH and VNC services on VPS
- ✅ Works for ALL applications and protocols (web, games, SSH, FTP, everything)

---

## Monitoring

### View Enrolled Devices
1. Go to: **My Team → Devices**
2. See:
   - Device name
   - User email
   - OS version
   - Last seen
   - Posture status

### View Traffic Logs
1. Go to: **Logs → Gateway → Activity**
2. Filter by:
   - User email
   - Device
   - Time range

### Analytics
1. Go to: **Analytics → Gateway**
2. View:
   - Traffic volume
   - Top users
   - Top destinations

---

## Advanced: L2TP VPN for Infrastructure

If you need L2TP VPN for infrastructure management (virtual routers, xRDP):

```bash
sudo ./setup_l2tp.sh
```

See the [L2TP appendix in old README](README.md#appendix-l2tp-vpn-setup) for configuration.

---

## What You've Built

✅ **Two-tier access control with unified traffic routing**:
- **Admins**: SSH + VNC access + web traffic through VPS
- **Users**: Web traffic through VPS only (no server access)

✅ **Cloudflare One Agent**: Single app for all users

✅ **WARP Connector**: Routes ALL user traffic through VPS

✅ **Universal VPS Exit IP**: Both admins and users show VPS IP

✅ **Zero Trust**: Gmail authentication + device posture

✅ **All platforms**: Desktop + Mobile

✅ **No VPN conflicts**: One app solution

---

## Support

- **Cloudflare Docs**: [https://developers.cloudflare.com/cloudflare-one/](https://developers.cloudflare.com/cloudflare-one/)
- **WARP Connector**: [https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/private-net/warp-connector/](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/private-net/warp-connector/)
- **Replace VPN Guide**: [https://developers.cloudflare.com/learning-paths/replace-vpn/](https://developers.cloudflare.com/learning-paths/replace-vpn/)

---

## License

MIT License - See [LICENSE](LICENSE) file for details.
