# Secure Remote Access Gateway with Cloudflare Zero Trust

**Secure access solution combining Cloudflare Zero Trust for SSH/VNC access with L2TP for app-specific routing in VNC sessions, and WARP custom endpoint to bypass ISP filtering.**

---

## Architecture Overview

This setup provides secure remote access with zero-trust control:

- **Cloudflare Zero Trust**: Identity-aware SSH/VNC access management
- **Cloudflare WARP**: Custom endpoint through VPS tunnel (bypasses ISP filtering)
- **L2TP/IPsec VPN**: Application-specific routing for VPN_APPS in VNC sessions

```
┌────────────────────────────────────────────────────────────┐
│                    CLIENT DEVICES                          │
│                  ┌──────────────────────────────┐          │
│                  │  Cloudflare One Agent        │          │
│                  │  (SSH/VNC Access + WARP)     │          │
│                  └───────────┬──────────────────┘          │
└──────────────────────────────┼─────────────────────────────┘
                               │
                               │ via Cloudflare Edge Network
                               │ (Zero Trust Access + WARP)
                               │
              ┌────────────────▼────────────┐
              │   Cloudflare Edge Network   │
              │      (Global CDN)           │
              └────────────┬────────────────┘
                           │ Secure Tunnel
                           ▼
┌──────────────────────────┴──────────────────────────────────┐
│                         VPS SERVER                          │
│            ┌──────────────────────┐                         │
│            │  cloudflared         │                         │
│            │  Tunnel Service      │                         │
│            │  (SSH/VNC + WARP)    │                         │
│            └──────────┬───────────┘                         │
│                       │                                     │
│                       ▼                                     │
│  ┌───────────────────────────────────────────────────────┐  │
│  │            VNC SESSIONS (Desktop Access)              │  │
│  │            - Accessed via Cloudflare Access           │  │
│  │            - Users: alice, bob, etc.                  │  │
│  │            - Ports: 5910, 5911, 5912...               │  │
│  │                                                       │  │
│  │   ┌───────────────────────────────────────────────┐   │  │
│  │   │  L2TP Client (run ./run_vpn.sh in VNC)        │   │  │
│  │   │  Routes specific VPN_APPS traffic:            │   │  │
│  │   │  - xrdp, remmina, etc.                        │   │  │
│  │   └───────────────────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│          ┌─────────┐  ┌──────────┐  ┌──────────┐            │
│          │ Docker  │  │ VS Code  │  │ Desktop  │            │
│          │         │  │  Chrome  │  │   Apps   │            │
│          └─────────┘  └──────────┘  └──────────┘            │
└─────────────────────────────────────────────────────────────┘

TRAFFIC FLOWS:
1. SSH/VNC Access: Client → Cloudflare Edge → cloudflared → SSH/VNC on VPS
2. WARP Endpoint:  Client WARP → VPS:7844 → Cloudflare (bypasses filtering)
3. L2TP in VNC:    VNC Session Apps → L2TP Server (routes specific VPN_APPS)
```

### What You Get

- ✅ **Cloudflare Zero Trust** - Identity-aware SSH/VNC access (Gmail + OTP)
- ✅ **Cloudflare WARP Custom Endpoint** - Bypass ISP filtering via VPS tunnel
- ✅ **L2TP/IPsec VPN** - Application-specific routing in VNC sessions
- ✅ **Multiple VNC Users** - Individual desktop sessions per user
- ✅ **Docker & Dev Tools** - VS Code, Chrome, Firefox pre-installed

---

## Prerequisites

- **VPS**: Ubuntu 24.04 with public IP
- **Cloudflare Account**: Free tier (for Zero Trust Access)
- **Email**: Gmail address for authentication
- **Clients**: client apps for VPN, Cloudflare One Agent for SSH/VNC

---

## Part 1: Cloudflare Zero Trust Setup (Dashboard Configuration)
Cloudflare One Agent for SSH/VNC access
### 1.1 Configure Identity Provider

Set up authentication method for your users:

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to: **Integrations → Identity providers**
4. Click **Add an identity provider**
5. Select **One-time PIN**
6. Click **Save**

**Result**: Users can now authenticate using email + OTP (one-time PIN sent to their email)

---

### 1.2 Configure Device Enrollment/Connection Policy

Allow authorized users to enroll/connect their devices:

1. Go to: **Team & Resources → Devices → Management**
2. Under **Device enrollment**, ensure these settings:
   - **Device enrollment permissions**: Select **Manage**
3. Under **Access policies**, click **Create new policy**
4. Configure Policy:
   - **Policy name**: `Admin Policy`
   - **Selector**: `Emails`
   - **Value**: `user1@gmail.com`
5. Click **Save**

Note: include this policy in the **Device enrollment permissions**

---

### 1.3 Create Cloudflare Tunnel

1. Go to: **Networks → Connectors → Cloudflare Tunnels**
2. Click **Create a tunnel**
3. Select **Cloudflared** (NOT WARP Connector)
4. **Tunnel name**: `vps-access`
5. Click **Save tunnel**
6. Select **Linux** as the operating system
7. You'll see installation commands - **copy the token** from the command
   
   Example command:
   ```bash
   cloudflared service install <YOUR-TOKEN-HERE>
   ```
   
   **Copy only the token part** (long string starting with `eyJ...`)
8. **Save this token** - you'll add it to `workstation.env` as `CLOUDFLARE_TUNNEL_TOKEN`
9. Click **Next**
10. **Important**: Add any public hostname routes then delete it (we'll add applications later)
11. Click **Next** again to finish
**Result**: Tunnel created and ready for configuration on VPS

---

### 1.4 Create Access Application for SSH

Configure SSH access through Cloudflare Access:

1. Go to: **Access controls → Applications**
2. Click **Add an application**
3. Select **Self-hosted**
4. Configure the application:
   - **Application name**: `VPS SSH`
   - **Session Duration**: `24 hours` (or your preference)
   - **Public hostname**:
     - Subdomain: `ssh-vps`
     - Domain: Select your team domain from dropdown
     - Path: Leave empty
   - Click **Next**

5. Add an Access policy:
   - Click **Select** next to the policy dropdown
   - Select your existing **Admin Policy** (the one you created earlier)
   - Click **Next**

6. Additional settings (optional):
   - Leave default settings
   - Click **Add application**

**Result**: SSH application created and protected by your Admin Policy

---

### 1.5 Configure Tunnel Routes for Applications

Now connect your tunnel to the applications you created:

1. Go to: **Networks → Connectors**
2. Click on your tunnel name (`vps-tunnel`)
3. Click **Configure**
4. Go to **Published application routes** tab
5. Click **Add a published application route**

**For SSH Application:**
   - **Subdomain**: `ssh-vps` (must match the subdomain from step 1.4)
   - **Domain**: Select your team domain
   - **Path**: Leave empty
   - **Type**: `SSH`
   - **URL**: `localhost:22`
   - Click **Save hostname**

**For VNC Applications (repeat for each VNC user):**
6. Click **Add a public hostname** again
   - **Subdomain**: `vnc1-vps` (for first VNC user)
   - **Domain**: Select your team domain
   - **Path**: Leave empty
   - **Type**: `TCP`
   - **URL**: `localhost:5910` (port 5910 for first user, 5911 for second, etc.)
   - Click **Save hostname**

7. Repeat step 6 for additional VNC users with different subdomains (vnc2-vps, vnc3-vps) and ports (5911, 5912)

**Result**: Your tunnel now routes traffic from Cloudflare to your VPS services

---

### 1.6 Create Access Application for VNC

If you want to access VNC through Cloudflare (recommended):

**For each VNC user, create a separate application:**

1. Go to: **Access → Applications**
2. Click **Add an application**
3. Select **Self-hosted**
4. Configure the application:
   - **Application name**: `VPS VNC User 1` (or specific username)
   - **Session Duration**: `24 hours`
   - **Application domain**:
     - Subdomain: `vnc1-vps` (use vnc2-vps, vnc3-vps for additional users)
     - Domain: Select your team domain
   - Click **Next**

5. Add an Access policy:
   - Click **Select** next to the policy dropdown
   - Select your existing **Admin Policy**
   - Or create a new policy if needed
   - Click **Next**

6. Additional settings:
   - Leave default settings
   - Click **Add application**

7. **Repeat steps 1-6** for each VNC user (User 2 on port 5911, User 3 on port 5912, etc.)

**Result**: Each VNC session has its own protected access application

---

### 1.7 Install Cloudflare One Agent on Your Device (Required for Access)

To access SSH and VNC through Cloudflare, install the Cloudflare One Agent:

**Download Links:**
- **Windows**: https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/download-warp/#windows
- **macOS**: https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/download-warp/#macos
- **Linux**: https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/download-warp/#linux
- **iOS**: https://apps.apple.com/app/cloudflare-one-agent/id6443476492
- **Android**: https://play.google.com/store/apps/details?id=com.cloudflare.cloudflareoneagent

**Setup Instructions:**
1. Download and install Cloudflare One Agent for your platform
2. Open the app and click **Settings** (gear icon)
3. Click **Preferences → Account**
4. Click **Login with Cloudflare Zero Trust**
5. Enter your team name (found in Zero Trust dashboard under **Settings → Custom Pages**)
6. Authenticate with your email (you'll receive a one-time PIN)
7. Set connection mode to **Gateway with WARP**

**Result**: Your device can now access SSH/VNC applications through Cloudflare's secure tunnel

---

### 1.8 Configure Custom WARP Endpoint (Bypass Iran Filtering)

If you're in a region where Cloudflare IPs are filtered (like Iran), configure a custom WARP endpoint to route connections through your VPS tunnel:

**In Cloudflare Zero Trust Dashboard:**

1. Go to: **Settings → WARP Client → Device settings**
2. Click **Manage** on your device profile (or create a new profile)
3. Scroll down to **Gateway with WARP settings**
4. Find **Custom endpoint** section
5. Click **Add endpoint**
6. Configure endpoint:
   - **Endpoint IPv4**: Enter your `VPS_PUBLIC_IP` (from workstation.env)
   - **Endpoint UDP Port**: `7844` (default WARP routing port)
   - **Name**: `VPS Custom Endpoint` (descriptive name)
7. Click **Save**
8. Make sure this profile is assigned to your devices

**On Your Device:**

1. Open Cloudflare One Agent
2. Go to **Settings → Preferences → Account**
3. Verify your device profile has the custom endpoint enabled
4. Disconnect and reconnect the WARP connection
5. Check connection is working

**How It Works:**
- Cloudflare One Agent connects to your VPS IP on port 7844 (UDP)
- Your VPS tunnel forwards the WARP traffic to Cloudflare's edge network
- This bypasses local ISP filtering of Cloudflare's default IPs
- All SSH/VNC access still works through the secure tunnel

**Verify It's Working:**
```bash
# Check cloudflared logs on VPS to see WARP connections
sudo journalctl -u cloudflared -f
```

You should see WARP routing traffic being handled by your tunnel.

---

### 1.9 Test Cloudflare Access Setup (After VPS Setup)

After completing VPS setup in Part 2, test your access:

**Test SSH Access:**
```bash
# With Cloudflare One Agent connected, use cloudflared access ssh command
cloudflared access ssh --hostname ssh-vps.yourteam.cloudflareaccess.com --url localhost:2222
```

Or configure your SSH client to use the Cloudflare tunnel.

**Test VNC Access:**
1. Connect Cloudflare One Agent
2. Open browser and go to: `https://vnc1-vps.yourteam.cloudflareaccess.com`
3. Authenticate with your email
4. Access VNC through browser or VNC client via the authenticated tunnel

**Important**: Direct SSH/VNC access to VPS IP is blocked by firewall. Access is ONLY through Cloudflare tunnel.

**Note**: Replace `yourteam` with your actual Cloudflare Zero Trust team name

---

## Part 2: VPS Server Setup

### 2.1 Prepare VPS Configuration

1. **SSH into your VPS**:
   ```bash
   ssh root@YOUR_VPS_IP
   ```

2. **Clone this repository**:
   ```bash
   git clone https://github.com/HosseinBeheshti/setupWS.git
   cd setupWS
   ```

3. **Edit `workstation.env`** configuration file:

```bash
vim workstation.env
```

**Required Configuration:**

```bash
# Cloudflare Tunnel (for SSH/VNC Access)
CLOUDFLARE_TUNNEL_TOKEN="eyJhIjoiN..."  # ← Paste token from Part 1.3
TUNNEL_NAME="vps-tunnel"                 # ← Match tunnel name from Part 1.3

# VPS Information
VPS_PUBLIC_IP="1.2.3.4"                  # ← Your VPS public IP

# VPN Configuration

# VNC Users (configure at least one)
VNCUSER1_USERNAME='alice'
VNCUSER1_PASSWORD='strong_password_here'
VNCUSER1_DISPLAY='1'
VNCUSER1_RESOLUTION='1920x1080'
VNCUSER1_PORT='5910'

# Add more users as needed (VNCUSER2_, VNCUSER3_, etc.)
VNC_USER_COUNT=3

# L2TP/IPsec Configuration (for VPN_APPS in VNC sessions)
L2TP_SERVER_IP='your.l2tp.server.ip'
L2TP_IPSEC_PSK='preshared_key'
L2TP_USERNAME='username'
L2TP_PASSWORD='password'

# Apps to route through L2TP (use ./run_vpn.sh in VNC)
VPN_APPS="xrdp remmina"
```

4. **Save and exit** (`:wq` in vim)

---

### 2.2 Run Automated Setup

**Run the master setup script** (installs everything in correct order):

```bash
sudo ./setup_ws.sh
```

**What this does:**
1. Installs all required packages (VNC, L2TP, Docker, VS Code, Chrome, etc.)
2. Configures virtual router for VPN traffic
3. Sets up L2TP/IPsec for VPN_APPS routing in VNC sessions
4. Creates VNC servers for each user
5. Installs cloudflared and configures Cloudflare Access with WARP routing

**Duration**: 10-15 minutes depending on VPS speed.

**Monitor progress** - the script provides detailed status messages.

---

## Part 3: Client Setup

### 3.1 Connect to VNC Desktop

**Via Cloudflare Access (Required):**

1. **Install and connect Cloudflare One Agent** (from Part 1.7)
2. **Access via browser**:
   - Open browser: `https://vnc1-vps.yourteam.cloudflareaccess.com`
   - Authenticate with your email (one-time PIN)
   - Access VNC session through Cloudflare's secure tunnel

**Or use VNC client with cloudflared:**
```bash
# Install cloudflared on client machine
# Create local tunnel to VNC
cloudflared access tcp --hostname vnc1-vps.yourteam.cloudflareaccess.com --url localhost:5900

# In another terminal, connect VNC client to localhost:5900
```

**Direct Connection:**

**Not Available** - Direct VNC access is blocked by firewall for security. You must use Cloudflare Access.

---

### 3.2 Access via SSH

**Via Cloudflare Access (Required):**

1. **Connect Cloudflare One Agent** on your device
2. **SSH via cloudflared**:
   ```bash
   cloudflared access ssh --hostname ssh-vps.yourteam.cloudflareaccess.com
   ```

**Or configure SSH client** (add to `~/.ssh/config`):
```
Host vps-ssh
  ProxyCommand cloudflared access ssh --hostname ssh-vps.yourteam.cloudflareaccess.com
  User root
```

Then connect with: `ssh vps-ssh`

**Direct SSH:**

**Not Available** - Direct SSH access is blocked by firewall for security. You must use Cloudflare Access.

---

### 3.3 Use L2TP for VPN_APPS in VNC Sessions

L2TP is configured to route specific applications through a remote VPN.
This is useful when working in a VNC session and need certain apps routed.

**In your VNC session:**
```bash
sudo ./run_vpn.sh
```

This will:
- Connect to L2TP VPN server
- Route traffic from VPN_APPS (e.g., xrdp, remmina) through L2TP
- Keep other VNC session traffic using normal routing

**Note:** is a separate independent VPN service for your client devices.
L2TP is only for routing specific apps in VNC sessions.

---

## Part 4: Verification

### 4.1 Verify VPN

**On VPS:**
```bash
# Check status
sudo wg show

# Should show:
# interface: 
#   public key: ...
#   listening port: 
#   peer: (client public key)
#     allowed ips: 10.8.0.2/32
#     latest handshake: X seconds ago
```

**On Client:**
```bash
# Check your public IP (should be VPS IP)
curl ifconfig.me

# Check VPN interface
ip addr show  # Linux/Mac
# Look for  or utun interface with 10.8.0.x IP
```

---

### 4.2 Client Management
### 4.2 Verify VNC Access

```bash
# On VPS - check VNC services
systemctl status vncserver-alice@1.service

# Should show: active (running)
```

Connect via VNC client to verify desktop access.

---

### 4.3 Verify Cloudflare Tunnel

```bash
# On VPS
sudo systemctl status cloudflared

# Should show: active (running)
# You should see "Registered tunnel connection" messages

# Check recent logs
sudo journalctl -u cloudflared -n 20
```

**Note**: Token-based tunnels don't support `cloudflared tunnel info` command. Instead:
- Check service status with `systemctl status cloudflared`
- Verify in Cloudflare dashboard: **Networks → Tunnels** (should show "Healthy" status)

**Test Access with Cloudflare One Agent:**

1. Connect Cloudflare One Agent on your device
2. Test SSH: `cloudflared access ssh --hostname ssh-vps.yourteam.cloudflareaccess.com`
3. Test VNC: Open browser to `https://vnc1-vps.yourteam.cloudflareaccess.com`
4. Verify authentication works (you should receive one-time PIN)

**Important**: Direct SSH/VNC to VPS IP is blocked. All access must go through Cloudflare.

**Note**: Replace `yourteam` with your actual Cloudflare Zero Trust team name

---

## Troubleshooting

### Issues
### VNC Issues

**Service not starting:**
```bash
# Check service status
systemctl status vncserver-username@display.service

# Check logs
journalctl -xeu vncserver-username@display.service

# Restart service
sudo systemctl restart vncserver-username@display.service
```

**Can't connect:**
```bash
# Check firewall
sudo ufw status
# VNC port should be ALLOW

# Check if VNC is listening
sudo netstat -tulpn | grep 5910
```

---

### Cloudflare Access Issues

**Tunnel not connecting:**
```bash
# Check cloudflared status
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -f

# Restart service
sudo systemctl restart cloudflared

# Check tunnel info
sudo cloudflared tunnel info vps-tunnel
```

**Can't access SSH/VNC via Cloudflare:**
1. Verify Cloudflare One Agent is installed and connected
2. Check connection mode: Should be **Gateway with WARP**
3. Verify you're authenticated (check Cloudflare One Agent settings)
4. Check Access applications exist in Dashboard (**Access → Applications**)
5. Verify your Admin Policy allows your email
6. Check public hostname routes exist (**Networks → Tunnels → Configure → Public Hostname**)
7. Test authentication: Visit `https://yourteam.cloudflareaccess.com` to verify you can authenticate
8. Check tunnel is "Healthy" in dashboard (**Networks → Tunnels**)

**Cloudflare One Agent Issues:**
```bash
# Check agent status (on client machine)
warp-cli status

# Check connection mode
warp-cli settings

# Reconnect
warp-cli disconnect
warp-cli connect
```

**Direct SSH/VNC not working:**
This is expected and by design. Direct access to SSH (port 22) and VNC ports is blocked by the VPS firewall. All SSH/VNC access must go through Cloudflare tunnel for security.

**cloudflared Access Tool Issues:**
```bash
# Test if cloudflared can reach the application
cloudflared access login https://ssh-vps.yourteam.cloudflareaccess.com

# Check token is valid
cloudflared access token -app=https://ssh-vps.yourteam.cloudflareaccess.com
```

---

## Monitoring

### Check VPN Connections

```bash
# active connections
sudo wg show

# Current VPN routes
ip route show table vpn_wg
```

### Check Active VNC Sessions

```bash
# All VNC services
systemctl list-units | grep vncserver

# Specific user
systemctl status vncserver-alice@1
```

### Monitor Cloudflare Tunnel

```bash
# Live logs
sudo journalctl -u cloudflared -f

# Check service status
sudo systemctl status cloudflared

# View recent activity
sudo journalctl -u cloudflared -n 50
```

**Note**: Token-based tunnels don't support `cloudflared tunnel info` or `tunnel list` commands.

**Check in Dashboard:**
- Go to **Networks → Tunnels**
- Your tunnel should show as "Healthy" with green status
- Check **Traffic** tab for connection metrics

---

## Security Best Practices

1. **Change default passwords** in `workstation.env` before setup
2. **Use strong keys** (auto-generated by setup script)
3. **Restrict Cloudflare Access** policies to specific emails
4. **Enable UFW firewall** (done automatically by setup script)
5. **Regularly update** VPS packages: `sudo apt update && sudo apt upgrade`
6. **Monitor logs** for suspicious activity
7. **Backup configs** from `/etc//clients/`

---

## FAQ

**Q: Can I use both L2TP simultaneously?**  
A: Yes! They serve different purposes:
- Access policies enforcement
- Traffic encryption and logging
- Protection against brute-force attacks
L2TP VPN ports remain open for their intended purposes.

**Q: How do I access my VPS through Cloudflare?**  
A: 
1. Install WARP client and authenticate with your team
2. For SSH: Use `cloudflared access ssh --hostname ssh-vps.yourteam.cloudflareaccess.com`
3. For VNC: Open browser to `https://vnc1-vps.yourteam.cloudflareaccess.com`
4. Or use `cloudflared access tcp` to create local tunnels for any service

**Q: Can I add more clients later?**  
A: Yes. Use the management script:
```bash
```
You can add unlimited clients on-demand.

**Q: How do I remove a client?**  
A: Use the management script:
```bash
```

**Q: How do I see all my clients?**  
A: Use the list command:
```bash
```

**Q: How do I add more VNC users?**  
A: Add `VNCUSER4_*` variables to `workstation.env`, increment `VNC_USER_COUNT`, and run `sudo ./setup_vnc.sh`.

**Q: What ports are open on my VPS?**  
A: 22 (SSH), VNC ports (5910-591x), and optionally L2TP ports (500, 1701, 4500/udp).

---

## Next Steps

1. ✅ Complete Cloudflare Zero Trust setup (Part 1)
   - Configure identity provider
   - Create tunnel and get token
   - Set up Access applications
   - Add private network routes
   - Install WARP client on your devices
2. ✅ Run `sudo ./setup_ws.sh` on VPS (Part 2)
4. ✅ Test Cloudflare private network access (SSH/VNC)
5. ✅ Test VPN connection and verify exit IP
6. ✅ Connect to VNC desktops
7. ✅ Read security best practices above

---

## Support

- **Cloudflare Zero Trust**: https://developers.cloudflare.com/cloudflare-one/
- **Ubuntu Server**: https://ubuntu.com/server/docs

---

## License

See [LICENSE](LICENSE) file.

---

**Setup completed!** Enjoy your secure remote access gateway with VPN and Cloudflare Zero Trust Access.
