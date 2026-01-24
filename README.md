# Cloudflare Zero Trust Network Access (ZTNA) Setup

Route all user traffic through your VPS using **Cloudflare One Agent + WARP Connector**.

## Architecture Overview

```
User Device                    Cloudflare Network          Your VPS (Germany)
┌──────────────┐              ┌─────────────────┐         ┌──────────────┐
│ Cloudflare   │              │   Zero Trust    │         │     WARP     │
│  One Agent   │─────────────▶│   Gateway       │────────▶│  Connector   │───▶ Internet
│              │  Encrypted   │  (Authentication)│ Routed  │              │    (Exit IP: VPS)
└──────────────┘              └─────────────────┘         └──────────────┘
```

**What this provides:**
- ✅ **Zero Trust Authentication**: One-time PIN via Gmail
- ✅ **Device Posture Checks**: OS version, firewall status, encryption
- ✅ **VPS Exit IP**: All traffic exits through your German VPS (65.109.210.232)
- ✅ **Works on ALL platforms**: Desktop (Windows/macOS/Linux) + Mobile (Android/iOS)
- ✅ **No VPN conflicts**: Single app solution (Cloudflare One Agent)
- ✅ **Obfuscated**: Looks like HTTPS traffic to Cloudflare

**Traffic Flow:**
1. User installs **Cloudflare One Agent** (one app only)
2. Authenticates with Gmail (One-time PIN)
3. Device posture checked automatically
4. All internet traffic routes: Device → Cloudflare → **WARP Connector on VPS** → Internet
5. Exit IP shows VPS location (Germany)

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Part 1: Cloudflare Zero Trust Setup](#part-1-cloudflare-zero-trust-setup)
  - [1.1 Configure Identity Provider with One-time PIN](#11-configure-identity-provider-with-one-time-pin)
  - [1.2 Enable Device Enrollment](#12-enable-device-enrollment)
  - [1.3 Create Device Posture Checks](#13-create-device-posture-checks)
  - [1.4 Create Gateway Network Policy](#14-create-gateway-network-policy)
  - [1.5 Create Cloudflare Tunnel (SSH/VNC)](#15-create-cloudflare-tunnel-sshvnc)
  - [1.6 Create Access Applications](#16-create-access-applications)
- [Part 2: VPS Server Setup](#part-2-vps-server-setup)
  - [2.1 Install WARP Connector](#21-install-warp-connector)
  - [2.2 Configure Split Tunnels](#22-configure-split-tunnels)
  - [2.3 (Optional) L2TP VPN for Infrastructure](#23-optional-l2tp-vpn-for-infrastructure)
- [Part 3: Client Device Setup](#part-3-client-device-setup)
  - [3.1 Install Cloudflare One Agent](#31-install-cloudflare-one-agent)
  - [3.2 Authenticate and Connect](#32-authenticate-and-connect)
- [Part 4: Verification](#part-4-verification)
- [Troubleshooting](#troubleshooting)
- [Appendix: L2TP VPN Setup](#appendix-l2tp-vpn-setup)

---

## Prerequisites

### VPS Server
- **Provider**: Any (Hetzner, DigitalOcean, AWS, etc.)
- **OS**: Ubuntu 24.04 LTS
- **RAM**: 2GB minimum (4GB recommended)
- **Storage**: 20GB minimum
- **Network**: Public IPv4 address
- **Location**: Germany (for your use case)
- **Your VPS IP**: `65.109.210.232`

### Cloudflare Account
- Free Cloudflare account
- Zero Trust plan: **Free tier supports 50 users**
- Domain managed by Cloudflare (for Tunnel access)
- Team name: `noise-ztna` (yours)

### Required Access
- Root/sudo access to VPS
- Cloudflare dashboard admin access
- User Gmail accounts for authentication

---

## Part 1: Cloudflare Zero Trust Setup

### 1.1 Configure Identity Provider with One-time PIN

This configures Gmail authentication with one-time PIN (no OAuth consent screen needed).

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to: **Settings → Authentication**
3. Under **Login methods**, click **Add new**
4. Select: **One-time PIN**
5. Configure:
   - **Name**: `Gmail One-time PIN`
   - Click **Save**

**How it works:**
- User enters their Gmail address
- Cloudflare sends a 6-digit PIN to their Gmail
- User enters PIN to authenticate
- No OAuth consent screen required

---

### 1.2 Enable Device Enrollment

Configure which devices can enroll in your Zero Trust network.

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

**Result:** Any user with a Gmail address can enroll their device.

---

### 1.3 Create Device Posture Checks

Enforce security requirements on user devices.

#### Navigate to Device Posture
1. Go to: **Reusable components → Posture checks**
2. Click: **Add new**

#### Create OS Version Check
1. **Check name**: `OS Version Check`
2. **Check type**: `OS version`
3. **Operating system**: `macOS` (repeat for Windows, Linux, Android, iOS)
4. **Operator**: `>=`
5. **Version**: 
   - macOS: `13.0` (Ventura or newer)
   - Windows: `10.0.19041` (Windows 10 20H1 or newer)
   - Linux: Any modern kernel `5.0+`
   - Android: `10.0`
   - iOS: `15.0`
6. Click **Save**

#### Create Firewall Check
1. **Check name**: `Firewall Enabled`
2. **Check type**: `Firewall`
3. **Enabled**: ✅ (checked)
4. Click **Save**

#### Create Disk Encryption Check
1. **Check name**: `Disk Encryption`
2. **Check type**: `Disk encryption`
3. **Encryption detected**: ✅ (checked)
4. Click **Save**

**Result:** Devices must pass these checks before connecting.

---

### 1.4 Create Gateway Network Policy

This enforces that only authenticated users can route traffic through WARP Connector.

1. Go to: **Traffic policies → Firewall policies → Network** tab
2. Click: **Add a policy**
3. Configure:
   - **Policy name**: `Allow Authenticated Users`
   - **Selector**: `User Email`
   - **Operator**: `matches regex`
   - **Value**: `.*` (matches all Gmail addresses)
   - **Action**: `Allow`
4. Under **Device posture**, add the posture checks:
   - ✅ OS Version Check
   - ✅ Firewall Enabled
   - ✅ Disk Encryption
5. Click **Save**

**Result:** Only authenticated Gmail users with healthy devices can use WARP Connector.

---

### 1.5 Create Cloudflare Tunnel (SSH/VNC)

This creates secure access to your VPS services without exposing ports.

#### Step 1: Create Tunnel

1. Go to: **Networks → Tunnels**
2. Click: **Create a tunnel**
3. Select connector: **Cloudflared**
4. **Tunnel name**: `vps-services`
5. Click **Save tunnel**

#### Step 2: Install Cloudflared on VPS

Copy the installation command shown in the dashboard. It looks like:

```bash
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb
sudo cloudflared service install <YOUR_TOKEN>
```

Run this on your VPS.

#### Step 3: Configure Routes

**IMPORTANT**: If you see DNS record conflict errors, delete the existing A/AAAA records for your subdomain first:

1. Go to Cloudflare Dashboard → DNS → Records
2. Find and delete any A/AAAA records for `ssh`, `vnc-workstation`, etc.
3. Then return to tunnel configuration

Now add routes in the Tunnel dashboard:

**SSH Access:**
- **Subdomain**: `ssh`
- **Domain**: `yourdomain.com`
- **Service**: `ssh://localhost:22`
- Click **Save**

**VNC Access (Workstation):**
- **Subdomain**: `vnc-workstation`
- **Domain**: `yourdomain.com`
- **Service**: `http://localhost:1370`
- Click **Save**

**VNC Access (Design):**
- **Subdomain**: `vnc-design`
- **Domain**: `yourdomain.com`
- **Service**: `http://localhost:1377`
- Click **Save**

**VNC Access (TV):**
- **Subdomain**: `vnc-tv`
- **Domain**: `yourdomain.com`
- **Service**: `http://localhost:1380`
- Click **Save**

**Result:** Services accessible via:
- `ssh.yourdomain.com`
- `vnc-workstation.yourdomain.com`
- `vnc-design.yourdomain.com`
- `vnc-tv.yourdomain.com`

---

### 1.6 Create Access Applications

Protect tunnel services with Zero Trust authentication.

#### Create SSH Access Application

1. Go to: **Access → Applications**
2. Click: **Add an application**
3. Select: **Self-hosted**
4. Configure:
   - **Application name**: `VPS SSH`
   - **Session duration**: `24 hours`
   - **Application domain**:
     - **Subdomain**: `ssh`
     - **Domain**: `yourdomain.com`
   - Click **Next**

5. Add policy:
   - **Policy name**: `Gmail Users`
   - **Action**: `Allow`
   - **Selector**: `Emails ending in`
   - **Value**: `gmail.com`
   - Click **Next**

6. Review and click **Add application**

#### Create VNC Access Applications

Repeat the above steps for each VNC service:

**Workstation VNC:**
- **Name**: `VNC Workstation`
- **Subdomain**: `vnc-workstation`

**Design VNC:**
- **Name**: `VNC Design`
- **Subdomain**: `vnc-design`

**TV VNC:**
- **Name**: `VNC TV`
- **Subdomain**: `vnc-tv`

**Result:** All services require Gmail authentication before access.

---

## Part 2: VPS Server Setup

### 2.1 Install WARP Connector

SSH into your VPS and run the automated setup script:

```bash
# Clone the repository
git clone https://github.com/HosseinBeheshti/setupWS.git
cd setupWS

# Run WARP Connector setup
sudo ./setup_warp_connector.sh
```

This script will:
- Install Cloudflare WARP Connector
- Configure IP forwarding and routing
- Setup UFW firewall
- Create post-installation guide

#### Register WARP Connector

After installation, register the connector:

```bash
# Register with Cloudflare
sudo warp-cli registration new
```

You'll be prompted to authenticate. Follow the instructions to link this WARP Connector to your Cloudflare Zero Trust account.

#### Verify Installation

```bash
# Check status
sudo warp-cli status

# Check account
sudo warp-cli account

# View logs
sudo journalctl -u warp-svc -f
```

You should see: `Status: Connected`

---

### 2.2 Configure Split Tunnels

This prevents routing loops and ensures traffic flows correctly.

1. Go to: **Settings → WARP Client → Device settings → Manage → Default**
2. Scroll to: **Split Tunnels**
3. Click: **Manage**
4. Set mode: **Exclude IPs and domains**
5. Add these exclusions:
   ```
   65.109.210.232/32    (your VPS IP - prevents routing loop)
   10.0.0.0/8           (private networks)
   172.16.0.0/12        (private networks)
   192.168.0.0/16       (private networks)
   ```
6. Click **Save**

**Why this is needed:**
- Prevents WARP Connector from routing its own traffic through itself (loop)
- Excludes private network ranges
- Ensures proper connectivity

---

### 2.3 (Optional) L2TP VPN for Infrastructure

If you need L2TP VPN access for your own infrastructure management (virtual routers, xRDP, etc.), you can set it up alongside WARP Connector.

**Use Cases:**
- Personal administrative access to VPS
- Virtual router setup
- xRDP/Windows Remote Desktop access
- Network bridging for internal infrastructure

**Setup:**

```bash
# Run L2TP VPN setup
sudo ./setup_l2tp.sh
```

This creates a separate L2TP/IPsec VPN server that runs alongside WARP Connector. See [Appendix: L2TP VPN Setup](#appendix-l2tp-vpn-setup) for detailed configuration.

**Note:** This is for infrastructure management only. End users should use Cloudflare One Agent (WARP Connector) for internet routing.

---

## Part 3: Client Device Setup

### 3.1 Install Cloudflare One Agent

Users install the **Cloudflare One Agent** (also called "Cloudflare WARP" or "1.1.1.1 app").

#### Download Links

**Android:**
- App Store: Search "Cloudflare One Agent"
- Package name: `com.cloudflare.cloudflareoneagent`
- Direct link: [Google Play Store](https://play.google.com/store/apps/details?id=com.cloudflare.cloudflareoneagent)

**iOS:**
- App Store: Search "Cloudflare One Agent"
- App ID: `id6443476492`
- Direct link: [Apple App Store](https://apps.apple.com/app/id6443476492)

**Windows/macOS/Linux:**
- Download from: [https://1.1.1.1/](https://1.1.1.1/)
- Or direct download: [https://install.appcenter.ms/orgs/cloudflare/apps/1.1.1.1-windows-1/distribution_groups/release](https://install.appcenter.ms/orgs/cloudflare/apps/1.1.1.1-windows-1/distribution_groups/release)

---

### 3.2 Authenticate and Connect

After installing Cloudflare One Agent:

#### Step 1: Open App Settings
- **Mobile**: Tap hamburger menu (☰) → Settings
- **Desktop**: Click system tray icon → Settings

#### Step 2: Switch to Zero Trust Mode
1. Go to: **Account**
2. Click: **Login with Cloudflare Zero Trust**
3. Enter your team name: `noise-ztna`
4. Click **Next**

#### Step 3: Authenticate with Gmail
1. Select: **One-time PIN**
2. Enter your Gmail address
3. Check Gmail inbox for 6-digit PIN
4. Enter PIN to authenticate

#### Step 4: Device Posture Check
The app will automatically check:
- ✅ OS version
- ✅ Firewall enabled
- ✅ Disk encryption

If any checks fail, you'll see an error. Fix the issues and try again.

#### Step 5: Connect
1. Toggle the connection **ON**
2. Accept VPN connection prompt (mobile only)
3. Wait for connection to establish

You should see: **Connected** status.

---

## Part 4: Verification

### Verify VPS Exit IP

From the client device (with Cloudflare One Agent connected):

```bash
# Check public IP
curl ifconfig.me
```

**Expected output:** `65.109.210.232` (your VPS IP)

If you see a different IP, check:
- WARP Connector status on VPS: `sudo warp-cli status`
- Split Tunnels configuration
- Gateway Network Policy allows your user email

---

### Verify Device Enrollment

Admin can verify enrolled devices:

1. Go to: **My Team → Devices**
2. You should see enrolled devices with:
   - Device name
   - User email (Gmail)
   - OS version
   - Enrollment time
   - Posture status (✅ or ❌)

---

### Verify SSH/VNC Access

Open browser and visit:
- `https://ssh.yourdomain.com`
- `https://vnc-workstation.yourdomain.com`

You should be prompted to authenticate with Gmail. After authentication, you'll access the service.

---

## Troubleshooting

### Client Cannot Connect to WARP

**Symptoms:** Connection fails, stuck on "Connecting..."

**Solutions:**
1. Check WARP Connector status on VPS:
   ```bash
   sudo warp-cli status
   ```
   Should show: `Status: Connected`

2. Restart WARP Connector:
   ```bash
   sudo systemctl restart warp-svc
   sudo warp-cli connect
   ```

3. Check Split Tunnels configuration:
   - Verify VPS IP is excluded
   - Verify private networks are excluded

4. Check Gateway Network Policy:
   - Verify user email matches policy selector
   - Verify device posture checks pass

---

### Traffic Not Routing Through VPS

**Symptoms:** `curl ifconfig.me` shows ISP IP instead of VPS IP

**Solutions:**
1. Check WARP Connector is connected:
   ```bash
   sudo warp-cli status
   ```

2. Verify Gateway Network Policy allows your user:
   - Go to: **Traffic policies → Firewall policies → Network**
   - Check policy matches your email

3. Check WARP Connector logs:
   ```bash
   sudo journalctl -u warp-svc -f
   ```
   Look for errors related to routing or authentication

4. Verify Split Tunnels doesn't exclude too much:
   - Should only exclude VPS IP and private networks
   - Should NOT exclude public internet ranges

---

### Device Posture Check Fails

**Symptoms:** Cannot connect, see posture check error

**Solutions:**

**OS Version:**
- Update your operating system to meet minimum requirements
- macOS: 13.0+, Windows: 10 20H1+, Android: 10+, iOS: 15+

**Firewall:**
- **Windows**: Settings → Privacy & Security → Windows Security → Firewall & network protection → Turn ON
- **macOS**: System Preferences → Security & Privacy → Firewall → Turn ON
- **Linux**: `sudo ufw enable`

**Disk Encryption:**
- **Windows**: Enable BitLocker
- **macOS**: Enable FileVault
- **Linux**: Enable LUKS during installation

---

### WARP Connector Registration Fails

**Symptoms:** `warp-cli registration new` fails or shows error

**Solutions:**
1. Delete existing registration:
   ```bash
   sudo warp-cli registration delete
   ```

2. Try registering again:
   ```bash
   sudo warp-cli registration new
   ```

3. Check firewall allows WARP:
   ```bash
   sudo ufw status
   ```

4. Check internet connectivity:
   ```bash
   ping 1.1.1.1
   ```

---

### SSH/VNC Access Denied

**Symptoms:** Cannot access `ssh.yourdomain.com`, authentication fails

**Solutions:**
1. Verify Cloudflare Tunnel is running:
   ```bash
   sudo systemctl status cloudflared
   ```

2. Verify Access Application policy allows your email:
   - Go to: **Access → Applications**
   - Check policy selector matches your Gmail domain

3. Check tunnel routes are configured:
   - Go to: **Networks → Tunnels → vps-services**
   - Verify routes exist for each service

4. Check service is running on VPS:
   ```bash
   # SSH
   sudo systemctl status ssh
   
   # VNC (if using x11vnc)
   ps aux | grep vnc
   ```

---

### DNS Record Conflict Error

**Symptoms:** Cannot create tunnel route, see "DNS record already exists" error

**Solution:**
1. Go to: **Cloudflare Dashboard → DNS → Records**
2. Find the conflicting A/AAAA record for your subdomain (e.g., `ssh`, `vnc-workstation`)
3. Delete the record
4. Return to tunnel configuration and create route again

---

## Advanced Configuration

### View WARP Connector Logs

```bash
# Real-time logs
sudo journalctl -u warp-svc -f

# Last 100 lines
sudo journalctl -u warp-svc -n 100

# Enable debug logging
sudo warp-cli debug-log on
```

---

### Check Connected Devices

As admin:
1. Go to: **My Team → Devices**
2. View:
   - Device name
   - User email
   - OS version
   - Last seen
   - Posture status

---

### Useful Commands

**WARP Connector (VPS):**
```bash
sudo warp-cli status              # Connection status
sudo warp-cli connect             # Connect
sudo warp-cli disconnect          # Disconnect
sudo warp-cli account             # Account info
sudo warp-cli settings            # Current settings
sudo systemctl restart warp-svc   # Restart service
```

**Cloudflare Tunnel (VPS):**
```bash
sudo systemctl status cloudflared    # Tunnel status
sudo systemctl restart cloudflared   # Restart tunnel
sudo journalctl -u cloudflared -f    # View logs
```

---

## Architecture Benefits

### Compared to Traditional VPN

| Feature | Traditional VPN | WARP Connector + Zero Trust |
|---------|----------------|----------------------------|
| **Authentication** | Pre-shared key | Gmail + One-time PIN |
| **Device Checks** | None | OS, Firewall, Encryption |
| **Mobile Support** | ✅ | ✅ |
| **VPN Conflicts** | ❌ (one VPN only) | ✅ (single app) |
| **Exit IP** | VPS | VPS |
| **Obfuscation** | Basic | HTTPS to Cloudflare |
| **Management** | Manual config files | Centralized dashboard |

### Security Advantages

1. **Identity-based Access**: Users authenticate with Gmail, not shared keys
2. **Device Posture**: Automatically enforces security requirements
3. **No Config Files**: No risk of leaked VPN configs
4. **Centralized Control**: Admin can revoke access instantly
5. **Audit Logs**: See who connected, when, and from where

---

## What's Next?

### Add More Users
1. Share the team name: `noise-ztna`
2. Users install Cloudflare One Agent
3. Users authenticate with their Gmail
4. Automatically enrolled if email domain matches

### Monitor Activity
- **Devices**: My Team → Devices
- **Logs**: Logs → Gateway → Activity
- **Analytics**: Analytics → Gateway

### Advanced Policies
- **Time-based access**: Allow connections only during business hours
- **Location-based**: Restrict by country/region
- **Application filtering**: Block specific apps/protocols

---

## Summary

**What you've built:**
1. ✅ Cloudflare Zero Trust with Gmail authentication (One-time PIN)
2. ✅ Device posture checks (OS, Firewall, Encryption)
3. ✅ WARP Connector on VPS routing all traffic
4. ✅ Users connect with Cloudflare One Agent (single app, all platforms)
5. ✅ Exit IP shows VPS location (Germany)
6. ✅ SSH/VNC access via Cloudflare Tunnel (browser-based, secure)
7. ✅ (Optional) L2TP VPN for infrastructure management

**Result:**
- Users authenticate with Gmail
- Devices checked for security compliance
- All traffic routes through your VPS
- Works on Desktop + Mobile (no VPN conflicts)
- Centralized management and monitoring

---

## Appendix: L2TP VPN Setup

This section covers setting up L2TP/IPsec VPN for **infrastructure management** (your own access to VPS, virtual routers, xRDP, etc.). This is separate from the WARP Connector that end users use.

### Why L2TP Alongside WARP?

- **WARP Connector**: For end users, routes their internet traffic through VPS
- **L2TP VPN**: For you (admin), direct VPN access to VPS infrastructure

### Installation

```bash
# Run setup script
sudo ./setup_l2tp.sh
```

The script will:
- Install xl2tpd and strongSwan (IPsec)
- Configure PSK (Pre-Shared Key) and user credentials
- Setup UFW firewall rules
- Configure NAT for VPN clients

### Configuration

Edit `workstation.env` before running:

```bash
# L2TP Configuration
L2TP_PSK="your-strong-psk-key"
L2TP_USERNAME="admin"
L2TP_PASSWORD="your-strong-password"
```

### Client Setup

#### Windows
1. Settings → Network & Internet → VPN → Add VPN
2. VPN Provider: Windows (built-in)
3. Connection name: VPS L2TP
4. Server: 65.109.210.232
5. VPN type: L2TP/IPsec with pre-shared key
6. Pre-shared key: (your L2TP_PSK)
7. Username/Password: (your credentials)

#### macOS
1. System Preferences → Network → + (Add)
2. Interface: VPN
3. VPN Type: L2TP over IPsec
4. Server: 65.109.210.232
5. Authentication Settings:
   - User Authentication: Password
   - Machine Authentication: Shared Secret
   - Shared Secret: (your L2TP_PSK)

#### Linux
```bash
# Install client
sudo apt-get install network-manager-l2tp network-manager-l2tp-gnome

# Use NetworkManager GUI to add L2TP connection
# Or use the run_vpn.sh script
sudo ./run_vpn.sh
```

### Use Cases

**Virtual Router Access:**
```bash
# After connecting L2TP
./setup_virtual_router.sh
```

**xRDP/Windows Remote Desktop:**
- Connect via L2TP first
- Access internal RDP services

**Internal Network Management:**
- Bridge networks
- Access private services not exposed via Cloudflare Tunnel

### Troubleshooting L2TP

**Connection fails:**
```bash
# Check L2TP service
sudo systemctl status xl2tpd

# Check IPsec
sudo ipsec status

# View logs
sudo journalctl -u xl2tpd -f
```

**Firewall issues:**
```bash
# Verify UFW rules
sudo ufw status

# L2TP requires:
# - 500/udp (IKE)
# - 4500/udp (IPsec NAT-T)
# - 1701/udp (L2TP)
```

### Running Both WARP and L2TP

WARP Connector and L2TP VPN can coexist on the same VPS:

| Service | Purpose | Users | Port |
|---------|---------|-------|------|
| **WARP Connector** | Route end-user traffic | All authenticated users | N/A (Cloudflare network) |
| **L2TP VPN** | Infrastructure access | Admin only | 500, 4500, 1701/udp |

They don't conflict because:
- WARP uses Cloudflare's network (no local port needed)
- L2TP uses UDP ports 500, 4500, 1701
- Different routing tables
- Different use cases

---

**Result:**
- Users authenticate with Gmail
- Devices checked for security compliance
- All traffic routes through your VPS
- Works on Desktop + Mobile (no VPN conflicts)
- Centralized management and monitoring

---

## Support

For issues or questions:
- **Cloudflare Docs**: [https://developers.cloudflare.com/cloudflare-one/](https://developers.cloudflare.com/cloudflare-one/)
- **WARP Connector Docs**: [https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/)
- **Community**: [https://community.cloudflare.com/](https://community.cloudflare.com/)

---

## License

MIT License - See [LICENSE](LICENSE) file for details.
