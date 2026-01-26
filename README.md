# Cloudflare Zero Trust VPN Replacement

Replace traditional VPN with **Cloudflare WARP Connector** - route ALL client traffic through your VPS with Zero Trust security.

## What You Get

✅ **Complete VPN Replacement** - ALL client traffic (web, DNS, apps, games) routes through your VPS  
✅ **SSH Access** - Secure SSH access via Cloudflare Tunnel  
✅ **Single Client App** - Cloudflare One Agent on all platforms (Desktop + Mobile)  
✅ **Zero Trust Security** - Identity-based access control + Gateway filtering  

---

## Architecture

⚠️ **IMPORTANT**: WARP Connector by itself does **NOT** route internet traffic through your VPS. It only provides access to private networks/services on the VPS.

**Default WARP Connector behavior:**
```
Client Devices (Cloudflare One Agent)
     │
     │ (All traffic)
     │
     ▼
Cloudflare Edge (Gateway filtering)
     │
     ├─→ Internet (Direct from Cloudflare - NOT through VPS)
     │
     └─→ VPS - WARP Connector (only for accessing VPS services like SSH)
```

**To use VPS as exit node (true VPN), you need additional configuration:**
```
Client Devices (Cloudflare One Agent)
     │
     │ (All traffic: DNS + Network + HTTP + Apps)
     │
     ▼
Cloudflare Edge (Gateway filtering)
     │
     │ (Routes to VPS via WARP Connector)
     │
     ▼
VPS - WARP Connector + NAT/Routing (65.109.210.232)
     │
     ├─→ Internet via VPS IP (requires NAT and routing rules)
     │
     └─→ SSH Access via Cloudflare Access
```

**What you need for true VPN functionality:**
- ✅ WARP Connector installed on VPS
- ✅ NAT (masquerading) configured on VPS
- ✅ Routing rules to force traffic through VPS
- ✅ Split tunnel configuration to route 0.0.0.0/0 through WARP
- Gateway filtering on all protocols (DNS/Network/HTTP)
- Secure SSH access through Cloudflare Access  

---

## Prerequisites

- **VPS**: Ubuntu 24.04, Public IP: `65.109.210.232`
- **Cloudflare Zero Trust**: Free tier (team: `noise-ztna`)
- **User Emails**: Gmail addresses for authorized users
- **WARP Client**: Required on all devices for SSH and traffic routing

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

### 1.2.1 Add VPS IP to Tunnel Routes

**Important**: Before you can create a target for SSH access, you must add your VPS IP to the tunnel routes:

1. Go to: **Networks → Connectors → Cloudflare Tunnels**
2. Find your `vps-traffic-routing` tunnel and click on it
3. Click on the **CIDR** or **Private Networks** tab
4. Click **Add a CIDR** or **Add IP/CIDR**
5. Enter your VPS IP: `65.109.210.232/32`
6. Click **Save**

**Why**: This tells Cloudflare that traffic to this IP should route through your WARP Connector. Without this, the IP won't appear when creating targets in Part 3.

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

Configure SSH Access
Since all traffic routes through Cloudflare WARP (including SSH), you need to configure Access for Infrastructure to securely access your server via SSH.

### 1.5 Add a Target

First, create a target that represents your SSH server:

1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
2. Navigate to: **Access controls → Targets**
3. Select **Add a target**
4. Configure Target:
   - **Target hostname**: `vps-server` (or any friendly name)
   - **IP addresses**: Enter `65.109.210.232` 
   - The IP should appear in the dropdown (you added it in section 1.2.1)
   - Select the IP and virtual network (likely `default`)
5. Click **Add target**

**Note**: If the IP doesn't appear in the dropdown, verify:
- You completed section 1.2.1 (added IP to tunnel routes)
- Go to **Networks → Routes** and confirm `65.109.210.232` is listed
- Your WARP Connector tunnel is **Healthy**

### 1.6 Create Infrastructure Application

Now create an infrastructure application to secure the target:

1. Go to: **Access controls → Applications**
2. Select **Add an application**
3. Select **Infrastructure**
4. Configure Application:
   - **Application name**: `SSH to VPS`
5. Under **Target criteria**:
   - **Target hostname**: Select `vps-server` (the target you created)
   - **Protocol**: `SSH`
   - **Port**: `22`
6. Click **Next**
7. **Add a policy**:
   - **Policy name**: `Allow SSH Access`
   - **Action**: `Allow`
   - **Configure rules**:
     - **Selector**: `Emails`
     - **Value**: `user1@gmail.com` (your email)
   - **Connection context**:
     - **SSH user**: Enter the UNIX usernames you want to allow (e.g., `root`)
     - Optionally enable: **Allow users to log in as their email alias**
8. Click **Add application**

### 1.7 Configure SSH Server

For enhanced security and SSH command logging, configure your VPS to trust Cloudflare's SSH Certificate Authority:

1. **Generate Cloudflare SSH CA:**
   - Go to: **Access controls → Service credentials → SSH**
   - Select **Add a certificate**
   - Under **SSH with Access for Infrastructure**, select **Generate SSH CA**
   - Copy the CA public key

2. **On your VPS, save the public key:**
   ```bash
   # Create the CA public key file
   sudo vim /etc/ssh/ca.pub
   # Paste the public key from Cloudflare
   ```

3. **Configure sshd to trust the CA:**
   ```bash
   # Edit sshd_config
   sudo vim /etc/ssh/sshd_config
   
   # Add these lines at the top:
   PubkeyAuthentication yes
   TrustedUserCAKeys /etc/ssh/ca.pub
   ```

4. **Reload SSH service:**
   ```bash
   sudo systemctl reload sshd
   ```
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

⚠️ **CRITICAL WARNING**: Running this script **WILL DISCONNECT YOUR SSH SESSION** when WARP Connector activates!

**Before running the script:**
1. Ensure you have console access to your VPS (KVM/VNC) OR
2. Have an alternative way to access the VPS OR
3. Configure SSH Access for Infrastructure FIRST (see Part 1.5-1.7) so you can reconnect via Cloudflare

**The script will:**
```bash
sudo ./setup_ztna.sh
```

**What This Script Does**:
1. ✅ Updates system packages
2. ✅ Installs Cloudflare WARP Connector
3. ✅ Registers WARP Connector with your token
4. ✅ Enables IP forwarding
5. ✅ Configures firewall (allows SSH on port 22)
6. ⚠️ **Activates WARP Connector - THIS DISCONNECTS SSH**
7. ✅ Verifies services are running (if you reconnect)

**Duration**: Approximately 5-10 minutes.

**After SSH Disconnects**:
1. Wait 30 seconds for WARP Connector to fully activate
2. **Option A**: Reconnect via regular SSH (if firewall allows):
   ```bash
   ssh root@65.109.210.232
   ```
3. **Option B**: Use console access (KVM/VNC) on your VPS hosting provider
4. **Option C**: If you configured Access for Infrastructure, connect via Cloudflare (requires WARP client running on your machine)

**Verify Installation**:
```bash
# Check WARP status
sudo warp-cli status

# Check IP forwarding
sysctl net.ipv4.ip_forward

# Check firewall rules
sudo ufw status
```

### 2.3 Configure NAT for True VPN Functionality

⚠️ **REQUIRED** if you want traffic to exit through your VPS IP (true VPN):

```bash
# Enable NAT/masquerading on VPS
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Make persistent (Ubuntu/Debian)
sudo apt-get install iptables-persistent
sudo netfilter-persistent save

# Or for other systems, add to /etc/rc.local:
echo '#!/bin/bash' | sudo tee /etc/rc.local
echo 'iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE' | sudo tee -a /etc/rc.local
sudo chmod +x /etc/rc.local
```

**Replace `eth0` with your actual network interface** (check with `ip link` or `ifconfig`).

**Without this NAT rule, traffic will NOT exit through your VPS!**

---



### 3.4 Connect via SSH

Users can now connect to the server using standard SSH commands while connected to WARP:

```bash
# Simply SSH to the server IP
ssh root@65.109.210.232

# Or use the target hostname if configured
ssh root@vps-server
```

**Requirements:**
- WARP client must be running and connected on the user's device
- User must be authenticated with their email (Gmail + One-time PIN)
- User must have an Access policy allowing them to connect

**Verify access:**
```bash
# Check which targets you have access to
warp-cli target list
```

---

## Part 3: Verification

### Understanding IP Routing

**CRITICAL**: By default, WARP Connector does **NOT** route internet traffic through your VPS!

```bash
curl ifconfig.me
# Shows: 2a09:bac1:28a0:88::3f:77 (Cloudflare CGNAT IP)
# This means traffic is NOT going through your VPS!
```

**If you see Cloudflare's IP instead of your VPS IP (65.109.210.232), your traffic is:**
- Client → Cloudflare Edge → Internet (DIRECTLY, bypassing VPS)

**NOT:**
- Client → Cloudflare Edge → VPS → Internet

**To verify if VPS routing is working:**

1. **Check your exit IP:**
```bash
curl ifconfig.me
# Should show: 65.109.210.232 (your VPS IP)
# If it shows Cloudflare IP, traffic is NOT going through VPS!
```

2. **On VPS, monitor outbound traffic:**
```bash
# Watch for outbound HTTP traffic on your WAN interface
sudo tcpdump -i eth0 -n 'dst port 80 or dst port 443'
# You should see traffic from Cloudflare IPs being forwarded out
```

3. **Check NAT is working:**
```bash
sudo iptables -t nat -L -v -n
# Should show MASQUERADE rule with packet counters increasing
```

**To fix and route traffic through VPS (true VPN):**

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

**Using standard SSH:**
```bash
# Connect to your VPS
ssh root@65.109.210.232

# First time, you'll authenticate via browser
# Subsequent connections are seamless
```

**Check available targets:**
```bash
warp-cli target list
# Should show your vps-server target with SSH on port 22
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

**Symptom**: Cannot connect to SSH after running setup script or enabling WARP

**Cause**: The script disconnects SSH when WARP activates, and you need alternative access.

**Solution Options:**

**Option 1: Direct SSH (if firewall allows)**
```bash
# Try connecting directly via SSH
ssh root@65.109.210.232

# If connection times out, firewall may be blocking
# Use console access to check firewall
```

**Option 2: Use VPS Console Access**
- Access your VPS through hosting provider's console (KVM/VNC/Serial)
- Log in and verify WARP is running:
  ```bash
  sudo warp-cli status
  ```
- Check firewall:
  ```bash
  sudo ufw status
  # Should show: 22/tcp ALLOW
  ```
- If SSH port is blocked, re-allow it:
  ```bash
  sudo ufw allow 22/tcp
  ```

**Option 3: Access via Cloudflare (requires Access for Infrastructure setup)**

1. **On your local machine, ensure WARP is connected:**
   ```bash
   warp-cli status
   # Should show: Connected
   ```

2. **Check if you have access to the target:**
   ```bash
   warp-cli target list
   # Should show your vps-server target
   ```

3. **Connect via SSH:**
   ```bash
   ssh root@65.109.210.232
   # First time will require browser authentication
   ```

4. **If target doesn't appear:**
   - Go to: **Access controls → Applications**
   - Find your SSH application
   - Verify your email is in the Allow policy
   - Verify the UNIX username (e.g., `root`) is configured

5. **Check tunnel health:**
   - Go to: **Networks → Connectors → Cloudflare Tunnels**
   - Verify your WARP Connector tunnel is **Healthy**

6. **Try verbose SSH for debugging:**
   ```bash
   ssh -vvv root@65.109.210.232
   ```

**Prevention for future:**
- Configure Access for Infrastructure BEFORE running setup script
- Keep console/KVM access available
- Or skip WARP activation in script and do it manually after testing

---

### Traffic Not Routing Through VPS

**Symptom**: `curl ifconfig.me` shows Cloudflare IP instead of your VPS IP

**This is the MAIN issue** - WARP Connector doesn't route internet traffic through VPS by default!

**Debug Steps:**

1. **Check your exit IP:**
```bash
# On client device with WARP connected
curl ifconfig.me
# Should show: 65.109.210.232 (your VPS IP)
# If shows Cloudflare IP (2a09:bac1:28a0:88::3f:77), traffic is NOT going through VPS!
```

2. **On VPS, verify NAT is configured:**
```bash
# Check if NAT rule exists
sudo iptables -t nat -L -v -n | grep MASQUERADE
# Should show MASQUERADE rule on your network interface (e.g., eth0)

# Check if rule has packet counters increasing
sudo iptables -t nat -L POSTROUTING -v -n
# Look at 'pkts' and 'bytes' columns - should increase when client browses
```

3. **On VPS, check forwarding rules:**
```bash
# Check forward rules
sudo iptables -L FORWARD -v -n
# Should show ACCEPT rules for CloudflareWARP interface

# Monitor live traffic forwarding
sudo tcpdump -i any -n 'not port 22' | grep -E '(CloudflareWARP|eth0)'
# Should see traffic coming from CloudflareWARP and going out eth0
```

4. **If NAT is missing, configure it manually:**
```bash
# Detect your network interface
ip route | grep default
# Look for interface name (eth0, ens3, enp0s3, etc.)

# Configure NAT (replace eth0 with your interface)
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i CloudflareWARP -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o CloudflareWARP -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save rules
sudo apt-get install iptables-persistent
sudo netfilter-persistent save
```

5. **Check IP forwarding is enabled:**
```bash
sysctl net.ipv4.ip_forward
sysctl net.ipv6.conf.all.forwarding
# Both should show = 1

# If not enabled:
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv6.conf.all.forwarding=1
```

6. **Verify Split Tunnels don't exclude all traffic:**
- Go to: **Team & Resources → Devices → Device profiles → Default**
- Check **Split Tunnels** section
- Mode should be: **Exclude IPs and domains**
- Should NOT have `0.0.0.0/0` in exclude list
- Only private networks should be excluded (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)

7. **Check WARP Connector tunnel routes:**
- Go to: **Networks → Routes**
- Should have `0.0.0.0/0` or specific public IPs routed through your WARP Connector tunnel
- If not, add route: Click **Add a route** → Enter `0.0.0.0/1` and `128.0.0.0/1` → Select your tunnel

8. **Restart WARP Connector:**
```bash
sudo warp-cli disconnect
sudo warp-cli connect
sudo warp-cli status
```

9. **On client, reconnect WARP:**
```bash
warp-cli disconnect
warp-cli connect
warp-cli status
```

10. **Test again:**
```bash
curl ifconfig.me
# Should now show: 65.109.210.232
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
| **SSH Access** | Direct via Access for Infrastructure (requires WARP client) |
| **Traffic Routing** | ALL traffic routes through VPS via WARP Connector |
| **Exit IP** | Cloudflare CGNAT IP (managed by Cloudflare) |
| **Platforms** | Windows, macOS, Linux, Android, iOS |

**Key Features:**
- ✅ Complete VPN replacement with WARP Connector
- ✅ System-wide traffic routing (DNS + Network + HTTP)
- ✅ Secure SSH access via Access for Infrastructure (no cloudflared needed)
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
