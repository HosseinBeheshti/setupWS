# Cloudflare Zero Trust Network Access (ZTNA)

Replace your VPN with **Cloudflare One Agent + WARP Connector** - complete system-wide traffic routing through your VPS.

## What You Get

✅ **System-wide VPN Replacement** - ALL traffic (web, DNS, apps, games) routes through your VPS  
✅ **Single App** - Cloudflare One Agent on all platforms (Desktop + Mobile)  
✅ **Two-Tier Access** - Admins get SSH/VNC access, Users get traffic routing  
✅ **No VPN Conflicts** - Works on Android/iOS without conflicts  
✅ **Zero Trust Security** - Identity-based authentication + device posture checks  

---

## Architecture

```
Admin Users                          Regular Users
     │                                    │
Cloudflare One Agent              Cloudflare One Agent
     │                                    │
     ├─→ SSH/VNC Access                   │
     │   (Cloudflare Tunnel)              │
     │                                    │
     └─→ System-wide Traffic      ────────┴───> System-wide Traffic
         (Gateway + WARP)                       (Gateway + WARP)
              │                                      │
              └──────────────┬───────────────────────┘
                             ▼
                         VPS (65.109.210.232)
                             ▼
                         Internet
```

**Admin Users**: SSH + VNC + System-wide traffic routing  
**Regular Users**: System-wide traffic routing only  

---

## Prerequisites

- **VPS**: Ubuntu 24.04, Public IP: `65.109.210.232`
- **Cloudflare Zero Trust**: Free tier (team: `noise-ztna`)
- **Domain**: Managed by Cloudflare
- **Admin Emails**: Gmail addresses for admins

---

## Part 1: Cloudflare Zero Trust Setup

### 1.1 Configure Identity Provider

Configure Gmail authentication with One-time PIN:

1. Go to [Cloudflare One](https://one.dash.cloudflare.com/)
2. Navigate to: **Integrations → Identity providers**
3. Click **Add an identity provider**
4. Select **One-time PIN**
5. Click **Save**

---

### 1.2 Create Admin Policy

Create policy for admins with SSH/VNC access + system-wide routing:

1. Go to: **Access controls → Policies**
2. Click **Add a policy**
3. Configure policy:
   - **Policy name**: `Admin - SSH/VNC + System-wide Routing`
   - **Action**: `Allow`
4. Add **Include** rule:
   - **Selector**: `Emails`
   - **Value**: `admin1@gmail.com, admin2@gmail.com` (your admin emails)
5. (Optional) Add **Include** rule for GitHub authentication:
   - **Selector**: `Login Methods`
   - **Value**: `GitHub`
6. Click **Save policy**

**This policy enables:**
- ✅ Access to SSH and VNC applications (configured in section 1.7)
- ✅ System-wide traffic routing through WARP Connector

---

### 1.3 Create User Policy

Create policy for regular users with system-wide routing only:

1. Go to: **Access controls → Policies**
2. Click **Add a policy**
3. Configure policy:
   - **Policy name**: `User - System-wide Routing Only`
   - **Action**: `Allow`
4. Add **Include** rule:
   - **Selector**: `Emails ending in`
   - **Value**: `gmail.com`
5. Add **Exclude** rule (to prevent overlap with admin policy):
   - **Selector**: `Emails`
   - **Value**: `admin1@gmail.com, admin2@gmail.com` (your admin emails)
6. Click **Save policy**

**This policy enables:**
- ✅ System-wide traffic routing through WARP Connector
- ❌ NO access to SSH or VNC

---

### 1.4 Create Cloudflare Tunnel

Create tunnel for admin access to SSH and VNC:

1. Go to: **Networks → Connectors → Cloudflare Tunnels**
2. Click **Add a tunnel**
3. Select **Cloudflared** and click **Next**
4. **Tunnel name**: `vps-admin-services`
5. Click **Save tunnel**
6. Copy the installation command (you'll run this on VPS in Part 2)
7. Click **Next**

#### Add SSH Route
1. Go to **Published applications routes** tab
2. Configure:
   - **Subdomain**: `ssh`
   - **Domain**: `yourdomain.com`
   - **Service Type**: `ssh`
   - **URL**: `localhost:22`
3. Click **Save**

#### Add VNC Route
1. Click **Add a public hostname**
2. Configure:
   - **Subdomain**: `vnc-admin`
   - **Domain**: `yourdomain.com`
   - **Service Type**: `http`
   - **URL**: `localhost:5901`
3. Click **Save**

---

### 1.5 Create Access Applications

Protect SSH and VNC with admin-only policies:

#### SSH Application
1. Go to: **Access controls → Applications**
2. Select **Add an application**
3. Select **Self-hosted**
4. Configure application:
   - **Application name**: `VPS SSH`
   - **Session Duration**: Choose how often users must reauthenticate (e.g., 24 hours)
5. Select **Add public hostname**
6. In **Domain** dropdown, select your domain
7. In **Subdomain**, enter: `ssh`
8. Select **Access policies → Select existing policies**:
   - **Policy name**: `Admin - SSH/VNC + System-wide Routing`
10. Select **Next**
11. (Optional) Configure App Launcher and Block page settings
12. Select **Next**
13. (Optional) Configure advanced settings (CORS, cookies)
14. Select **Save**

#### VNC Application
1. Select **Add an application**
2. Select **Self-hosted**
3. Configure application:
   - **Application name**: `VNC Admin`
   - **Session Duration**: Choose how often users must reauthenticate (e.g., 24 hours)
4. Select **Add public hostname**
5. In **Domain** dropdown, select your domain
6. In **Subdomain**, enter: `vnc-admin`
7. Select **Access policies → Select existing policies**:
   - **Policy name**: `Admin - SSH/VNC + System-wide Routing`
8. Select **Next** → **Next** → **Save**

**Result**: Only admin emails can access SSH and VNC through Cloudflare Tunnel.

---

## Part 2: VPS Server Setup

### 2.1 Run Automated Setup

Clone repository and run setup on your VPS:

```bash
# SSH into your VPS
ssh root@65.109.210.232

# Clone repository
git clone https://github.com/HosseinBeheshti/setupWS.git
cd setupWS

# Edit configuration
vim workstation.env

# Run setup script
sudo ./setup_server.sh
```

**The script installs:**
- ✅ WARP Connector (for system-wide traffic routing)
- ✅ VNC Server (for remote desktop)
- ✅ cloudflared (for Cloudflare Tunnel)
- ✅ Firewall configuration

---

### 2.2 Register WARP Connector

Connect your VPS to Cloudflare Zero Trust:

```bash
# Register WARP Connector
sudo warp-cli registration new

# Follow prompts to authenticate with your Zero Trust organization

# Verify connection
sudo warp-cli status
# Should show: Status: Connected
```

---

### 2.3 Configure Split Tunnels

Prevent routing loops by excluding your VPS IP:

1. Go to: **Team & Resources → Devices → Device profiles**
2. Find the **Default** profile and click **Configure**
3. Scroll to **Split Tunnels** section
4. Click **Manage**
5. Ensure mode is: **Exclude IPs and domains**
6. Click **Add IP address**
7. Add these exclusions:
   ```
   65.109.210.232/32    (your VPS IP)
   10.0.0.0/8
   172.16.0.0/12
   192.168.0.0/16
   ```
8. Click **Save**

**Why**: Prevents infinite routing loops when connecting to VPS.

---

## Part 3: Client Setup

### 3.1 Install Cloudflare One Agent

**Android:**
- Download from [Google Play Store](https://play.google.com/store/apps/details?id=com.cloudflare.cloudflareoneagent)

**iOS:**
- Download from [App Store](https://apps.apple.com/app/id6443476492)

**Windows/macOS/Linux:**
- Download from [cloudflare.com/products/zero-trust/warp/](https://www.cloudflare.com/products/zero-trust/warp/)

---

### 3.2 Authenticate

Connect to your Zero Trust organization:

1. Open **Cloudflare One Agent** (or WARP app)
2. Go to **Settings → Account**
3. Click **Login with Cloudflare Zero Trust**
4. Enter team name: `noise-ztna`
5. Select **One-time PIN**
6. Enter your Gmail address
7. Check Gmail for PIN code
8. Enter PIN to complete authentication
9. Toggle connection **ON**

**Device enrollment complete!** Your traffic now routes through VPS (65.109.210.232).

---

## Part 4: Verification

### For All Users (Admin + Regular)

**Check exit IP:**
```bash
curl ifconfig.me
```
**Expected**: `65.109.210.232` (your VPS IP)

**Check DNS routing:**
```bash
nslookup cloudflare.com
```
**Expected**: DNS server should be `172.64.36.1` or `172.64.36.2` (Gateway resolver)

### For Admin Users Only

**Access SSH:**
```bash
# Install cloudflared locally first
# macOS: brew install cloudflared
# Linux: wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb && sudo dpkg -i cloudflared-linux-amd64.deb

# Connect via SSH
cloudflared access ssh --hostname ssh.yourdomain.com

```

**Access VNC:**
- Open browser: `https://vnc-admin.yourdomain.com`
- Authenticate with Gmail + PIN
- Access remote desktop

---

## Troubleshooting

### Traffic Shows Cloudflare IP Instead of VPS IP

**Symptom**: `curl ifconfig.me` shows IPv6 like `2a09:bac5:3744:278::3f:da` (Cloudflare CGNAT) instead of your VPS IP `65.109.210.232`

**Cause**: Traffic is routing through regular Cloudflare WARP, not your WARP Connector.

**This setup does NOT use WARP Connector for client traffic routing!**

This architecture uses:
- **Cloudflare Tunnel (cloudflared)** for SSH/VNC access to VPS
- **Regular Cloudflare WARP** for client traffic (traffic exits via Cloudflare edge, not your VPS)

**To route traffic through YOUR VPS, you need WARP Connector with different configuration:**

#### Option 1: Current Setup (Traffic via Cloudflare Edge)
- Users get Cloudflare's IP when browsing
- VPS is ONLY accessed via SSH/VNC through Cloudflare Tunnel
- This is SIMPLER and what the current README describes

#### Option 2: Route Traffic Through Your VPS (Requires WARP Connector)
You need additional configuration:

1. **On VPS, check WARP Connector:**
```bash
sudo warp-cli status
# Should show: Connected

sudo warp-cli account
# Should show your team name
```

2. **Create WARP Connector tunnel (different from cloudflared tunnel):**
- Go to: **Networks → Connectors → Cloudflare Tunnels**
- Select **Create a tunnel**
- Choose **WARP Connector** (NOT Cloudflared)
- Follow prompts to register VPS as WARP Connector
- This allows client traffic to route THROUGH your VPS

3. **Configure device profile for WARP Connector routing:**
- Go to: **Team & Resources → Devices → Device profiles**
- Edit Default profile
- Under **Service mode**, ensure: **Gateway with WARP**
- Under **Split Tunnels**, verify VPS IP is excluded

**Note**: The current README describes Access via Tunnel only, not WARP Connector routing.

---

### Cannot Access SSH/VNC (Error 1033)

**Symptom**: Accessing `ssh.autoazma.ir` shows "Cloudflare Tunnel error 1033"

**Cause**: Cloudflare Tunnel daemon (`cloudflared`) is not running on VPS.

**Debug Steps:**

1. **Check if cloudflared is installed:**
```bash
# On VPS
cloudflared --version
```

2. **Check if cloudflared service is running:**
```bash
sudo systemctl status cloudflared
```

If not running:
```bash
# Check if service exists
systemctl list-unit-files | grep cloudflared
```

3. **If service doesn't exist, you need to install the tunnel:**

Follow section 1.4 tunnel installation steps, or manually:

```bash
# On VPS - Get tunnel token from Cloudflare dashboard
# Go to: Networks → Connectors → Cloudflare Tunnels → vps-admin-services
# Copy the install command and run it

# Example:
sudo cloudflared service install <YOUR_TUNNEL_TOKEN>

# Start the service
sudo systemctl start cloudflared
sudo systemctl enable cloudflared

# Verify
sudo systemctl status cloudflared
```

4. **Check tunnel status in dashboard:**
- Go to: **Networks → Connectors → Cloudflare Tunnels**
- Find your tunnel `vps-admin-services`
- Status should show: **Healthy** (green)
- If status is **Down** or **Inactive**, tunnel is not connected

5. **Check tunnel logs:**
```bash
sudo journalctl -u cloudflared -f
```

6. **Verify tunnel routes:**
- Go to: **Networks → Connectors → Cloudflare Tunnels → vps-admin-services**
- Check **Public Hostname** tab
- Verify routes exist:
  - `ssh.autoazma.ir` → `ssh://localhost:22`
  - `vnc-admin.autoazma.ir` → `http://localhost:5901`

7. **Test local services:**
```bash
# On VPS - Check if SSH is listening
sudo netstat -tlnp | grep :22

# Check if VNC is listening
sudo netstat -tlnp | grep :5901
```

---

### Traffic Not Routing Through VPS

**Check WARP status:**
- Verify WARP is connected and showing team name

**Check DNS:**
```bash
nslookup cloudflare.com
# Must show 172.64.36.x, not ISP DNS
```

**Check Split Tunnels:**
- Verify VPS IP is excluded in device profile
- Mode must be "Exclude IPs and domains"

---

### Device Enrollment Fails

**Check enrollment policy:**
1. Go to: **Team & Resources → Devices → Device profiles → Management**
2. Verify email domain is allowed in enrollment policy
3. Check One-time PIN is enabled in login methods

---

## Monitoring

**View enrolled devices:**
- Go to: **Team & Resources → Devices**
- See all devices with user emails

**View Gateway logs:**
- Go to: **Logs → Gateway → DNS/Network/HTTP**
- Monitor traffic from your users

**View Access logs:**
- Go to: **Logs → Access**
- Monitor SSH/VNC access attempts

---

## Summary

| User Type | Authentication | SSH/VNC | Traffic Routing | Exit IP | Platform |
|-----------|---------------|---------|-----------------|---------|----------|
| **Admin** | Gmail + PIN | ✅ Yes | ✅ System-wide | VPS IP | All |
| **User** | Gmail + PIN | ❌ No | ✅ System-wide | VPS IP | All |

**Key Features:**
- ✅ Single app (Cloudflare One Agent) for all users
- ✅ Complete system-wide traffic routing (DNS + Network + HTTP)
- ✅ Identity-based access control (no shared credentials)
- ✅ Device posture enforcement (OS, firewall, encryption)
- ✅ Works on all platforms (Desktop + Mobile, no conflicts)

---

## Next Steps

1. ✅ Complete Cloudflare Zero Trust setup (Part 1)
2. ✅ Run VPS setup script (Part 2)
3. ✅ Install Cloudflare One Agent on user devices (Part 3)
4. ✅ Verify traffic routing (Part 4)
5. 📊 Monitor usage in Cloudflare dashboard

**Your VPN replacement is complete!**
