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

### 1.1 Configure Identity Provider and Admin Policy

Set up Gmail authentication with One-time PIN:

1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
2. Navigate to: **Settings → Authentication**
3. Under **Login methods**, click **Add new**
4. Select **One-time PIN**
5. Click **Save**

**Create Admin Policy for Device Enrollment:**

1. Go to: **Settings → WARP Client**
2. Under **Device enrollment**, click **Manage**
3. Click **Add a rule**
4. Configure policy:
   - **Rule name**: `Admin Access`
   - **Rule action**: `Allow`
   - **Selector**: `Emails`
   - **Value**: `your-admin@gmail.com` (your email)
5. Click **Save**

---

### 1.2 Create Cloudflare Tunnel for SSH/VNC Access

**Important**: Create a regular **Cloudflare Tunnel** (cloudflared), NOT WARP Connector.

1. Go to: **Networks → Tunnels**
2. Click **Create a tunnel**
3. Select **Cloudflared** as connector type
4. **Tunnel name**: `vps-access` (or any name you prefer)
5. Click **Save tunnel**
6. **Select environment**: Linux
7. You'll see installation commands - **copy the token** from the command:
   
   ```bash
   cloudflared service install eyJhIjoiN...  # ← Copy this token
   ```
   
   **Copy only the token part** (long string starting with `eyJ...`)
8. **Save this token** - you'll add it to `workstation.env` as `CLOUDFLARE_TUNNEL_TOKEN`
9. Click **Next**
10. **Don't add public hostname yet** - we'll configure access applications separately
11. Click **Save tunnel**

**Result**: Cloudflare Tunnel created and ready for SSH/VNC access.

---

### 1.3 Create Access Application for SSH

1. Go to: **Access → Applications**
2. Click **Add an application**
3. Select **Self-hosted**
4. Configure application:
   - **Application name**: `VPS SSH Access`
   - **Session duration**: `24 hours`
   - **Application domain**: `ssh-vps` (subdomain)
   - **Subdomain**: Choose your team domain
   - **Path**: Leave empty
5. Click **Next**

**Configure Policy:**
   - **Policy name**: `Allow Admins`
   - **Action**: `Allow`
   - **Selector**: `Emails`
   - **Value**: `your-admin@gmail.com`
6. Click **Next**, then **Add application**

**Add SSH Configuration:**
1. Go back to **Networks → Tunnels**
2. Click on your `vps-access` tunnel → **Configure**
3. Go to **Public Hostname** tab
4. Click **Add a public hostname**
5. Configure:
   - **Subdomain**: `ssh-vps`
   - **Domain**: Your team domain
   - **Service**: `SSH`
   - **URL**: `localhost:22`
6. Click **Save hostname**

---

### 1.4 Create Access Applications for VNC (Optional)

Repeat the process for each VNC user/port:

1. **Access → Applications → Add an application**
2. Configure for each VNC port (e.g., 5910, 5911, 5912)
3. Use same policy (Allow Admins with your email)
4. Add public hostname in tunnel configuration for each VNC service

---

### 1.5 Install Cloudflare One Agent (Optional - for SSH/VNC)

**On your client device** (if you want to access SSH/VNC via Cloudflare Access):

1. Download: [Cloudflare One Agent](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/download-warp/)
2. Install and authenticate with your Gmail account
3. Access SSH via: `ssh-vps.yourteam.cloudflareaccess.com`

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
CLOUDFLARE_TUNNEL_TOKEN="eyJhIjoiN..."  # ← Paste token from Part 1.2
TUNNEL_NAME="vps-access"                 # ← Match tunnel name from Part 1.2

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

**Direct Connection (when NOT using Cloudflare Access):**

1. **Install VNC client**:
   - RealVNC Viewer, TigerVNC, Remmina, etc.

2. **Connect**:
   - Address: `YOUR_VPS_IP:5910` (for VNCUSER1)
   - Password: (from workstation.env)

**Via Cloudflare Access (if configured in Part 1.4):**

1. Install Cloudflare One Agent
2. Access via application URL from dashboard

---

### 3.4 Access via SSH

**Direct SSH**:
```bash
ssh username@YOUR_VPS_IP
```

**Via Cloudflare Access**:
```bash
ssh ssh-vps.yourteam.cloudflareaccess.com
```

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
sudo cloudflared tunnel info vps-access
```

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

# Verify credentials
sudo cat /etc/cloudflared/credentials.json
# Should contain valid JSON with AccountTag

# Restart service
sudo systemctl restart cloudflared
```

**Can't access SSH via Cloudflare:**
- Verify application is created in Dashboard
- Check DNS: `ssh-vps.yourteam.cloudflareaccess.com` should resolve
- Verify access policy allows your email
- Install Cloudflare One Agent on client device

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

# Recent activity
sudo cloudflared tunnel info vps-access
```

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

**Q: Do I need Cloudflare One Agent for VPN?**  
A: No. WireGuard VPN connects directly to VPS. Cloudflare One Agent is only needed for accessing SSH/VNC via Cloudflare Access.

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

1. ✅ Complete Cloudflare Zero Trust setup
2. ✅ Run `sudo ./setup_ws.sh` on VPS
3. ✅ Distribute WireGuard configs to clients
4. ✅ Test VPN connection and verify exit IP
5. ✅ Connect to VNC desktops
6. ✅ (Optional) Configure Cloudflare Access for SSH/VNC
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
