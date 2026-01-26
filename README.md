# Cloudflare Zero Trust VPN Replacement

Replace traditional VPN with **Cloudflare WARP Connector** - route ALL client traffic through your VPS with Zero Trust security.

## What You Get

✅ **Complete VPN Replacement** - ALL client traffic (web, DNS, apps, games) routes through your VPS  
✅ **SSH Access** - Secure SSH access via Cloudflare Tunnel  
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
     └─→ SSH Access via Cloudflare Tunnel (no public ports needed)
```

**All users get:**
- **Complete traffic routing** - WARP Connector routes ALL client traffic through VPS (not just web)
- **System-wide VPN** - DNS queries, web browsing, apps, games, P2P, streaming
- Gateway filtering on all protocols (DNS/Network/HTTP)
- Secure SSH access through Cloudflare Tunnel  

---

## Prerequisites

- **VPS**: Ubuntu 24.04, Public IP: `65.109.210.232`
- **Cloudflare Zero Trust**: Free tier (team: `noise-ztna`)
- **User Emails**: Gmail addresses for authorized users
- **Domain**: Required for SSH access via Cloudflare Tunnel (or use Quick Tunnels)

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
8. **Save tunnel token in your workstation.env**
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

Note: include this policy in the **Device enrollment permissions**

---

### 1.4 Configure Split Tunnels

Configure split tunnels to route all traffic through WARP:

1. Go to: **Team & Resources → Devices → Device profiles**
2. Find the **Default** profile and click **Configure**
3. Scroll to **Split Tunnels** section
4. Click **Manage**
5. Ensure mode is: **Exclude IPs and domains**
6. Only exclude private networks:
   ```
   10.0.0.0/8
   172.16.0.0/12
   192.168.0.0/16
   ```
7. Click **Save**

**Note**: Do NOT exclude your VPS IP (65.109.210.232). All traffic, including SSH, will route through Cloudflare.

---

## Part 2: VPS Server Setup

### 2.1 Prepare VPS Configuration

SSH into your VPS and clone the repository
then edit `workstation.env` and configure:
```bash
# Clone repository
git clone https://github.com/HosseinBeheshti/setupWS.git
cd setupWS
vim workstation.env
```

---

### 2.2 Run Automated Setup

The setup script performs complete VPS configuration automatically:

```bash
sudo ./setup_ztna.sh
```

**What This Script Does**:
1. ✅ Updates system packages
2. ✅ Installs Cloudflare WARP Connector
3. ✅ Registers WARP Connector with your token
4. ✅ Enables IP forwarding
5. ✅ Configures firewall
6. ✅ Verifies services are running

**Duration**: Approximately 5-10 minutes.

**After Setup Completes**:
- WARP Connector registered and connected
- Firewall configured with proper rules
- IP forwarding enabled

**Verify Installation**:
```bash
# Check WARP status
sudo warp-cli status

# Check IP forwarding
sysctl net.ipv4.ip_forward

# Check firewall rules
sudo ufw status
```
---

## Part 3: Configure SSH Access

Since all traffic routes through Cloudflare WARP (including SSH), you need to create an application in Cloudflare Zero Trust to access your server via SSH.

### 3.1 Create SSH Application

1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
2. Navigate to: **Team & Resources → Applications → Add an application**
3. Select **Private Network** (or **Self-hosted** for domain-based access)
4. Configure Application:
   - **Application name**: `SSH to VPS`
   - **Session duration**: `24 hours` (or your preference)
5. Under **Application configuration**:
   - **Type**: `SSH`
   - **URL**: Use your VPS hostname or create a subdomain
     - Option 1: Use Quick Tunnels (no domain required)
     - Option 2: Use a domain like `ssh.yourdomain.com` pointing to your tunnel
6. Under **Private Network**:
   - **IP/CIDR**: `65.109.210.232/32` (your VPS private IP as seen from WARP)
   - **Port**: `22`
7. Click **Next**
8. **Add a policy**:
   - **Policy name**: `Allow SSH Access`
   - **Action**: `Allow`
   - **Configure rules**:
     - **Selector**: `Emails`
     - **Value**: `user1@gmail.com` (your email)
9. Click **Add policy** then **Done**

### 3.2 Access SSH via Cloudflare

**Method 1: Using cloudflared CLI (Recommended)**

Install cloudflared on your client:
```bash
# Linux/macOS
brew install cloudflare/cloudflare/cloudflared

# Or download from: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/
```

Configure SSH in your `~/.ssh/config`:
```bash
Host vps-ssh
  HostName 65.109.210.232
  ProxyCommand cloudflared access ssh --hostname ssh.yourdomain.com
  User root
```

Connect:
```bash
ssh vps-ssh
```

**Method 2: Using Browser-based SSH**

1. Go to your application URL (e.g., `ssh.yourdomain.com`)
2. Authenticate with your email
3. Use the web-based SSH terminal

### 3.3 Alternative: Quick Tunnel for SSH

If you don't have a domain, use a Quick Tunnel:

On your VPS, create a tunnel for SSH:
```bash
# Install cloudflared on VPS if not already installed
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
chmod +x cloudflared
sudo mv cloudflared /usr/local/bin/

# Create a quick tunnel for SSH
cloudflared tunnel --url ssh://localhost:22
```

This will give you a temporary URL like `https://random-name.trycloudflare.com`. You can then access SSH through this URL using cloudflared on your client.

---

## Part 4: Verification

### Understanding IP Routing

**Important**: When connected to WARP, your traffic routes through Cloudflare's network:

```bash
curl ifconfig.me
# Shows: 2a09:bac1:28a0:88::3f:77 (Cloudflare CGNAT IP)
```

This is **expected behavior**. Your traffic flows:
- Client → Cloudflare Edge → WARP Connector on VPS → Internet

The exit IP you see is Cloudflare's IP because:
1. WARP encrypts traffic to Cloudflare Edge
2. Cloudflare Edge routes to your VPS WARP Connector
3. VPS routes traffic to internet through Cloudflare's network

**To verify VPS routing is working:**

### For All Users

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

**Check DNS routing:**
```bash
nslookup cloudflare.com
# Expected: DNS server should be 172.64.36.1 or 172.64.36.2 (Gateway resolver)
```

**Verify traffic flows through VPS:**
```bash
# On VPS, monitor traffic
sudo tcpdump -i any -n | grep "your-client-warp-ip"
```

### Test SSH Access

**Using cloudflared:**
```bash
ssh vps-ssh
# Should authenticate via browser and connect
```

### Verify Gateway Filtering

1. Go to: **Logs → Gateway → DNS**
2. You should see DNS queries from `warp_connector@noise-ztna.cloudflareaccess.com`
3. Go to: **Logs → Gateway → Network**
4. You should see network traffic routed through VPS

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

### Understanding Cloudflare IP vs VPS IP

**Why you see Cloudflare IP (2a09:bac1:28a0:88::3f:77):**

When you run `curl ifconfig.me` while connected to WARP, you see Cloudflare's CGNAT IP, not your VPS IP. This is **expected** because:

1. Your traffic is encrypted and sent to Cloudflare Edge
2. Cloudflare Edge routes to your VPS WARP Connector
3. VPS forwards traffic back through Cloudflare's network to the internet
4. External sites see Cloudflare's IP, not your VPS IP

**Traffic Flow:**
```
Your Device → WARP Client → Cloudflare Edge → WARP Connector (VPS) → Cloudflare Network → Internet
                                                                              ↑
                                                              External sites see this IP (Cloudflare)
```

**This is how WARP Connector works by design**. Your VPS routes traffic, but the exit IP is managed by Cloudflare's infrastructure.

### Cannot Access VPS via SSH

**Symptom**: Cannot connect to SSH after enabling WARP

**Cause**: All traffic routes through WARP tunnel, direct IP access is blocked.

**Solution**: Use Cloudflare Tunnel for SSH access (see Part 3 above).

---

### Traffic Not Routing Through VPS

**Symptom**: Traffic not going through WARP at all

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
| **SSH Access** | Via Cloudflare Tunnel + cloudflared CLI |
| **Traffic Routing** | ALL traffic routes through VPS via WARP Connector |
| **Exit IP** | Cloudflare CGNAT IP (managed by Cloudflare) |
| **Platforms** | Windows, macOS, Linux, Android, iOS |

**Key Features:**
- ✅ Complete VPN replacement with WARP Connector
- ✅ System-wide traffic routing (DNS + Network + HTTP)
- ✅ Secure SSH access via Cloudflare Tunnel
- ✅ Gateway filtering and logging
- ✅ Identity-based device enrollment
- ✅ Works on all platforms without conflicts

---

## Next Steps

1. ✅ **Part 1**: Create WARP Connector tunnel in Cloudflare dashboard
2. ✅ **Part 2**: Install WARP Connector on VPS with setup script
3. ✅ **Part 3**: Configure SSH access via Cloudflare Tunnel
4. ✅ **Part 4**: Install Cloudflare One Agent on client devices
5. ✅ **Part 5**: Verify traffic routes through VPS
6. 📊 **Monitor**: Check Gateway logs and WARP Connector health

**Your WARP Connector VPN is ready!**
