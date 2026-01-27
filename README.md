# Secure Remote Access Gateway with WireGuard VPN

**Hybrid secure access solution combining WireGuard VPN for clients with L2TP for app-specific routing in VNC sessions, all managed through Cloudflare Zero Trust Access.**

---

## Architecture Overview

This setup provides two VPN services and zero-trust access control:

- **WireGuard VPN**: Independent VPN service for client devices (all traffic)
- **L2TP/IPsec VPN**: Application-specific routing for VPN_APPS in VNC sessions
- **Cloudflare Zero Trust**: Identity-aware SSH/VNC access management

```
┌────────────────────────────────────────────────────────────┐
│                    CLIENT DEVICES                          │
│  ┌──────────────────────┐    ┌──────────────────────────┐  │
│  │   WireGuard VPN      │    │  Cloudflare One Agent    │  │
│  │  (All Traffic)       │    │  (SSH/VNC Access)        │  │
│  └──────────┬───────────┘    └───────────┬──────────────┘  │
└─────────────┼────────────────────────────┼─────────────────┘
              │                            │
              │ Encrypted Tunnel           │ via Cloudflare Edge Network
              │ Port 51820/udp             │ (Zero Trust Access)
              │                            │
              ▼                            ▼
       ┌──────────────┐            ┌─────────────────┐
       │   Internet   │            │ Cloudflare Edge │
       │      via     │            │   (Global CDN)  │
       │ VPS_PUBLIC_IP│            └────────┬────────┘
       └──────────────┘                     │
              ▲                             │ Secure Tunnel
              │                             ▼
┌─────────────┴─────────────────────────────┴─────────────────┐
│                         VPS SERVER                          │
│  ┌─────────────────────┐       ┌──────────────────────┐     │
│  │  WireGuard          │       │  cloudflared         │     │
│  │  (wg0)              │       │  Tunnel Service      │     │
│  │  10.8.0.1/24        │       │  (Port 22, 5910+)    │     │
│  |  Routes to Internet |       └──────────┬───────────┘     │
│  |  NAT/Masquerade     |                  |                 │
│  └─────────────────────┘                  |                 |
│                                           │                 │
│                                           ▼                 │
│  ┌───────────────────────────────────────────────────────┐  │
│  │            VNC SESSIONS (Desktop Access)              │  │
│  │            - Accessed via Cloudflare Edge             │  │
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
1. WireGuard VPN:  Client → VPS (encrypted) → Internet (exits as VPS_PUBLIC_IP)
2. VNC/SSH Access: Client → Cloudflare Edge → cloudflared → VNC/SSH on VPS
3. L2TP in VNC:    VNC Session Apps → L2TP Server (routes specific VPN_APPS)
```

### What You Get

- ✅ **WireGuard VPN** - Independent VPN service for client devices (full tunnel)
- ✅ **L2TP/IPsec VPN** - Application-specific routing in VNC sessions (VPN_APPS)
- ✅ **Cloudflare Access** - Identity-aware SSH/VNC access (Gmail + OTP)
- ✅ **Zero Trust Security** - Policy-based access control for management
- ✅ **Multiple VNC Users** - Individual desktop sessions per user
- ✅ **Docker & Dev Tools** - VS Code, Chrome, Firefox pre-installed

---

## Prerequisites

- **VPS**: Ubuntu 24.04 with public IP
- **Cloudflare Account**: Free tier (for Zero Trust Access)
- **Email**: Gmail address for authentication
- **Clients**: WireGuard client apps for VPN, Cloudflare One Agent for SSH/VNC

---

## Part 1: Cloudflare Zero Trust Setup (Dashboard Configuration)

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
4. **Tunnel name**: `vps-tunnel` (or any name you prefer)
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
10. **Important**: Add any public hostname routes then delete it(we'll add applications later)
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

1. Go to: **Networks → Tunnels**
2. Click on your tunnel name (`vps-tunnel`)
3. Click **Configure**
4. Go to **Public Hostname** tab
5. Click **Add a public hostname**

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
   - **Type**: `HTTP`
   - **URL**: `localhost:5910` (port 5910 for first user, 5911 for second, etc.)
   - Click **Save hostname**

7. Repeat step 6 for additional VNC users with different subdomains (vnc2-vps, vnc3-vps) and ports (5911, 5912)

**Result**: Your tunnel now routes traffic from Cloudflare to your VPS services

---

### 1.6 Create Access Application for VNC (Optional)

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

### 1.7 Install WARP Client on Your Device (Required for Access)

To access SSH and VNC through Cloudflare, install the WARP client:

**For Windows/Mac/Linux:**
1. Download WARP client from: https://1.1.1.1/
2. Install the client
3. Open WARP and go to **Settings → Preferences → Account**
4. Click **Login with Cloudflare Zero Trust**
5. Enter your team name (found in Zero Trust dashboard under Settings → Custom Pages)
6. Authenticate with your email (you'll receive a one-time PIN)
7. In WARP settings, set mode to **Gateway with WARP**

**Result**: Your device can now access applications through Cloudflare

---

### 1.8 Test Cloudflare Access Setup (After VPS Setup)

After completing VPS setup in Part 2, test your access:

**Test SSH Access:**
```bash
# With WARP connected, use cloudflared access ssh command
cloudflared access ssh --hostname ssh-vps.yourteam.cloudflareaccess.com --url localhost:2222
```

Or configure your SSH client to use the Cloudflare tunnel.

**Test VNC Access:**
1. Connect WARP client
2. Open browser and go to: `https://vnc1-vps.yourteam.cloudflareaccess.com`
3. Authenticate with your email
4. Access VNC through browser or VNC client via the authenticated tunnel

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
   git clone https://github.com/yourusername/setupWS.git
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

# WireGuard VPN Configuration
WG_SERVER_PORT="51820"
WG_SERVER_ADDRESS="10.8.0.1/24"
WG_CLIENT_DNS="1.1.1.1, 1.0.0.1"

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
1. Installs all required packages (VNC, WireGuard, L2TP, Docker, VS Code, Chrome, etc.)
2. Configures virtual router for VPN traffic
3. Sets up L2TP/IPsec for VPN_APPS routing in VNC sessions
4. Creates VNC servers for each user
5. Installs and configures WireGuard VPN server (clients managed separately)
6. Installs cloudflared and configures Cloudflare Access

**Duration**: 10-15 minutes depending on VPS speed.

**Monitor progress** - the script provides detailed status messages.

---

## Part 3: Client Setup

### 3.1 Add and Configure WireGuard Clients

**Interactive Menu (Recommended):**

```bash
sudo ./manage_wg_client.sh
```

This will show an interactive menu:
```
1. List all clients
2. Add new client
3. Remove client
4. Show client configuration
5. Show QR code for client
6. Show WireGuard status
0. Exit
```

**Or use direct commands:**

```bash
# Add clients
sudo ./manage_wg_client.sh add laptop
sudo ./manage_wg_client.sh add phone

# List all clients
sudo ./manage_wg_client.sh list

# Show QR code for mobile device
sudo ./manage_wg_client.sh qr phone

# Show client configuration
sudo ./manage_wg_client.sh show laptop

# Remove a client
sudo ./manage_wg_client.sh remove old-device
```

---

### 3.2 Connect via WireGuard VPN

**Desktop Clients (Linux/Mac/Windows):**

1. **Install WireGuard**:
   - Linux: `sudo apt install wireguard`
   - Mac/Windows: Download from [wireguard.com](https://www.wireguard.com/install/)

2. **Copy client configuration from VPS**:
   ```bash
   scp root@YOUR_VPS_IP:/etc/wireguard/clients/laptop.conf ~/
   ```

3. **Import configuration**:
   - Linux/Mac: `sudo wg-quick up ~/laptop.conf`
   - Windows/Mac GUI: Import `laptop.conf` file

4. **Verify connection**:
   ```bash
   curl ifconfig.me
   # Should show your VPS IP
   ```

**Mobile Clients (iOS/Android):**

1. **Install WireGuard app** from App Store/Play Store
2. **Generate QR code on VPS**:
   ```bash
   sudo ./manage_wg_client.sh qr phone
   ```
3. **Scan QR code** in WireGuard app
4. **Connect** and verify IP

---

### 3.3 Connect to VNC Desktop

**Via Cloudflare Access (Recommended):**

1. **Install and connect WARP client** (from Part 1.7)
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

**Direct Connection (without Cloudflare):**

1. **Install VNC client**
2. **Connect directly**:
   - Address: `YOUR_VPS_IP:5910`
   - Password: (from workstation.env)
   - Note: This bypasses Cloudflare Access protection

---

### 3.4 Access via SSH

**Via Cloudflare Access (Recommended):**

1. **Connect WARP client** on your device
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

**Direct SSH (without Cloudflare):**
```bash
ssh root@YOUR_VPS_IP
```
Note: This bypasses Cloudflare Access protection

---

### 3.5 Use L2TP for VPN_APPS in VNC Sessions

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

**Note:** WireGuard is a separate independent VPN service for your client devices.
L2TP is only for routing specific apps in VNC sessions.

---

## Part 4: Verification

### 4.1 Verify WireGuard VPN

**On VPS:**
```bash
# Check WireGuard status
sudo wg show

# Should show:
# interface: wg0
#   public key: ...
#   listening port: 51820
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
# Look for wg0 or utun interface with 10.8.0.x IP
```

---

### 4.2 WireGuard Client Management

**Interactive menu:**

```bash
sudo ./manage_wg_client.sh
```

Select from the menu to manage clients easily.

**Direct commands:**

```bash
# List all clients and their connection status
sudo ./manage_wg_client.sh list

# Add a new client
sudo ./manage_wg_client.sh add tablet

# Show client configuration file
sudo ./manage_wg_client.sh show tablet

# Generate/show QR code for mobile
sudo ./manage_wg_client.sh qr tablet

# Remove a client
sudo ./manage_wg_client.sh remove old-laptop

# Check active connections
sudo wg show
```

---

### 4.3 Verify VNC Access

```bash
# On VPS - check VNC services
systemctl status vncserver-alice@1.service

# Should show: active (running)
```

Connect via VNC client to verify desktop access.

---

### 4.4 Verify Cloudflare Tunnel

```bash
# On VPS
sudo systemctl status cloudflared

# Should show: active (running)

# Check tunnel info
sudo cloudflared tunnel info vps-tunnel
```

**Test Access with WARP Client:**

1. Connect WARP client on your device
2. Test SSH: `cloudflared access ssh --hostname ssh-vps.yourteam.cloudflareaccess.com`
3. Test VNC: Open browser to `https://vnc1-vps.yourteam.cloudflareaccess.com`
4. Verify authentication works (you should receive one-time PIN)

**Note**: Replace `yourteam` with your actual Cloudflare Zero Trust team name

---

## Troubleshooting

### WireGuard Issues

**VPN not connecting:**
```bash
# On VPS - check WireGuard service
sudo systemctl status wg-quick@wg0
sudo journalctl -u wg-quick@wg0 -n 50

# Check firewall
sudo ufw status
# Port 51820/udp should be ALLOW

# Check IP forwarding
sysctl net.ipv4.ip_forward
# Should be: net.ipv4.ip_forward = 1
```

**Traffic not routing:**
```bash
# Check NAT rules
sudo iptables -t nat -L -v -n | grep MASQUERADE
# Should see rule for wg0 interface
```

---

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
1. Verify WARP client is installed and connected
2. Check WARP mode: Should be **Gateway with WARP**
3. Verify you're authenticated (check WARP client settings)
4. Check Access applications exist in Dashboard (**Access → Applications**)
5. Verify your Admin Policy allows your email
6. Check public hostname routes exist (**Networks → Tunnels → Configure → Public Hostname**)
7. Test authentication: Visit `https://yourteam.cloudflareaccess.com` to verify you can authenticate
8. Check tunnel is "Healthy" in dashboard (**Networks → Tunnels**)

**WARP Client Issues:**
```bash
# Check WARP status (on client machine)
warp-cli status

# Check connection mode
warp-cli settings

# Reconnect
warp-cli disconnect
warp-cli connect
```

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
# WireGuard active connections
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

# Check tunnel status
sudo cloudflared tunnel info vps-tunnel

# List all tunnels
sudo cloudflared tunnel list
```

**Check in Dashboard:**
- Go to **Networks → Tunnels**
- Your tunnel should show as "Healthy" with green status
- Check **Traffic** tab for connection metrics

---

## Security Best Practices

1. **Change default passwords** in `workstation.env` before setup
2. **Use strong WireGuard keys** (auto-generated by setup script)
3. **Restrict Cloudflare Access** policies to specific emails
4. **Enable UFW firewall** (done automatically by setup script)
5. **Regularly update** VPS packages: `sudo apt update && sudo apt upgrade`
6. **Monitor logs** for suspicious activity
7. **Backup WireGuard configs** from `/etc/wireguard/clients/`

---

## FAQ

**Q: Can I use both WireGuard and L2TP simultaneously?**  
A: Yes! They serve different purposes:
- **WireGuard**: Independent VPN service for client devices (routes all traffic through VPS)
- **L2TP**: Routes specific VPN_APPS in VNC sessions (run ./run_vpn.sh in VNC)
- Use WireGuard on your laptop/phone, and L2TP in VNC for app-specific routing

**Q: Which VPN should I use - WireGuard or L2TP?**  
A: Use both for different purposes:
- **WireGuard**: For your client devices (laptop, phone) - full VPN service
- **L2TP**: In VNC sessions for routing specific apps (xrdp, remmina, etc.)

**Q: Do I need Cloudflare WARP for VPN?**  
A: No. There are two separate things:
- **WireGuard VPN**: Routes all your device traffic through VPS (shows VPS IP)
- **Cloudflare WARP + Access**: Only needed for accessing SSH/VNC through Cloudflare's authenticated applications
- You can use WireGuard for general VPN, and Cloudflare Access only when accessing your VPS services

**Q: What's the difference between WireGuard and Cloudflare WARP?**  
A: 
- **WireGuard**: Your own VPN server - all traffic exits via your VPS IP
- **WARP + Access**: Cloudflare's client for accessing self-hosted applications protected by Access policies
- They serve different purposes and can be used together

**Q: How do I access my VPS through Cloudflare?**  
A: 
1. Install WARP client and authenticate with your team
2. For SSH: Use `cloudflared access ssh --hostname ssh-vps.yourteam.cloudflareaccess.com`
3. For VNC: Open browser to `https://vnc1-vps.yourteam.cloudflareaccess.com`
4. Or use `cloudflared access tcp` to create local tunnels for any service

**Q: Can I add more WireGuard clients later?**  
A: Yes. Use the management script:
```bash
sudo ./manage_wg_client.sh add new-device-name
```
You can add unlimited clients on-demand.

**Q: How do I remove a WireGuard client?**  
A: Use the management script:
```bash
sudo ./manage_wg_client.sh remove device-name
```

**Q: How do I see all my WireGuard clients?**  
A: Use the list command:
```bash
sudo ./manage_wg_client.sh list
```

**Q: How do I add more VNC users?**  
A: Add `VNCUSER4_*` variables to `workstation.env`, increment `VNC_USER_COUNT`, and run `sudo ./setup_vnc.sh`.

**Q: What ports are open on my VPS?**  
A: 22 (SSH), 51820/udp (WireGuard), VNC ports (5910-591x), and optionally L2TP ports (500, 1701, 4500/udp).

---

## Next Steps

1. ✅ Complete Cloudflare Zero Trust setup (Part 1)
   - Configure identity provider
   - Create tunnel and get token
   - Set up Access applications
   - Add private network routes
   - Install WARP client on your devices
2. ✅ Run `sudo ./setup_ws.sh` on VPS (Part 2)
3. ✅ Add WireGuard clients with `sudo ./manage_wg_client.sh` (Part 3)
4. ✅ Test Cloudflare private network access (SSH/VNC)
5. ✅ Test WireGuard VPN connection and verify exit IP
6. ✅ Connect to VNC desktops
7. ✅ Read security best practices above

---

## Support

- **WireGuard**: https://www.wireguard.com/
- **Cloudflare Zero Trust**: https://developers.cloudflare.com/cloudflare-one/
- **Ubuntu Server**: https://ubuntu.com/server/docs

---

## License

See [LICENSE](LICENSE) file.

---

**Setup completed!** Enjoy your secure remote access gateway with WireGuard VPN and Cloudflare Zero Trust Access.
