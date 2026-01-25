# Cloudflare Zero Trust VPN Replacement

Replace traditional VPN with **Cloudflare WARP Connector** - route ALL client traffic through your VPS with Zero Trust security.

## What You Get

✅ **Complete VPN Replacement** - ALL client traffic (web, DNS, apps, games) routes through your VPS  
✅ **Direct VPS Access** - SSH and VNC via normal IP/port (no Cloudflare Tunnel needed)  
✅ **L2TP/IPSec Fallback** - Backup VPN for clients that don't support WARP  
✅ **Single Client App** - Cloudflare One Agent on all platforms (Desktop + Mobile)  
✅ **Zero Trust Security** - Identity-based access control + Gateway filtering  

---

## Architecture

```
Client Devices (Cloudflare One Agent)
     │
     │ (All traffic: DNS + Network + HTTP + Apps)
     │
     ▼
Cloudflare Edge (Gateway filtering)
     │
     │ (Encrypted WARP tunnel)
     │
     ▼
VPS - WARP Connector (65.109.210.232)
     │
     ├─→ Internet (ALL traffic: web, apps, games, DNS, etc.)
     │
     └─→ Direct SSH/VNC Management Access (port 22, VNC: 5910/5911)
```

**All users get:**
- **Complete traffic routing** - WARP Connector routes ALL client traffic through VPS (not just web)
- **System-wide VPN** - DNS queries, web browsing, apps, games, P2P, streaming
- Gateway filtering on all protocols (DNS/Network/HTTP)
- Direct SSH/VNC management access to VPS (standard ports)
- L2TP/IPSec fallback VPN option  

---

## Prerequisites

- **VPS**: Ubuntu 24.04, Public IP: `65.109.210.232`
- **Cloudflare Zero Trust**: Free tier (team: `noise-ztna`)
- **User Emails**: Gmail addresses for authorized users
- **No domain required**: Direct IP access for SSH/VNC

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

### 1.2 Create WARP Connector Tunnel

This creates the WARP Connector that routes client traffic through your VPS:

1. Go to: **Networks → Connectors → Cloudflare Tunnels**
2. Click **Create a tunnel**
3. Select **WARP Connector** (NOT Cloudflared)
4. You will be prompted to turn on these settings if not already enabled:
   - **Allow all Cloudflare One traffic to reach enrolled devices**
   - **Assign a unique IP address to each device**
   
   Click **Turn on** to enable both settings.

5. **Tunnel name**: `vps-traffic-routing` (or any name you prefer)
6. Click **Create tunnel**
7. Select **Linux** as the operating system
8. **Copy the installation commands** shown in the dashboard (you'll need these in Part 2)

The commands will look like:
```bash
# Install WARP client
curl https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
sudo apt-get update && sudo apt-get install cloudflare-warp

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv6.conf.all.forwarding=1

# Register WARP Connector
sudo warp-cli registration new --accept-tos
sudo warp-cli registration token <YOUR-TOKEN-HERE>
sudo warp-cli connect
```

9. Click **Next** after copying the commands

**Result**: WARP Connector tunnel is created and ready for installation on VPS.

---

### 1.3 Configure Device Enrollment/Connection Policy

Allow authorized users to enroll/connect their devices:

1. Go to: **Team & Resources → Devices → Management**
2. Under **Device enrollment**, ensure these settings:
   - **Device enrollment permissions**: Select **Manage**
3. Under **Access policies**, click **Create new policy**
4. Configure Policy:
   - **Policy name**: `vps-warp`
   - **Selector**: `Emails`
   - **Value**: `user1@gmail.com`
5. Click **Save**

---

### 1.4 Configure Split Tunnels

Prevent routing loops by excluding your VPS IP from WARP tunnel:

1. Go to: **Team & Resources → Devices → Device profiles**
2. Find the **Default** profile and click **Configure**
3. Scroll to **Split Tunnels** section
4. Click **Manage**
5. Ensure mode is: **Exclude IPs and domains**
6. Click **Add IP address** and add:
   ```
   65.109.210.232/32    (your VPS IP - for direct SSH/VNC access)
   10.0.0.0/8
   172.16.0.0/12
   192.168.0.0/16
   ```
7. Click **Save**

**Why**: Prevents infinite routing loops when connecting to VPS directly via SSH/VNC.

---

## Part 2: VPS Server Setup

### 2.1 Prepare VPS Configuration

SSH into your VPS and clone the repository:

```bash
# SSH into your VPS
ssh root@65.109.210.232

# Clone repository
git clone https://github.com/HosseinBeheshti/setupWS.git
cd setupWS
```

Now edit `workstation.env` and configure:

```bash
vim workstation.env
```

**Required Configuration**:
- `CLOUDFLARE_WARP_TOKEN`: Token from Part 1.2 (WARP Connector creation)
- `VPS_PUBLIC_IP`: Your VPS IP (auto-detected if not set)
- `VNC_USER_COUNT`: Number of VNC users
- `VNCUSER1_USERNAME`, `VNCUSER1_PASSWORD`, `VNCUSER1_PORT`: VNC user credentials
- `L2TP_IPSEC_PSK`, `L2TP_USERNAME`, `L2TP_PASSWORD`: L2TP fallback VPN credentials

**Example**:
```bash
CLOUDFLARE_WARP_TOKEN="eyJhIjo..."
VPS_PUBLIC_IP="65.109.210.232"
VNC_USER_COUNT=2
VNCUSER1_USERNAME="gateway"
VNCUSER1_PASSWORD="YourSecurePassword123!"
VNCUSER1_PORT="5910"
# ... etc
```

---

### 2.2 Run Automated Setup

The setup script performs complete VPS configuration automatically:

```bash
sudo ./setup_server.sh
```

**What This Script Does**:
1. ✅ Updates system packages
2. ✅ Installs Ubuntu Desktop + XFCE4
3. ✅ Installs TigerVNC Server
4. ✅ Installs L2TP/IPSec VPN (fallback)
5. ✅ Installs Cloudflare WARP Connector
6. ✅ Registers WARP Connector with your token
7. ✅ Creates systemd services for all VNC users
8. ✅ Starts all VNC servers automatically
9. ✅ Configures firewall (SSH, VNC ports, L2TP)
10. ✅ Verifies all services are running

**Duration**: Approximately 15-20 minutes (mostly installing desktop environment).

**After Setup Completes**:
- All services automatically started
- VNC servers running on configured ports
- WARP Connector registered and connected
- Firewall configured with proper rules

**Verify Installation**:
```bash
# Check WARP status
sudo warp-cli status

# Check VNC services
systemctl status vncserver@gateway.service
systemctl status vncserver@vncuser.service

# Check firewall rules
sudo ufw status
```

#### Register WARP Connector
```bash
# Accept terms of service
sudo warp-cli registration new --accept-tos

# Register with your tunnel token (from section 1.2)
sudo warp-cli registration token <YOUR-TOKEN-HERE>

# Connect WARP
sudo warp-cli connect

# Verify connection
sudo warp-cli status
# Should show: Status: Connected
```

#### Configure iptables for Traffic Forwarding (Optional)
```bash
# Allow forwarding between interfaces
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

### 3.2 Authenticate to Zero Trust

Connect your device to the Zero Trust organization:

1. Open **Cloudflare One Agent** (or WARP app)
2. Go to **Settings → Account**
3. Click **Login with Cloudflare Zero Trust**
4. Enter team name: `noise-ztna`
5. Select **One-time PIN**
6. Enter your Gmail address
7. Check Gmail for PIN code
8. Enter PIN to complete authentication
9. Toggle connection **ON**

**Device enrollment complete!** Your traffic now routes through VPS.

---

### 3.3 Access VPS Directly

#### SSH Access
```bash
# Direct SSH to VPS (no Cloudflare Tunnel needed)
ssh root@65.109.210.232

# Or with specific user
ssh username@65.109.210.232
```

**Note**: SSH traffic will route through Cloudflare WARP first, then exit from VPS to SSH port.

#### VNC Access
```bash
# Using any VNC client (check workstation.env for configured ports)
vncviewer 65.109.210.232:5910  # User 1 (gateway)
vncviewer 65.109.210.232:5911  # User 2 (vncuser)

# Or use built-in VNC clients:
# - Windows: Remote Desktop Connection (after VNC bridge setup)
# - macOS: Screen Sharing app  
# - Linux: Remmina, TigerVNC viewer
```

**VNC Password**: Use the password you set during VPS setup (section 2.2)  
**VNC Ports**: Configured in `workstation.env` (VNCUSER1_PORT=5910, VNCUSER2_PORT=5911)

---

### 3.4 L2TP/IPSec Fallback (Optional)

For devices that don't support WARP, use L2TP/IPSec:

**iOS:**
1. Settings → VPN → Add VPN Configuration
2. Type: L2TP
3. Server: `65.109.210.232`
4. Account: (from workstation.env)
5. Password: (from workstation.env)
6. Secret: (from workstation.env)

**Android:**
1. Settings → Network & Internet → VPN
2. Add VPN → L2TP/IPSec PSK
3. Server address: `65.109.210.232`
4. L2TP secret: (from workstation.env)
5. IPSec pre-shared key: (from workstation.env)

---

## Part 4: Verification

### For All Users

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

**Check WARP connection:**
```bash
# On client device (if warp-cli is installed)
warp-cli status
# Expected: Status: Connected, Team: noise-ztna

# Check routing table (Linux/macOS)
ip route show | grep CloudflareWARP
# or
netstat -rn | grep CloudflareWARP
```

### Test VPS Access

**SSH:**
```bash
ssh root@65.109.210.232
# Should connect successfully
```

**VNC:**
```bash
vncviewer 65.109.210.232:5910  # User 1
vncviewer 65.109.210.232:5911  # User 2
# Should prompt for password and connect
```

### Verify Gateway Filtering

1. Go to: **Logs → Gateway → DNS**
2. You should see DNS queries from `warp_connector@noise-ztna.cloudflareaccess.com`
3. Go to: **Logs → Gateway → Network**
4. You should see network traffic routed through VPS

---

## Troubleshooting

### Traffic Not Routing Through VPS

**Symptom**: `curl ifconfig.me` shows Cloudflare CGNAT IP instead of your VPS IP `65.109.210.232`

**Cause**: WARP Connector not properly configured or not routing traffic.

**Debug Steps:**

1. **On VPS, check WARP Connector status:**
```bash
sudo warp-cli status
# Expected: Status: Connected

sudo warp-cli account
# Expected: Shows your team name (noise-ztna)
```

2. **Check WARP Connector in dashboard:**
- Go to: **Networks → Connectors → Cloudflare Tunnels**
- Find your tunnel `vps-traffic-routing`
- Status should show: **Healthy** (green)
- If **Down** or **Inactive**, WARP Connector is not connected

3. **Restart WARP Connector:**
```bash
sudo warp-cli disconnect
sudo warp-cli connect
sudo warp-cli status
```

4. **Check IP forwarding:**
```bash
sysctl net.ipv4.ip_forward
sysctl net.ipv6.conf.all.forwarding
# Both should show = 1
```

5. **Check Gateway settings:**
- Go to: **Team & Resources → Devices → Device profiles → Default**
- Ensure **Service mode** is: **Gateway with WARP**
- Ensure these are enabled:
  - Allow all Cloudflare One traffic to reach enrolled devices
  - Assign a unique IP address to each device

6. **Check client WARP connection:**
```bash
# On client device
warp-cli status
# Should show: Status: Connected, Team: noise-ztna
```

---

### Cannot Access VPS via SSH/VNC

**Symptom**: Cannot connect to `ssh root@65.109.210.232` or VNC

**Cause**: VPS IP not excluded from WARP tunnel, or services not running.

**Debug Steps:**

1. **Check Split Tunnels:**
- Go to: **Team & Resources → Devices → Device profiles → Default**
- Click **Configure → Split Tunnels → Manage**
- Verify `65.109.210.232/32` is in the **Exclude** list
- If not, add it and wait 1-2 minutes for policy to sync

2. **On VPS, check services:**
```bash
# Check SSH
sudo systemctl status ssh
sudo netstat -tlnp | grep :22

# Check VNC
sudo netstat -tlnp | grep :59
# Should show ports 5910, 5911, etc.
# If not listening, start VNC:
vncserver :1 -geometry 1920x1080 -depth 24  # :1 = port 5901+9 = 5910
vncserver :2 -geometry 1920x1080 -depth 24  # :2 = port 5901+10 = 5911
```

3. **Check firewall:**
```bash
sudo ufw status
# Should show:
# 22/tcp ALLOW
# 5910/tcp ALLOW (VNC-gateway)
# 5911/tcp ALLOW (VNC-vncuser)
```

4. **Test from client:**
```bash
# Test SSH connectivity
telnet 65.109.210.232 22
# Should connect

# Test VNC connectivity
telnet 65.109.210.232 5910  # User 1
telnet 65.109.210.232 5911  # User 2
# Should connect
```

---

### WARP Connector Shows "Disconnected"

**Symptom**: `sudo warp-cli status` shows "Disconnected" or "Error"

**Cause**: Registration issue or network connectivity problem.

**Debug Steps:**

1. **Re-register WARP Connector:**
```bash
# Delete existing registration
sudo warp-cli registration delete

# Register again with tunnel token
sudo warp-cli registration new --accept-tos
sudo warp-cli registration token <YOUR-TOKEN-FROM-SECTION-1.2>
sudo warp-cli connect
```

2. **Check network connectivity:**
```bash
# Ping Cloudflare
ping 1.1.1.1

# Check if WARP ports are accessible
sudo ss -tulpn | grep warp-svc
```

3. **Check WARP logs:**
```bash
# View WARP service logs
sudo journalctl -u warp-svc -f

# Look for errors related to connection or registration
```

4. **Reinstall WARP:**
```bash
sudo apt-get remove --purge cloudflare-warp
sudo apt-get autoremove
sudo apt-get update
sudo apt-get install cloudflare-warp

# Re-register (section 2.3)
```

---

### Device Enrollment Fails

**Symptom**: Cannot enroll device with Zero Trust

**Cause**: Email not in allowed list or enrollment settings incorrect.

**Debug Steps:**

1. **Check enrollment policy:**
- Go to: **Team & Resources → Devices → Device profiles → Management**
- Verify your email domain/address is in enrollment rules

2. **Check One-time PIN:**
- Go to: **Integrations → Identity providers**
- Verify **One-time PIN** is enabled

3. **Try different authentication:**
- Use incognito/private browser window
- Clear browser cache
- Try different email address

---

### Gateway Logs Show No Traffic

**Symptom**: No logs appearing in Gateway DNS/Network logs

**Cause**: WARP Connector not properly routing traffic through Gateway.

**Debug Steps:**

1. **Verify Gateway settings:**
- Go to: **Team & Resources → Devices → Device profiles → Default**
- Ensure **Service mode** is: **Gateway with WARP** (NOT Gateway with DoH)

2. **Check if traffic is being filtered:**
```bash
# On client device
dig @172.64.36.1 cloudflare.com
# Should return results from Gateway DNS resolver
```

3. **Test DNS resolution:**
```bash
nslookup cloudflare.com
# Should use 172.64.36.1 or 172.64.36.2
```

4. **Check device profile assignment:**
- Go to: **Team & Resources → Devices**
- Find your device
- Check which profile is applied (should be Default or custom WARP Connector profile)

---

## Monitoring

**View enrolled devices:**
- Go to: **Team & Resources → Devices**
- See all devices connected to Zero Trust

**View WARP Connector status:**
- Go to: **Networks → Connectors → Cloudflare Tunnels**
- Check `vps-traffic-routing` tunnel health
- View connected devices and traffic statistics

**View Gateway logs:**
- Go to: **Logs → Gateway → DNS**
  - Monitor DNS queries from `warp_connector@noise-ztna.cloudflareaccess.com`
- Go to: **Logs → Gateway → Network**
  - Monitor network traffic routed through VPS
- Go to: **Logs → Gateway → HTTP**
  - Monitor web browsing activity

**On VPS, monitor WARP Connector:**
```bash
# Check WARP status
sudo warp-cli status

# Check WARP statistics
sudo warp-cli warp-stats

# View system logs
sudo journalctl -u warp-svc -f
```

---

## Summary

| Feature | Details |
|---------|---------|
| **Authentication** | Gmail + One-time PIN |
| **SSH Access** | Direct: `ssh root@65.109.210.232` |
| **VNC Access** | Direct: `vncviewer 65.109.210.232:5910` (or 5911, see workstation.env) |
| **Traffic Routing** | ALL traffic routes through VPS (65.109.210.232) |
| **Exit IP** | VPS IP (65.109.210.232) |
| **Platforms** | Windows, macOS, Linux, Android, iOS |
| **Fallback VPN** | L2TP/IPSec available |

**Key Features:**
- ✅ Complete VPN replacement with WARP Connector
- ✅ System-wide traffic routing (DNS + Network + HTTP)
- ✅ Direct SSH/VNC access (no Cloudflare Tunnel needed)
- ✅ Gateway filtering and logging
- ✅ Identity-based device enrollment
- ✅ Works on all platforms without conflicts

---

## Next Steps

1. ✅ **Part 1**: Create WARP Connector tunnel in Cloudflare dashboard
2. ✅ **Part 2**: Install WARP Connector on VPS step-by-step (DO NOT use setup_server.sh)
3. ✅ **Part 3**: Install Cloudflare One Agent on client devices
4. ✅ **Part 4**: Verify traffic routes through VPS
5. 📊 **Monitor**: Check Gateway logs and WARP Connector health

**Your WARP Connector VPN is ready!**
