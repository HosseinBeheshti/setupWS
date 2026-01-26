# Cloudflare Zero Trust VPN Replacement

Replace traditional VPN with **cloudflared + Egress Policies** - route client traffic through your VPS with Zero Trust security.

## What You Get

✅ **VPN Replacement** - Route WARP client traffic through your VPS with your exit IP  
✅ **SSH Access** - Secure SSH access via Cloudflare Tunnel  
✅ **Single Client App** - Cloudflare One Agent on all platforms (Desktop + Mobile)  
✅ **Zero Trust Security** - Identity-based access control + Gateway filtering  
✅ **Custom Exit IP** - Traffic exits from your VPS IP (VPS_PUBLIC_IP)  

---

## Architecture

**Using cloudflared + Egress through Cloudflare Tunnel (Beta):**
```
Remote WARP Clients (Anywhere)
     │
     │ (DNS + Network + HTTP traffic)
     │
     ▼
Cloudflare Edge (Gateway filtering + DNS resolution)
     │
     │ (Encrypted Cloudflare Tunnel)
     │
     ▼
VPS - cloudflared (VPS_PUBLIC_IP)
     │
     │ (Egress with VPS IP)
     │
     ▼
Internet (traffic exits with VPS_PUBLIC_IP)
```

**How it works:**
1. WARP client sends all traffic to Cloudflare Gateway
2. Gateway resolves DNS queries with "initial resolved IPs" (100.80.x.x range)
3. For domains with hostname routes, Gateway sends traffic down your Cloudflare Tunnel
4. Your VPS receives traffic via cloudflared
5. Traffic exits to internet using your VPS IP (VPS_PUBLIC_IP)
6. Gateway logs and filters all traffic

**What you get:**
- ✅ cloudflared tunnel on VPS for egress
- ✅ Hostname-based routing (configure which domains exit through VPS)
- ✅ NAT configured for internet egress
- ✅ Exit IP = Your VPS IP (VPS_PUBLIC_IP)
- ✅ Gateway filtering and logging
- ✅ Secure SSH access through Cloudflare Access  

---

## Prerequisites

- **VPS**: Ubuntu 24.04, Public IP: `VPS_PUBLIC_IP`
- **Cloudflare Zero Trust**: Free tier (team: `noise-ztna`)
- **User Emails**: Gmail addresses for authorized users
- **WARP Client**: Required on all devices for traffic routing
- **cloudflared**: Version 2025.7.0 or later (installed by setup script)

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

### 1.2 Create Cloudflare Tunnel with cloudflared

This creates the tunnel that will be used for egress routing:

1. Go to: **Networks → Connectors → Cloudflare Tunnels**
2. Click **Create a tunnel**
3. Select **Cloudflared** (NOT WARP Connector)
4. **Tunnel name**: `vps-egress` (or any name you prefer)
5. Click **Save tunnel**
6. Select **Linux** as the operating system
7. You'll see installation commands - **copy the token** from the command
   
   Example command:
   ```bash
   cloudflared service install <YOUR-TOKEN-HERE>
   ```
   
   **Copy only the token part** (long string starting with `eyJ...`)
8. **Save this token in your workstation.env** as `CLOUDFLARE_TUNNEL_TOKEN`
9. Click **Next**
10. **Important**: Don't add any public hostname routes yet (we'll do this later)
11. Click **Next** again to finish

**Result**: Cloudflare Tunnel created and ready for installation on VPS.

---

### 1.2.1 Add Hostname Routes for Egress

**Critical**: Configure which domains should exit through your VPS.

**Option A: Route ALL traffic (recommended for VPN replacement)**

1. Go to: **Networks → Routes → Hostname routes**
2. Click **Create hostname route**
3. Configure:
   - **Hostname**: `*` (wildcard for all domains)
   - **Tunnel**: Select your `vps-egress` tunnel
4. Click **Create route**

**Option B: Route specific domains only**

Add routes for specific domains:
- `google.com` - Route Google traffic
- `*.youtube.com` - Route YouTube traffic  
- `example.com` - Route specific site

Repeat for each domain you want to exit through VPS.

**Note**: Without hostname routes, traffic will NOT go through your VPS!

---

### 1.2.2 Add VPS Private Network (for SSH Access)

1. Go back to: **Networks → Connectors → Cloudflare Tunnels**
2. Find your `vps-egress` tunnel and click **Configure**
3. Go to **Private Networks** tab
4. Click **Add a private network**
5. Enter: `10.0.0.0/24` (or your VPS internal network)
6. Click **Save**

**Why**: This allows SSH access to your VPS through the tunnel.

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

### 1.4 Configure Split Tunnels for Egress

**Critical**: Configure split tunnels to allow initial resolved IPs:

1. Go to: **Team & Resources → Devices → Device profiles**
2. Find the **Default** profile and click **Configure**
3. Scroll to **Split Tunnels** section
4. Click **Manage**
5. Ensure mode is: **Exclude IPs and domains**
6. **REMOVE** `100.64.0.0/10` from exclude list (if present)
   - This is required for hostname-based egress routing
   - Gateway uses 100.80.0.0/16 range for "initial resolved IPs"
7. Only exclude private networks:
   ```
   10.0.0.0/8
   172.16.0.0/12
   192.168.0.0/16
   ```
8. Click **Save**

**Important**: Without removing 100.64.0.0/10, egress through your tunnel will NOT work!

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
   - **IP addresses**: Enter `VPS_PUBLIC_IP` 
   - The IP should appear in the dropdown (you added it in section 1.2.1)
   - Select the IP and virtual network (likely `default`)
5. Click **Add target**

**Note**: If the IP doesn't appear in the dropdown, verify:
- You completed section 1.2.1 (added IP to tunnel routes)
- Go to **Networks → Routes** and confirm `VPS_PUBLIC_IP` is listed
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

SSH into your VPS and clone the repository, then edit `workstation.env` and configure:
```bash
# Clone repository
git clone https://github.com/HosseinBeheshti/setupWS.git
cd setupWS
vim workstation.env
```

**Required configuration:**
- `CLOUDFLARE_TUNNEL_TOKEN` - Token from Step 1.2 (starts with eyJ...)
- `VPS_PUBLIC_IP` - Your VPS public IP (or leave empty for auto-detect)
- `TUNNEL_NAME` - Your tunnel name (e.g., `vps-egress`)

---

### 2.2 Run Automated Setup

⚠️ **Note**: The script will install and configure cloudflared. Your SSH connection should remain stable.

```bash
sudo ./setup_ztna.sh
```

**What This Script Does**:
1. ✅ Updates system packages
2. ✅ Installs cloudflared (latest version)
3. ✅ Configures cloudflared tunnel with your token
4. ✅ Enables WARP routing for egress
5. ✅ Configures NAT/masquerading for internet egress
6. ✅ Enables IP forwarding
7. ✅ Configures firewall (allows SSH on port 22)
8. ✅ Starts cloudflared as a system service
9. ✅ Verifies tunnel connectivity

**Duration**: Approximately 5-10 minutes.

**After Setup Completes**:
- cloudflared tunnel running and connected
- NAT configured for egress routing
- Firewall configured with proper rules
- IP forwarding enabled

**Verify Installation**:
```bash
# Check tunnel status
sudo systemctl status cloudflared

# Check tunnel connectivity
sudo cloudflared tunnel info <TUNNEL-NAME>

# Check IP forwarding
sysctl net.ipv4.ip_forward

# Check NAT rules
sudo iptables -t nat -L -v -n | grep MASQUERADE

# Check firewall rules
sudo ufw status
```
---



### 3.4 Connect via SSH

Users can now connect to the server using standard SSH commands while connected to WARP:

```bash
# Simply SSH to the server IP
ssh root@VPS_PUBLIC_IP

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

### Understanding IP Routing with cloudflared Egress

**How it works**: When you configure hostname routes, traffic flows:

```bash
curl ifconfig.me
# Should show: VPS_PUBLIC_IP (your VPS IP)
```

Your traffic flows:
- Client → Cloudflare Edge → Gateway (DNS resolution with initial resolved IP)
- Gateway → Your cloudflared tunnel → VPS
- VPS → Internet (exits with VPS_PUBLIC_IP)

**To verify VPS routing is working:**

1. **Check your exit IP:**
```bash
# On client with WARP connected
curl ifconfig.me
# Should show: VPS_PUBLIC_IP (your VPS IP)

# If shows Cloudflare IP instead:
# - Check hostname routes are configured (Step 1.2.1)
# - Check split tunnels (100.64.0.0/10 should NOT be excluded)
# - Check cloudflared tunnel is running on VPS
```

2. **On VPS, monitor tunnel traffic:**
```bash
# Watch cloudflared logs
sudo journalctl -u cloudflared -f

# Watch outbound traffic
sudo tcpdump -i eth0 -n 'dst port 80 or dst port 443'
# Should see traffic being forwarded from tunnel to internet
```

3. **Check NAT is working:**
```bash
sudo iptables -t nat -L -v -n | grep MASQUERADE
# Should show MASQUERADE rule with increasing packet counters
```

4. **Check Gateway DNS logs:**
- Go to: **Logs → Gateway → DNS**
- Look for queries with initial resolved IPs (100.80.x.x)
- Verify domains are resolving correctly

**Common issues:**

- **Still seeing Cloudflare IP**: Hostname routes not configured or 100.64.0.0/10 excluded in split tunnels
- **No traffic in tunnel logs**: Hostname routes missing or WARP not connected
- **NAT not working**: Check iptables rules and IP forwarding enabled

**To fix and route traffic through VPS (true VPN):****

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
ssh root@VPS_PUBLIC_IP

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
ssh root@VPS_PUBLIC_IP

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
   ssh root@VPS_PUBLIC_IP
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
   ssh -vvv root@VPS_PUBLIC_IP
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
# Should show: VPS_PUBLIC_IP (your VPS IP)
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
# Should now show: VPS_PUBLIC_IP
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
