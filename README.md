# Cloudflare Zero Trust Network Access (ZTNA)

Replace your VPN with **Cloudflare One Agent + WARP Connector**.

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
**Policy: SSH & VNC Access + Traffic Routing**
- **What they get**: 
  - SSH terminal access
  - Remote desktop access via VNC
  - ALL web traffic routed through VPS
- **How**: 
  - SSH/VNC: Cloudflare Tunnel → SSH port 22 & VNC port 5901
  - Traffic: WARP Connector routes all traffic through VPS
- **Authentication**: Gmail with One-time PIN
- **Device checks**: OS version, firewall, disk encryption
- **Access method**: 
  - SSH: `cloudflared access ssh ssh.yourdomain.com`
  - VNC: Browser-based VNC viewer at `vnc-admin.yourdomain.com`
  - Web browsing: All traffic exits via VPS IP

**Use case**: System administrators need full access to VPS + secure internet routing

### Regular Users 🌐
**Policy: Web Traffic Routing Only**
- **What they get**: 
  - Internet access through VPS
  - NO administrative access
- **How**: 
  - WARP Connector routes ALL traffic through VPS
  - Cannot access SSH or VNC
- **Authentication**: Gmail with One-time PIN
- **Device checks**: OS version, firewall, disk encryption
- **Exit IP**: VPS location (your VPS IP)

**Use case**: Users need secure internet access with VPS exit point, without server access

---

## Benefits

✅ **Single App**: Cloudflare One Agent for both admin and users  
✅ **All Platforms**: Desktop (Windows/macOS/Linux) + Mobile (Android/iOS)  
✅ **No VPN Conflicts**: One app, no dual-VPN issues  
✅ **Identity-based**: Gmail authentication, no shared keys  
✅ **Device Posture**: Automatic security checks  
✅ **VPS Exit IP**: All user traffic exits through your VPS  
✅ **Zero config files**: No VPN configs to manage
✅ **Unified routing**: Both admins and users route traffic through WARP  

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Part 1: Cloudflare Zero Trust Setup](#part-1-cloudflare-zero-trust-setup)
  - [1.1 Configure Identity Provider](#11-configure-identity-provider)
  - [1.2 Enable Device Enrollment](#12-enable-device-enrollment)
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
2. Navigate to: **Settings → Authentication**
3. Under **Login methods**, click **Add new**
4. Select: **One-time PIN**
5. Configure:
   - **Name**: `Gmail One-time PIN`
   - Click **Save**

---

### 1.2 Enable Device Enrollment

1. Go to: **Settings → WARP Client** tab
2. Scroll to: **Device enrollment**
3. Click: **Manage**
4. Under **Device enrollment permissions**, click **Add a rule**
5. Configure:
   - **Rule name**: `Allow Gmail Users`
   - **Rule action**: `Allow`
   - **Selector**: `Emails ending in`
   - **Value**: `gmail.com`
   - Click **Save**

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

#### Policy 1: Admin Policy (SSH/VNC Access + Traffic Routing)

This policy allows admins to:
- Access SSH and VNC via Cloudflare Tunnel
- Route ALL web traffic through WARP Connector

1. Go to: **Traffic policies → Firewall policies → Network** tab
2. Click: **Add a policy**
3. Configure:
   - **Policy name**: `Admin - Full Access + WARP Routing`
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
- ✅ All web traffic routes through WARP Connector (VPS exit IP)

#### Policy 2: User Policy (Traffic Routing Only)

This policy allows regular users to:
- Route ALL web traffic through WARP Connector
- NO SSH/VNC access

1. Click: **Add a policy**
2. Configure:
   - **Policy name**: `User - WARP Traffic Routing Only`
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
- ✅ All web traffic routes through WARP Connector (VPS exit IP)
- ❌ NO SSH access
- ❌ NO VNC access

**Result:** 
- **Admins**: SSH + VNC access + traffic routing through VPS
- **Users**: Traffic routing through VPS only

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

**Check Exit IP (same as regular users):**
```bash
curl ifconfig.me
```

**Expected:** `65.109.210.232` (your VPS IP)

All web traffic routes through your VPS, same as regular users!

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

All web traffic now routes through your VPS!

**This applies to:**
- ✅ Regular users: Only web traffic routing
- ✅ Admin users: Web traffic routing + SSH/VNC access

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

**Layer 1: Gateway Network Policies (Traffic Routing)**
- Controls who can route traffic through WARP Connector
- **Admin Policy**: Specific admin emails → Allow traffic routing
- **User Policy**: All Gmail users → Allow traffic routing
- **Result**: ALL users route web traffic through VPS

**Layer 2: Access Applications (Service Access)**
- Controls who can access SSH and VNC via Cloudflare Tunnel
- **SSH Application**: Only admin emails → Allow SSH access
- **VNC Application**: Only admin emails → Allow VNC access
- **Result**: Only admins can access server services

### Traffic Flow Breakdown

**For Admin Users:**
```
Admin Device with Cloudflare One Agent
│
├─→ Web Traffic (browsing, apps)
│   └─→ WARP Connector → VPS → Internet (Exit IP: VPS)
│
├─→ SSH Access (terminal)
│   └─→ Cloudflare Tunnel → VPS:22 (authenticated via Access App)
│
└─→ VNC Access (GUI)
    └─→ Cloudflare Tunnel → VPS:5901 (authenticated via Access App)
```

**For Regular Users:**
```
User Device with Cloudflare One Agent
│
└─→ Web Traffic (browsing, apps)
    └─→ WARP Connector → VPS → Internet (Exit IP: VPS)
    
    ❌ SSH Access: Denied by Access Application
    ❌ VNC Access: Denied by Access Application
```

### Why This Design Works

1. **Single App**: Both admins and users install the same Cloudflare One Agent
2. **Universal Routing**: Gateway Network Policy ensures ALL users route through WARP
3. **Selective Access**: Access Applications restrict SSH/VNC to admins only
4. **Zero Trust**: Every access requires authentication + device posture check
5. **Platform Agnostic**: Works on Desktop and Mobile without VPN conflicts

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

**Check Gateway Policy:**
1. Go to: **Traffic policies → Firewall policies → Network**
2. Verify these policies exist:
   - `Admin - Full Access + WARP Routing`
   - `User - WARP Traffic Routing Only`
3. Check user email matches one of the policies

**Check Split Tunnels:**
1. Verify VPS IP is excluded
2. Verify private networks are excluded

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

| User Type | Authentication | SSH/VNC Access | Traffic Routing | Exit IP |
|-----------|---------------|----------------|-----------------|---------|
| **Admin** | Gmail + PIN | ✅ SSH + VNC via Tunnel | ✅ All traffic via WARP | VPS IP |
| **Regular User** | Gmail + PIN | ❌ No server access | ✅ All traffic via WARP | VPS IP |

**Key Points:**
- ✅ **ALL users** (admin + regular) route web traffic through WARP Connector
- ✅ **ALL users** see VPS IP as their exit IP
- ✅ **Only admins** can access SSH and VNC
- ✅ Gateway Network Policy controls both traffic routing AND access permissions

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
