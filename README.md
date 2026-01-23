# Cloudflare Zero Trust + WireGuard VPN Setup Guide

This guide provides complete step-by-step instructions for deploying **Cloudflare Zero Trust** as an authentication layer for **WireGuard VPN** on your VPS.

## 🎯 Architecture: Two-Layer Security Model

**Layer 1: Cloudflare One Agent (Zero Trust) - AUTHENTICATION & ACCESS CONTROL**
- Authenticates user identity with 2FA
- Checks device health (OS version, firewall, encryption)
- Enforces corporate security policies
- Controls access to WireGuard service (configurable UDP port)
  - Default: 443/UDP (obfuscated for Iran - appears as HTTPS/QUIC)
  - Alternatives: 53/UDP (DNS), 123/UDP (NTP), high ports (40000-50000)
  - **Note:** Default 51820 is blocked in Iran

**Layer 2: WireGuard VPN - ACTUAL VPN TUNNEL**
- Provides secure VPN connection
- Routes internet traffic through VPS
- Masks user's IP address
- Fast, modern VPN protocol

## 🔑 Key Concept

**Cloudflare One Agent ≠ VPN**  
It's an authentication/policy enforcement tool, NOT a VPN replacement.

**Users run BOTH applications simultaneously:**
1. **Cloudflare One Agent** (runs in background) - Provides authentication
2. **WireGuard app** (user activates) - Provides VPN tunnel

**If Cloudflare One Agent is not running or user fails authentication:**
→ WireGuard connection to configured port (default 443/UDP) is **BLOCKED** by Cloudflare Gateway

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Understanding the Components](#understanding-the-components)
- [Prerequisites](#prerequisites)
- [Part 1: Cloudflare Zero Trust Setup](#part-1-cloudflare-zero-trust-setup)
  - [1.1 Configure Identity Provider with 2FA](#11-configure-identity-provider-with-2fa)
  - [1.2 Enable Device Enrollment](#12-enable-device-enrollment)
  - [1.3 Create Device Posture Checks](#13-create-device-posture-checks)
  - [1.4 Create Gateway Network Policy for WireGuard](#14-create-gateway-network-policy-for-wireguard)
  - [1.5 Create Cloudflare Tunnel](#15-create-cloudflare-tunnel)
  - [1.6 Create Access Applications for SSH/VNC](#16-create-access-applications-for-sshvnc)
- [Part 2: VPS Server Setup](#part-2-vps-server-setup)
- [Part 3: Device Enrollment (All Users)](#part-3-device-enrollment-all-users)
  - [3.1 Desktop/Laptop Enrollment](#31-desktoplaptop-enrollment)
  - [3.2 Mobile Device Enrollment](#32-mobile-device-enrollment)
- [Part 4: Using Services After Enrollment](#part-4-using-services-after-enrollment)
  - [4.1 WireGuard VPN Access](#41-wireguard-vpn-access)
  - [4.2 SSH Access](#42-ssh-access)
  - [4.3 VNC Access](#43-vnc-access)
- [Part 5: Admin Workflows](#part-5-admin-workflows)
- [Part 6: Backup & Recovery](#part-6-backup--recovery)
- [Part 7: Monitoring & Troubleshooting](#part-7-monitoring--troubleshooting)

---

## Architecture Overview

```
User Device - BOTH Apps Running Simultaneously:
┌──────────────────────────────────────────────────────────────┐
│  Application 1: Cloudflare One Agent                         │
│  Purpose: Authentication & Access Control                    │
│  Status: Connected (runs in background)                      │
│  ├─ User authenticated with 2FA: ✓                           │
│  ├─ Device posture checks passed: ✓                          │
│  └─ Grants permission to access WireGuard port               │
└──────────────────────────────────────────────────────────────┘
                         │
                         │ Authentication Active
                         ▼
┌──────────────────────────────────────────────────────────────┐
│  Application 2: WireGuard Client                             │
│  Purpose: VPN Tunnel                                         │
│  Status: User clicks "Connect"                               │
│  ├─ Connects to VPS port 443/UDP (allowed by Zero Trust)     │
│  │  (Appears as HTTPS/QUIC traffic - obfuscated)             │
│  ├─ Establishes encrypted tunnel                             │
│  └─ Routes all internet via VPS                              │
└──────────────────────────────────────────────────────────────┘
                         │
                         │ VPN Traffic
                         ▼
┌──────────────────────────────────────────────────────────────┐
│              Cloudflare Gateway (Policy Enforcement)         │
│                                                              │
│  IF (Cloudflare One Agent authenticated + posture OK)        │
│     THEN allow traffic to WireGuard port (443/UDP)           │
│  ELSE block connection                                       │
└──────────────────────────────────────────────────────────────┘
                         │
                         │ Access Granted
                         ▼
        ┌────────────────────────────────────┐
        │  VPS Server (Your Infrastructure)  │
        │                                    │
        │  ┌──────────────────────────────┐  │
        │  │ WireGuard Server (443/UDP)   │  │
        │  │  - Accepts connections       │  │
        │  │  - Routes internet traffic   │  │
        │  └──────────────────────────────┘  │
        │                                    │
        │  ┌──────────────────────────────┐  │
        │  │ Cloudflare Tunnel (SSH/VNC)  │  │
        │  │  - ssh.yourdomain.com        │  │
        │  │  - vnc-*.yourdomain.com      │  │
        │  └──────────────────────────────┘  │
        └────────────────────────────────────┘
                         │
                         ▼
                    Internet
```

### Traffic Flow

**For WireGuard VPN:**
```
Cloudflare One Agent (background) → 2FA Auth → Posture Check → Gateway Policy (Allow WireGuard port) → WireGuard Client (VPN tunnel) → Internet via VPS
```

**For SSH/VNC:**
```
Browser → 2FA Auth → Posture Check → Access Policy → Cloudflare Tunnel → SSH/VNC on VPS
```

---

## Understanding the Components

### What Each Component Does

| Component | Type | Purpose | User Interaction |
|-----------|------|---------|------------------|
| **Cloudflare One Agent** | Authentication Client | Verifies identity + device health | Install once, runs in background |
| **WireGuard** | VPN Client | Actual VPN tunnel | User clicks "Connect" when needed |
| **Cloudflare Gateway** | Cloud Service | Enforces access policies | Invisible to user |
| **cloudflared Tunnel** | Server Daemon | Exposes SSH/VNC | No user interaction |

### Critical Differences

| Feature | Cloudflare One Agent | WireGuard |
|---------|---------------------|-----------|
| **Authentication** | ✅ Yes (2FA, email) | ❌ No |
| **Device Posture** | ✅ Yes (OS, firewall, etc.) | ❌ No |
| **Policy Enforcement** | ✅ Yes | ❌ No |
| **VPN Tunnel** | ❌ No | ✅ Yes |
| **Routes Internet** | ❌ No | ✅ Yes |
| **IP Masking** | ❌ No | ✅ Yes |
| **Always Running** | ✅ Yes (background) | No (user activates) |

### Why Both Are Needed

**Cloudflare One Agent alone:**
- ❌ Cannot route internet traffic
- ❌ Cannot mask IP address
- ✅ Can authenticate users
- ✅ Can enforce policies

**WireGuard alone:**
- ✅ Can route internet traffic
- ✅ Can mask IP address
- ❌ Cannot authenticate users
- ❌ Anyone with config file can connect

**Both together:**
- ✅ Authenticates users (Cloudflare)
- ✅ Routes traffic (WireGuard)
- ✅ Enforces policies (Cloudflare)
- ✅ Provides VPN (WireGuard)
- ✅ Full Zero Trust security

### User Experience Example

**Old way (WireGuard only - INSECURE):**
```
1. User gets WireGuard config file
2. User imports into WireGuard app
3. User clicks "Connect"
4. Internet routed through VPS

❌ No identity check
❌ Anyone with config can connect
❌ No device health verification
❌ Can't revoke access remotely
```

**New way (Zero Trust + WireGuard - SECURE):**
```
1. User enrolls with Cloudflare One Agent (one-time)
   - Authenticates with 2FA
   - Device posture checks run
   
2. Cloudflare One Agent runs in background (always)
   - Continuously verifies identity
   - Monitors device health
   
3. User gets WireGuard config (from admin)

4. User opens WireGuard app and clicks "Connect"
   - Cloudflare Gateway checks: Is user authenticated?
   - If YES → Allow connection to WireGuard port (configured in workstation.env, default 443/UDP)
   - If NO → Block connection
   
5. WireGuard tunnel established
6. Internet routed through VPS

✅ Identity verified continuously
✅ Device health checked
✅ Admin can revoke access instantly
✅ Full audit log of connections
```

---

## Prerequisites

### Server Requirements

- **VPS with Ubuntu 22.04 or 24.04 LTS**
- **Minimum:** 2 CPU cores, 4GB RAM, 50GB storage
- **Root or sudo access**
- **Public IP address**
- **Open ports:** 22 (SSH), 443 (WireGuard obfuscated as HTTPS/QUIC)

### Cloudflare Requirements

- **Cloudflare account** (free tier is sufficient)
- **Domain name** pointed to Cloudflare nameservers
- **Cloudflare Zero Trust** account (free up to 50 users)

### Client Requirements

**For ALL Users - TWO applications required:**

1. **Cloudflare One Agent** (Authentication layer)
   - Desktop: https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/download-warp/
   - iOS: https://apps.apple.com/app/cloudflare-one-agent/id6443476492
   - Android: https://play.google.com/store/apps/details?id=com.cloudflare.cloudflareoneagent
   - **Note**: Download "Cloudflare One Agent" app, NOT the old "1.1.1.1: Faster Internet" consumer app

2. **WireGuard Client** (VPN layer)
   - Desktop: https://www.wireguard.com/install/
   - iOS: https://apps.apple.com/app/wireguard/id1441195209
   - Android: https://play.google.com/store/apps/details?id=com.wireguard.android

**Also Required:**
- **Authenticator app** for 2FA (Google Authenticator, Authy, Microsoft Authenticator)

**Additional for Admins:**
- **VNC client** (optional, can use browser)
- **SSH client** (optional, can use browser)

---

## Part 1: Cloudflare Zero Trust Setup

### 1.1 Configure Identity Provider with 2FA

**Navigation:** Cloudflare One Dashboard → **Integrations** → **Identity providers**

1. Click **Add new identity provider**

2. **Choose authentication method:**

   **Option A: One-Time PIN (Recommended for quick setup)**
   - Select **One-time PIN**
   - Click **Save**
   - **Important**: This method sends email codes. For stronger security, use Option B.

   **Option B: Enterprise IdP with MFA (Recommended for production)**
   - Select your IdP: **Okta**, **Microsoft Entra ID**, **Google Workspace**, etc.
   - Follow provider-specific setup instructions
   - **Critical**: Enable MFA in your IdP settings (Okta/Azure/Google)
   - Cloudflare will validate that users authenticated with MFA
   - Click **Save** and **Test** to verify

3. **Verify 2FA is enforced:**
   - In your Identity Provider settings, ensure MFA is **required** (not optional)
   - Users should be prompted for 2FA every login

---

### 1.2 Enable Device Enrollment

**Navigation:** In [Cloudflare One](https://one.dash.cloudflare.com/), go to **Settings** → **WARP Client** → **Device enrollment**

#### Step 1: Configure Device Enrollment Permissions

1. In the **Device enrollment** section, click **Manage** under **Device enrollment permissions**

2. In the **Policies** tab:
   - Click **Add a policy** button
   - **Policy name**: Enter a name (e.g., "Allow Gmail Users with OTP")
   - **Action**: Select **Allow** from dropdown
   - **Session duration**: Leave default (24 hours)

3. **Add Include selector** (who can enroll):
   - You'll see selector configuration section
   - Click **Include** (this is the logic type, like OR operator)
   - **Selector**: Select **Login Methods** from dropdown
   - **Value**: Select **One-time PIN** from dropdown
   
   This allows anyone with an email address to enroll by receiving a PIN code.

4. Click **Save policy**

**⚠️ Important:** Device posture checks are NOT supported in device enrollment policies. Device posture can only be enforced AFTER enrollment (see Section 1.4 Gateway Network Policies).

#### Step 2: Configure Login Methods

1. In the **Login methods** tab:
   - Find **One-time PIN** in the list
   - Click the toggle or checkbox to **Enable** it
   - This allows users to receive a PIN code to their email (including Gmail)
   - (Optional) Also enable **Google** if you want to allow Google OAuth login
   
2. Click **Save** at the bottom of the page

#### Step 3: Note Your Team Name

Users will need your **team name** to enroll devices:
- Your team name is visible in the Cloudflare One dashboard URL
- Format: `https://<your-team-name>.cloudflareaccess.com`
- Example: If your URL is `mycompany-ztna.cloudflareaccess.com`, your team name is `mycompany-ztna`
- Share this team name with users for enrollment

#### Step 4: (Optional) Prevent Users from Leaving Organization

1. Go to **Team & Resources** → **Devices** → **Device profiles** → **Default**
2. Click **Settings** tab
3. Find **Allow device to leave organization**
4. Toggle it to **Disabled**
5. Click **Save**

**✅ Device enrollment is now enabled!** Users can enroll by:
1. Opening Cloudflare One Agent
2. Entering team name
3. Entering their email (any email including Gmail)
4. Receiving and entering the one-time PIN code

---

### 1.3 Create Device Posture Checks

**Navigation:** Cloudflare One Dashboard → **Devices** → **Configure** (under Device posture)

Create multiple posture checks for comprehensive security:

#### Check 1: Require WARP Connection
1. Click **Add new** → **Require WARP**
2. **Name**: WARP Connected
3. Click **Save**

#### Check 2: OS Version (Windows example)
1. Click **Add new** → **OS Version**
2. **Name**: Windows 10 Minimum
3. **Platform**: Windows
4. **Operator**: greater than or equal to
5. **Version**: `10.0.19041`
6. Click **Save**

#### Check 3: OS Version (macOS example)
1. Click **Add new** → **OS Version**
2. **Name**: macOS 12 Minimum
3. **Platform**: macOS
4. **Operator**: greater than or equal to
5. **Version**: `12.0.0`
6. Click **Save**

#### Check 4: Firewall Enabled
1. Click **Add new** → **Firewall**
2. **Name**: Firewall Enabled
3. **Platform**: Windows or macOS
4. **Check**: Firewall is enabled
5. Click **Save**

#### Check 5: Disk Encryption (Optional but recommended)
1. Click **Add new** → **Disk Encryption**
2. **Name**: Disk Encrypted
3. **Platform**: Windows or macOS
4. **Check**: System drive is encrypted
5. Click **Save**

**Note:** You'll use these posture checks in both Gateway and Access policies.

---

### 1.4 Create Gateway Network Policy for WireGuard

This is the critical step that protects your WireGuard port with Zero Trust authentication.

**⚠️ PORT CONFIGURATION**: The default WireGuard port in this setup is **443/UDP** (obfuscated for Iran). Update the policy below to match your configured `WG_PORT` in [workstation.env](workstation.env).

**Port Options:**
- **443/UDP** (recommended for Iran - appears as HTTPS/QUIC traffic)
- **53/UDP** (DNS obfuscation)
- **123/UDP** (NTP obfuscation)
- High ports: 40000-50000/UDP
- **Avoid 51820** (default WireGuard port, blocked in Iran)

#### Step A: Enable Network Filtering

**Navigation:** Cloudflare One Dashboard → **Traffic policies** → **Traffic settings**

1. Scroll to **Network filtering** section
2. Enable: **Allow Secure Web Gateway to proxy traffic**
3. Under **Proxy**, select protocols:
   - ✅ TCP
   - ✅ UDP
   - ✅ ICMP (optional)
4. Click **Save**

#### Step B: Configure Split Tunnels (Critical!)

**Navigation:** Cloudflare One Dashboard → **Team & Resources** → **Devices** → **Device profiles** → **Configure**

**IMPORTANT**: Configure split tunnels so Cloudflare One Agent and WireGuard don't conflict.

**Goal**: 
- Cloudflare One Agent handles: Authentication + policy enforcement  
- WireGuard handles: Actual internet traffic routing

**Recommended Configuration - Exclude Mode:**

| Type | Selector | Value | Purpose |
|------|----------|-------|---------|
| Exclude | IP Address | `10.13.13.0/24` | WireGuard tunnel subnet - CRITICAL! |
| Exclude | IP Address | `<YOUR-VPS-IP>/32` | Your VPS IP (optional but recommended) |
| Exclude | IP Address | `192.168.0.0/16` | Local network |
| Exclude | IP Address | `10.0.0.0/8` | Private network |
| Exclude | IP Address | `172.16.0.0/12` | Private network |

**Why exclude WireGuard subnet?**
- Prevents Cloudflare One Agent from routing WireGuard's traffic
- WireGuard routes ALL internet traffic (including to 10.13.13.0/24)
- Cloudflare One Agent only checks authentication, doesn't route traffic
- This avoids routing loops and conflicts

Click **Save settings**

#### Step C: Create Gateway Network Policies

**Navigation:** Cloudflare One Dashboard → **Traffic policies** → **Network**

##### Policy 1: Allow Authenticated Users to WireGuard

**Step-by-step creation:**

1. Click **Add a policy** button at the top

2. **Configure Basic Settings:**
   - **Policy name**: Enter "Allow Authenticated Users to WireGuard"
   - **Action**: Select **Allow** from dropdown
   - Leave **Precedence** as default (it will be 1 for first policy)

3. **Configure Traffic Conditions** (what traffic this applies to):
   
   Click **Add condition** under Traffic section:
   
   - **First condition:**
     - Selector: Select **Destination IP**
     - Operator: Select **in**
     - Value: Enter your VPS IP (e.g., `65.109.210.232`)
     - Click **And** to add next condition
   
   - **Second condition:**
     - Selector: Select **Destination Port**
     - Operator: Select **is**
     - Value: Enter **443** (or your configured WG_PORT from workstation.env)
     - Click **And** to add next condition
   
   - **Third condition:**
     - Selector: Select **Protocol**
     - Operator: Select **is**
     - Value: Select **UDP**

4. **Configure Identity Conditions** (who can access):
   
   Click **Add condition** under Identity section:
   
   - Selector: Select **Login Methods**
   - Operator: Select **is**
   - Value: Select **One-time PIN**
   - Click **And** to add device posture check

5. **Configure Device Posture Conditions** (device whitelist):
   
   - Selector: Select **Passed Device Posture Checks**
   - Operator: Select **in**
   - Value: Check ALL the posture checks you created in Section 1.3:
     - ✅ WARP Connected
     - ✅ Windows 10 Minimum (or your OS checks)
     - ✅ Disk Encryption
     - ✅ Firewall Enabled
     - ✅ Domain Joined (if applicable)

6. Click **Create policy**

**This policy enforces:**
- ✅ User must have authenticated via One-time PIN (any email including Gmail)
- ✅ Device must pass ALL posture checks (OS version, firewall, disk encryption, etc.)
- ✅ Device must be connected to Cloudflare One Agent
- ✅ Only allows access to WireGuard port 443/UDP on your VPS IP

##### Policy 2: Block All Other Traffic to WireGuard (Deny by Default)

**Step-by-step creation:**

1. Click **Add a policy** button again

2. **Configure Basic Settings:**
   - **Policy name**: Enter "Block Non-WARP WireGuard Access"
   - **Action**: Select **Block** from dropdown
   - **Precedence**: Will be automatically set to 2 (after first policy)

3. **Enable Block Notification:**
   - Scroll down to find **Display block notification**
   - Toggle it to **Enabled**
   - In **Custom notification** field, enter: `Access denied. Connect via Cloudflare One Agent with valid credentials.`

4. **Configure Traffic Conditions** (what traffic to block):
   
   Click **Add condition** under Traffic section:
   
   - **First condition:**
     - Selector: Select **Destination IP**
     - Operator: Select **in**
     - Value: Enter your VPS IP (e.g., `65.109.210.232`)
     - Click **And**
   
   - **Second condition:**
     - Selector: Select **Destination Port**
     - Operator: Select **is**
     - Value: Enter **443** (must match Policy 1)
     - Click **And**
   
   - **Third condition:**
     - Selector: Select **Protocol**
     - Operator: Select **is**
     - Value: Select **UDP**

5. **Do NOT add Identity or Device Posture conditions** (we want to block everyone who doesn't match Policy 1)

6. Click **Create policy**

**⚠️ Critical: Policy Order**
- Cloudflare evaluates policies from **top to bottom** (precedence 1, 2, 3...)
- Your **Allow policy (1)** MUST be **ABOVE** the **Block policy (2)**
- If needed, drag and drop policies to reorder them in the UI
- Users matching Policy 1 get access, everyone else gets blocked by Policy 2

**✅ Gateway Network Policies are now configured!**

---

### 1.5 Create Cloudflare Tunnel

**Navigation:** Cloudflare One Dashboard → **Networks** → **Connectors** → **Cloudflare Tunnels**

1. Click **Create a tunnel**

2. **Select connector type:** Cloudflared

3. **Name your tunnel:**
   ```
   Tunnel name: vps-ztna-tunnel
   ```
   Click **Save tunnel**

4. **Install connector:**
   - Copy the token shown (starts with `eyJh...`)
   - **Save this token** - you'll need it in Part 2 for VPS setup
   - Example: `eyJhIjoiODQ5YTNlZjA0NDVlNmFhNjFlOTcyMmQ5MTgxZDY5ZDQi...`

5. **Configure public hostname routes:**
   
   Click **Published applications** tab and add:

   **SSH Access:**
   - Public hostname: `ssh.yourdomain.com`
   - Service Type: `SSH`
   - URL: `localhost:22`
   - Click **Save**

   **VNC Applications** (repeat for each user):
   
   User 1:
   - Public hostname: `vnc-hossein.yourdomain.com`
   - Service Type: `HTTP`
   - URL: `localhost:1370`
   - Save

   User 2:
   - Public hostname: `vnc-asal.yourdomain.com`
   - Service Type: `HTTP`
   - URL: `localhost:1377`
   - Save

   User 3:
   - Public hostname: `vnc-hassan.yourdomain.com`
   - Service Type: `HTTP`
   - URL: `localhost:1380`
   - Save

6. Click **Save tunnel**

**Note:** Tunnel will show **Down** status until you set up the VPS server in Part 2.

---

### 1.6 Create Access Applications for SSH/VNC

**Navigation:** Cloudflare One Dashboard → **Access controls** → **Applications** → **Add an application**

#### Application 1: SSH Access

1. Select **Self-hosted**
2. **Application name**: SSH Server
3. **Application domain**: `ssh.yourdomain.com`
4. Click **Next**

**Create Policy:**
| Configuration | Value |
|---------------|-------|
| **Policy name** | Allow Authenticated Users |
| **Action** | Allow |

**Include rule:**
| Selector | Operator | Value |
|----------|----------|-------|
| Emails ending in | is | @yourcompany.com |

**Require rules:**
| Selector | Operator | Value |
|----------|----------|-------|
| **AND** Authentication method | is | mfa - multiple-factor authentication |
| **AND** Passed Device Posture Checks | in | [Select all posture checks] |

Click **Next** and **Add application**

#### Application 2-4: VNC Access (repeat for each)

**For vnc-hossein.yourdomain.com:**
1. Select **Self-hosted**
2. **Application name**: VNC - Hossein
3. **Application domain**: `vnc-hossein.yourdomain.com`
4. Use same policy as SSH (Allow Authenticated Users)
5. Click **Add application**

Repeat for:
- `vnc-asal.yourdomain.com`
- `vnc-hassan.yourdomain.com`

---

## Part 2: VPS Server Setup

### Step 2.1: Prepare Configuration File

1. **Clone this repository:**
   ```bash
   git clone https://github.com/HosseinBeheshti/setupWS.git
   cd setupWS
   ```

2. **Edit `workstation.env`:**
   ```bash
   nano workstation.env
   ```

3. **Update these values:**
   ```bash
   # Cloudflare Configuration
   CLOUDFLARE_TUNNEL_TOKEN="eyJhIjoiODQ5YTNlZjA0NDVl..."  # From Step 1.5
   CLOUDFLARE_DOMAIN="yourdomain.com"
   CLOUDFLARE_ZONE_ID="your-zone-id"  # From Cloudflare dashboard

   # WireGuard Configuration
   WG_SERVER_PUBLIC_IP="65.109.210.232"  # Your VPS IP
   WG_PORT="443"  # Obfuscated port (443/UDP appears as HTTPS/QUIC)
   WG_SUBNET="10.13.13.0/24"
   WG_DNS="1.1.1.1,1.0.0.1"

   # VNC Users
   VNCUSER1_USERNAME='hossein'
   VNCUSER1_PASSWORD='strong_password_here'
   VNCUSER1_PORT='1370'

   VNCUSER2_USERNAME='asal'
   VNCUSER2_PASSWORD='strong_password_here'
   VNCUSER2_PORT='1377'

   VNCUSER3_USERNAME='hassan'
   VNCUSER3_PASSWORD='strong_password_here'
   VNCUSER3_PORT='1380'

   VNC_USER_COUNT=3
   ```

4. Save and exit (Ctrl+X, Y, Enter)

### Step 2.2: Run Setup Script

```bash
sudo ./setup_server.sh
```

**The script will:**
1. Install Docker, cloudflared, and system packages
2. Initialize SQLite database for user management
3. Generate WireGuard server keys
4. Enable IP forwarding
5. Configure firewall rules
6. Start Docker containers (WireGuard + Cloudflared)
7. Set up VNC servers for each user
8. Configure virtual router
9. Set up automated backups

**Expected output:**
```
[INFO] Loading configuration from workstation.env...
[INFO] Configuration loaded successfully.
========================================
Step 0/5: Setting up ZTNA Infrastructure
========================================
[INFO] Installing required packages...
[INFO] ✓ System packages installed
[INFO] Installing Docker...
[INFO] ✓ Docker installed and started
[INFO] ✓ Docker is operational
[INFO] Installing cloudflared...
[INFO] ✓ cloudflared installed
[INFO] ✓ Directories created
[INFO] ✓ Database initialized: /var/lib/ztna/users.db
[INFO] ✓ WireGuard server keys generated
[INFO] ✓ IP forwarding enabled
[INFO] ✓ Firewall configured
[INFO] Starting ZTNA Docker services...
[INFO] ✓ Docker services started
[INFO] ✓ WireGuard container running
[INFO] ✓ Cloudflare tunnel container running
[INFO] ✓ Cloudflare tunnel connected successfully
[INFO] ✓ ZTNA Infrastructure setup completed
========================================
Step 1/5: Setting up VNC Server and Users
========================================
[INFO] ✓ VNC setup completed successfully
========================================
Setup Complete!
========================================
```

### Step 2.3: Verify Services

```bash
# Check Docker containers
docker ps

# Should show:
# - wireguard (healthy)
# - cloudflared (running)

# Check Cloudflare tunnel status
docker logs cloudflared

# Should show: "Registered tunnel connection"

# Check WireGuard status
docker exec wireguard wg show

# Check VNC services
systemctl status vncserver-hossein@1.service
systemctl status vncserver-asal@2.service
systemctl status vncserver-hassan@3.service
```

### Step 2.4: Verify Tunnel in Cloudflare Dashboard

1. Go to **Networks** → **Connectors** → **Cloudflare Tunnels**
2. Your tunnel should show **Healthy** status
3. Click on tunnel name to see active connections

---

## Part 3: Device Enrollment (All Users)

**Important:** ALL users must complete enrollment before accessing any service.

### 3.1 Desktop/Laptop Enrollment

#### Windows/macOS/Linux

1. **Download Cloudflare One Agent:**
   - Visit: https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/download-warp/
   - Select **"Cloudflare WARP for managed deployment"** (enterprise version)
   - Click **Download** for your operating system
   - Install the application

2. **Open Cloudflare One Agent:**
   - Launch the **Cloudflare One Agent** application
   - Click the Cloudflare logo in system tray (Windows/Linux) or menu bar (macOS)

3. **Enroll in Zero Trust:**
   - Click Settings (gear icon) → **Preferences** → **Account**
   - Select **Login with Cloudflare Zero Trust**
   - Enter your **team name** (from Step 1.2)
   - Example: `mycompany-ztna`

4. **Authenticate:**
   - Browser will open
   - Login with your email
   - **Complete 2FA** (enter OTP code from authenticator app)
   - Click **Open Cloudflare One Agent** when prompted

5. **Connect:**
   - Cloudflare One Agent will automatically connect
   - Status should show **Connected**
   - You are now authenticated and enrolled in Zero Trust

6. **Verify Enrollment:**
   ```bash
   # Check connection status
   warp-cli status
   # Should show: Connected
   # Registration: mycompany-ztna

   # Check account info
   warp-cli account
   # Should show your email
   ```

#### CLI Enrollment (Alternative method)

```bash
# Register device
warp-cli registration new <your-team-name>

# Authenticate in browser (2FA required)

# Verify registration
warp-cli registration show

# Connect
warp-cli connect

# Check status
warp-cli status
```

---

### 3.2 Mobile Device Enrollment

#### iOS/Android

1. **Download Cloudflare One Agent:**
   - iOS: https://apps.apple.com/app/cloudflare-one-agent/id6443476492
   - Android: https://play.google.com/store/apps/details?id=com.cloudflare.cloudflareoneagent
   - **Important**: Install "Cloudflare One Agent", NOT the old "1.1.1.1" consumer app

2. **Open App:**
   - Tap **Next** to start
   - Review privacy policy → **Accept**

3. **Enroll in Zero Trust:**
   
   **Method A: Manual Entry**
   - Tap **Enter your team name**
   - Enter: `mycompany-ztna`
   - Tap **Next**

   **Method B: QR Code (easier)**
   - On admin computer, generate QR code for: 
     ```
     cf1app://oneapp.cloudflare.com/team?name=mycompany-ztna
     ```
   - Scan QR code with phone camera
   - Opens Cloudflare One Agent automatically

4. **Authenticate:**
   - Login with your email
   - **Complete 2FA** (enter OTP code)
   - Tap **Allow** when prompted for VPN profile

5. **Install VPN Profile:**
   - Tap **Install VPN Profile**
   - Enter device passcode
   - Tap **Allow**

6. **Connect:**
   - Toggle switch to **Connected**
   - Status should show **Protected**

---

### 3.3 Verify Device Posture (Admin)

After users enroll, verify their device health:

1. Go to **Team & Resources** → **Devices** in Cloudflare dashboard
2. Find the user's device
3. Click **View details** → **Posture checks** tab
4. Verify all checks show **Pass**:
   - ✅ WARP Connected
   - ✅ OS Version
   - ✅ Firewall Enabled
   - ✅ Disk Encrypted (if configured)

**If any check fails:**
- User must fix the issue (update OS, enable firewall, etc.)
- Posture checks re-run every 5 minutes automatically
- User cannot access services until all checks pass

---

## Part 4: Using Services After Enrollment

### 4.1 WireGuard VPN Access

**Prerequisites:**
- ✅ Cloudflare One Agent installed and connected
- ✅ Device posture checks passing
- ✅ WireGuard client installed (separate app)
- ✅ WireGuard config file provided by admin

**IMPORTANT**: You need TWO apps running:
1. **Cloudflare One Agent** (authentication - must be connected)
2. **WireGuard** (VPN tunnel - user activates when needed)

#### Step 1: Ensure Cloudflare One Agent is Running

**Before using WireGuard, verify:**
```bash
# Check Cloudflare One Agent status
warp-cli status
# Must show: Status update: Connected

# If not connected
warp-cli connect
```

**On mobile:**
- Open Cloudflare One Agent
- Verify status shows "Protected" or "Connected"

#### Step 2: Get WireGuard Configuration

**Admin creates user:**
```bash
ssh root@your-vps-ip
cd /root/setupWS
sudo ./add_wg_peer.sh username
```

**Admin sends config to user:**
- Config file: `/var/lib/ztna/clients/<username>.conf`
- QR code (for mobile): Shown in terminal after creation

#### Step 3: Install WireGuard Client (Separate from Cloudflare!)

**Desktop:**
- Windows/macOS/Linux: https://www.wireguard.com/install/
- Install and launch WireGuard

**Mobile:**
- iOS: https://apps.apple.com/app/wireguard/id1441195209
- Android: https://play.google.com/store/apps/details?id=com.wireguard.android

#### Step 4: Import WireGuard Configuration

**Desktop:**
1. Open WireGuard app
2. Click **Import tunnel(s) from file**
3. Select the `.conf` file
4. Click **Activate**

**Mobile:**
1. Open WireGuard app
2. Tap **+** → **Create from QR code**
3. Scan QR code provided by admin
4. Tap **Create tunnel**
5. Toggle to **Active**

#### Step 5: Connect with Both Apps

**Connection Sequence:**

1. **First**: Ensure Cloudflare One Agent is connected
   ```bash
   warp-cli status  # Must show: Connected
   ```

2. **Then**: Activate WireGuard tunnel
   - Open WireGuard app
   - Click/tap the toggle to "Activate"

3. **What happens:**
   - Cloudflare Gateway checks: Is this user authenticated?
   - If YES → Allows WireGuard connection to configured port (default 443/UDP)
   - If NO → Blocks connection
   - WireGuard establishes VPN tunnel
   - All your internet traffic now routes through VPS

#### Step 6: Test Connection

```bash
# Test WireGuard gateway
ping 10.13.13.1
# Should respond

# Check your public IP (should be VPS IP now)
curl ifconfig.me
# Should show: 65.109.210.232 (your VPS IP)

# Test internet via VPN
curl https://www.google.com
# Should work
```

**If connection fails:**

1. **Check Cloudflare One Agent:**
   ```bash
   warp-cli status
   # Must show: Connected
   ```

2. **Check device posture in dashboard:**
   - Go to Cloudflare One Dashboard
   - **Team & Resources** → **Devices**
   - Find your device
   - Verify all posture checks show "Pass"

3. **Check Gateway logs:**
   - **Analytics** → **Gateway** → **Network logs**
   - Filter: Destination Port = 443 (or your configured WG_PORT)
   - Look for "Block" actions and reason

4. **Check WireGuard status:**
   ```bash
   # On VPS
   docker logs wireguard
   docker exec wireguard wg show
   ```

**Common issues:**

| Problem | Cause | Solution |
|---------|-------|----------|
| WireGuard says "Connecting..." forever | Cloudflare One Agent not connected | Run `warp-cli connect` |
| Connection blocked | Device posture check failed | Fix device issue (OS update, firewall, etc.) |
| "No route to host" | Split tunnel misconfigured | Check Cloudflare split tunnel settings |
| Works sometimes, fails others | Cloudflare One Agent disconnected | Ensure it's set to "Always on" |

---

### 4.2 SSH Access

**Prerequisites:**
- ✅ Browser with internet access (WARP not required for browser-based SSH)
- ✅ Authentication credentials (email + 2FA)

#### Method 1: Browser-Based SSH (Easiest)

1. Open browser and go to: `https://ssh.yourdomain.com`
2. **Authenticate:**
   - Enter your email
   - Complete 2FA
   - (Optional) Complete device posture check
3. Browser-based terminal will open
4. Login as root or your user

#### Method 2: CLI SSH via cloudflared (Advanced)

**One-time setup:**
```bash
# Install cloudflared on your local machine
# macOS
brew install cloudflare/cloudflare/cloudflared

# Windows
winget install Cloudflare.cloudflared

# Linux
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared
```

**Connect via SSH:**
```bash
# Connect to SSH
cloudflared access ssh --hostname ssh.yourdomain.com

# Or add to SSH config
cloudflared access ssh-config --hostname ssh.yourdomain.com >> ~/.ssh/config

# Then use normal SSH
ssh ssh.yourdomain.com
```

---

### 4.3 VNC Access

**Prerequisites:**
- ✅ Browser with internet access
- ✅ Authentication credentials (email + 2FA)

#### Access VNC via Browser

1. Open browser and navigate to your assigned VNC URL:
   - Hossein: `https://vnc-hossein.yourdomain.com`
   - Asal: `https://vnc-asal.yourdomain.com`
   - Hassan: `https://vnc-hassan.yourdomain.com`

2. **Authenticate:**
   - Enter your email
   - Complete 2FA verification
   - Device posture check (automatic)

3. **VNC Login:**
   - noVNC web interface will load
   - Click **Connect**
   - Enter VNC password (provided by admin)

4. **Use Desktop:**
   - Full Ubuntu desktop environment
   - Firefox, VS Code, Chrome pre-installed
   - Internet routed through VPS

**Keyboard shortcuts in noVNC:**
- **Ctrl+Alt+Shift** - Open extra keys menu
- **View Only Mode** - Toggle in settings
- **Clipboard** - Use clipboard button to paste

---

## Part 5: Admin Workflows

### 5.1 Add New WireGuard User

```bash
# SSH to VPS
ssh root@your-vps-ip

# Navigate to scripts directory
cd /root/setupWS

# Add new user
sudo ./add_wg_peer.sh username

# Output:
# - Config file: /var/lib/ztna/clients/username.conf
# - QR code displayed in terminal
# - Database record created
```

### 5.2 List All Users

```bash
cd /root/setupWS
sudo ./query_users.sh

# Shows:
# - Username
# - Device ID
# - IP address
# - Public key
# - Created date
# - Last seen
```

### 5.3 Remove User

```bash
# Method 1: Using query_users.sh menu
sudo ./query_users.sh
# Select option to delete user

# Method 2: Direct deletion
docker exec wireguard wg set wg0 peer <PUBLIC_KEY> remove

# Remove from database
sqlite3 /var/lib/ztna/users.db "DELETE FROM users WHERE username='username';"
```

### 5.4 Monitor Services

```bash
# Check Docker containers
docker ps

# View logs
docker logs wireguard
docker logs cloudflared

# Check WireGuard connections
docker exec wireguard wg show

# Check VNC services
systemctl status vncserver-*

# View Gateway logs (Cloudflare Dashboard)
# Navigate to: Analytics → Gateway → Network logs
```

### 5.5 Revoke Device Access

**In Cloudflare Dashboard:**
1. Go to **Team & Resources** → **Devices**
2. Find the device
3. Click **...** → **Revoke**
4. Device will be disconnected immediately
5. User must re-enroll to regain access

---

## Part 6: Backup & Recovery

### 6.1 Automated Backups

Backups run automatically daily at 2:00 AM UTC via cron job.

**Backup includes:**
- WireGuard configurations
- SQLite user database
- VNC user configurations
- System scripts

**Backup location:** `/var/lib/ztna/backups/`

### 6.2 Manual Backup

```bash
cd /root/setupWS
sudo ./backup_ztna.sh

# Creates timestamped backup:
# /var/lib/ztna/backups/ztna_backup_20260122_140530.tar.gz
```

### 6.3 Download Backup to Local Machine

```bash
# From your local machine
scp root@your-vps-ip:/var/lib/ztna/backups/ztna_backup_*.tar.gz ~/backups/
```

### 6.4 Restore from Backup

```bash
# On VPS
cd /var/lib/ztna/backups

# Extract backup
tar -xzf ztna_backup_20260122_140530.tar.gz

# Restore WireGuard configs
cp -r etc/wireguard/* /etc/wireguard/

# Restore database
cp var/lib/ztna/users.db /var/lib/ztna/

# Restart services
docker compose -f /root/setupWS/docker-compose-ztna.yml restart
```

---

## Part 7: Monitoring & Troubleshooting

### 7.1 Common Issues

#### Issue: WARP won't connect

**Symptoms:**
- WARP shows "Disconnected" or "Connecting..."
- Cannot access any services

**Solutions:**
```bash
# Check WARP status
warp-cli status

# View detailed logs
warp-cli debug log

# Re-register device
warp-cli registration delete
warp-cli registration new <team-name>

# Restart WARP service
# macOS/Linux
sudo warp-cli disconnect
sudo warp-cli connect

# Windows
net stop WarpSvc
net start WarpSvc
```

#### Issue: Device posture checks failing

**Symptoms:**
- Cannot access services even with WARP connected
- Cloudflare dashboard shows failed posture checks

**Solutions:**
1. Check which posture check failed:
   - Go to **Devices** → Select device → **Posture checks** tab
   
2. Fix the specific issue:
   - **OS Version**: Update operating system
   - **Firewall**: Enable Windows Defender Firewall or macOS firewall
   - **Disk Encryption**: Enable BitLocker (Windows) or FileVault (macOS)

3. Wait 5 minutes for automatic re-check

4. Manually trigger re-check:
   ```bash
   # Disconnect and reconnect WARP
   warp-cli disconnect
   warp-cli connect
   ```

#### Issue: WireGuard blocked even with WARP connected

**Symptoms:**
- WARP shows connected
- WireGuard connection fails or times out

**Solutions:**
1. Verify WARP is truly connected:
   ```bash
   warp-cli status
   # Must show: Status update: Connected
   ```

2. Check Gateway logs:
   - Go to **Analytics** → **Gateway** → **Network logs**
   - Filter: Destination Port = 443 (or your configured WG_PORT)
   - Look for block reason

3. Verify Split Tunnel configuration:
   - Ensure VPS IP is not excluded
   - Check **Traffic policies** → **Traffic settings** → **Split Tunnels**

4. Check policy order:
   - **Traffic policies** → **Network**
   - Ensure Allow policy is ABOVE Block policy

5. Verify user email in policy:
   - Check that regex matches your email
   - Example: `.*@yourcompany.com` should match `user@yourcompany.com`

#### Issue: Cannot access SSH/VNC via browser

**Symptoms:**
- Browser shows "Access Denied" or 403 error
- Authentication page doesn't appear

**Solutions:**
1. Verify Access application exists:
   - **Access controls** → **Applications**
   - Check SSH/VNC app is listed

2. Check Access policy:
   - Open application → **Policies** tab
   - Verify user email is in Include rule
   - Verify 2FA requirement is correct

3. Verify tunnel is running:
   - **Networks** → **Connectors** → **Cloudflare Tunnels**
   - Status should be **Healthy**
   - Check `docker logs cloudflared` on VPS

4. Clear browser cache and cookies

5. Try incognito/private mode

#### Issue: Cloudflare tunnel shows "Down"

**Symptoms:**
- Tunnel status: Down
- SSH/VNC URLs don't work

**Solutions:**
```bash
# SSH to VPS
ssh root@your-vps-ip

# Check cloudflared container
docker ps
docker logs cloudflared

# If container not running, restart
cd /root/setupWS
source workstation.env
export CLOUDFLARE_TUNNEL_TOKEN WG_SERVER_PUBLIC_IP WG_PORT WG_SUBNET WG_DNS
docker compose -f docker-compose-ztna.yml up -d cloudflared

# Verify tunnel registration
docker logs cloudflared | grep "Registered tunnel connection"
# Should show 4 connections
```

### 7.2 Monitoring Dashboard

**Cloudflare Dashboard Analytics:**

1. **Gateway Network Logs:**
   - **Analytics** → **Gateway** → **Network logs**
   - Filter by Destination IP (your VPS)
   - View all WireGuard connection attempts
   - See which users/devices were allowed or blocked

2. **Access Logs:**
   - **Analytics** → **Access** → **Logs**
   - View SSH/VNC authentication attempts
   - See 2FA completions
   - Track posture check results

3. **Device Health:**
   - **Team & Resources** → **Devices**
   - View all enrolled devices
   - Check posture status
   - See last seen timestamp

4. **Tunnel Health:**
   - **Networks** → **Connectors** → **Cloudflare Tunnels**
   - View connection status
   - See active connections count
   - Check bandwidth usage

### 7.3 VPS Monitoring

```bash
# System resources
htop

# Docker containers
docker stats

# WireGuard active peers
docker exec wireguard wg show

# Check WireGuard bandwidth
docker exec wireguard wg show wg0 transfer

# View VNC service logs
journalctl -u vncserver-hossein@1.service -f

# Network connections (adjust port if WG_PORT changed)
netstat -tuln | grep -E '(443|1370|1377|1380)'

# Disk usage
df -h
du -sh /var/lib/ztna/backups
```

### 7.4 Performance Optimization

**For high-traffic WireGuard:**
```bash
# Increase kernel UDP buffer sizes
sudo sysctl -w net.core.rmem_max=2500000
sudo sysctl -w net.core.wmem_max=2500000

# Make persistent
echo "net.core.rmem_max=2500000" | sudo tee -a /etc/sysctl.conf
echo "net.core.wmem_max=2500000" | sudo tee -a /etc/sysctl.conf
```

**For VNC performance:**
- Use lower resolution (1280x720 instead of 1920x1080)
- Reduce color depth in VNC client settings
- Use compression in VNC client

### 7.5 Security Audit

**Regular security checks:**

1. **Review enrolled devices:**
   - **Devices** → Check for unknown devices
   - Revoke any suspicious devices

2. **Review Gateway logs:**
   - **Analytics** → **Gateway** → **Network logs**
   - Look for unusual connection patterns
   - Check for blocked attempts

3. **Review Access logs:**
   - **Analytics** → **Access** → **Logs**
   - Check for failed 2FA attempts
   - Verify all access is from expected users

4. **Update posture checks:**
   - Increase minimum OS version requirements
   - Add new security checks (antivirus, etc.)

5. **Rotate credentials:**
   - Change VNC passwords regularly
   - Rotate WireGuard keys
   - Update Cloudflare tunnel token

---

## Summary

You now have a complete Zero Trust architecture where:

✅ **All users** (WireGuard, SSH, VNC) must:
- Enroll via Cloudflare WARP
- Authenticate with 2FA
- Pass device posture checks

✅ **WireGuard VPN** is protected by:
- Gateway Network Policies
- User authentication
- Device health verification

✅ **SSH/VNC access** is protected by:
- Cloudflare Access
- 2FA requirement
- Posture checks

✅ **Centralized management**:
- Revoke access instantly from dashboard
- Monitor all connections in real-time
- View device health status

✅ **Defense in depth**:
- Identity verification (who)
- Device verification (what)
- Network policies (where)
- Application policies (how)

**Key Takeaway:** No service can be accessed without authenticating through Cloudflare Zero Trust first. This provides comprehensive security for your entire infrastructure.

---

## Additional Resources

- **Cloudflare One Documentation:** https://developers.cloudflare.com/cloudflare-one/
- **WireGuard Documentation:** https://www.wireguard.com/
- **Cloudflare One Agent Download:** https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/download-warp/
- **Support:** https://community.cloudflare.com/

---

**Questions or Issues?** Open an issue on GitHub: https://github.com/HosseinBeheshti/setupWS/issues
