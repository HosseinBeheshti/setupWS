# Secure Remote Access Gateway with WireGuard VPN

**Hybrid secure access solution combining WireGuard VPN with Cloudflare Zero Trust Access management.**

---

## Architecture Overview

This setup provides two independent security layers:

```
┌─────────────────────────────────────────────────────────────┐
│                    CLIENT DEVICES                            │
│  ┌──────────────────────┐    ┌──────────────────────────┐  │
│  │   WireGuard VPN      │    │  Cloudflare One Agent    │  │
│  │  (All Traffic)       │    │  (SSH/VNC Access)        │  │
│  └──────────┬───────────┘    └───────────┬──────────────┘  │
└─────────────┼────────────────────────────┼─────────────────┘
              │                            │
              │ Direct VPS Connection      │ via Cloudflare Edge
              │ (Port 51820/udp)           │ (Tunneled)
              ▼                            ▼
┌─────────────┴────────────────────────────┴─────────────────┐
│                      VPS SERVER                              │
│  ┌────────────────┐              ┌──────────────────────┐  │
│  │  WireGuard     │              │  cloudflared         │  │
│  │  (wg0)         │              │  (SSH/VNC Tunnel)    │  │
│  │  10.8.0.1/24   │              │                      │  │
│  └────────┬───────┘              └──────────────────────┘  │
│           │                                                  │
│           │ NAT/Masquerade                                  │
│           ▼                                                  │
│    ┌────────────┐    ┌─────────┐    ┌────────────┐        │
│    │   VNC      │    │  Docker │    │  Desktop   │        │
│    │  Servers   │    │         │    │  Apps      │        │
│    └────────────┘    └─────────┘    └────────────┘        │
└──────────────────────────────────────────────────────────────┘
              │
              │ All Traffic Exits
              ▼
           Internet (VPS_PUBLIC_IP)
```

### What You Get

✅ **WireGuard VPN** - True all-traffic VPN with your VPS as exit point  
✅ **Cloudflare Access** - Identity-aware SSH/VNC access (Gmail + OTP)  
✅ **Zero Trust Security** - Policy-based access control for management  
✅ **Multiple VNC Users** - Individual desktop sessions per user  
✅ **L2TP Fallback** - Optional VPN for devices without WireGuard support  
✅ **Docker & Dev Tools** - VS Code, Chrome, Firefox pre-installed

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
WG_CLIENT_COUNT=3                        # ← Number of VPN clients

# VNC Users (configure at least one)
VNCUSER1_USERNAME='alice'
VNCUSER1_PASSWORD='strong_password_here'
VNCUSER1_DISPLAY='1'
VNCUSER1_RESOLUTION='1920x1080'
VNCUSER1_PORT='5910'

# Add more users as needed (VNCUSER2_, VNCUSER3_, etc.)
VNC_USER_COUNT=3

# VPN List (which VPN types to configure)
VPN_LIST="l2tp wg"  # wg=WireGuard, l2tp=L2TP fallback

# Optional: L2TP/IPsec Configuration (for fallback VPN)
L2TP_SERVER_IP='your.l2tp.server.ip'
L2TP_IPSEC_PSK='preshared_key'
L2TP_USERNAME='username'
L2TP_PASSWORD='password'
```

4. **Save and exit** (`:wq` in vim)

---

### 2.2 Run Automated Setup

**Run the master setup script** (installs everything in correct order):

```bash
sudo ./setup_ws.sh
```

**What this does:**
1. Installs all required packages (VNC, WireGuard, Docker, VS Code, Chrome, etc.)
2. Configures virtual router for VPN traffic
3. Sets up L2TP/IPsec (if enabled)
4. Creates VNC servers for each user
5. Installs and configures WireGuard VPN server
6. Installs cloudflared and configures Cloudflare Access

**Duration**: 10-15 minutes depending on VPS speed.

**Monitor progress** - the script provides detailed status messages.

---

## Part 3: Client Setup

### 3.1 Connect via WireGuard VPN

**Desktop Clients (Linux/Mac/Windows):**

1. **Install WireGuard**:
   - Linux: `sudo apt install wireguard`
   - Mac/Windows: Download from [wireguard.com](https://www.wireguard.com/install/)

2. **Copy client configuration from VPS**:
   ```bash
   scp root@YOUR_VPS_IP:/etc/wireguard/clients/client1.conf ~/
   ```

3. **Import configuration**:
   - Linux/Mac: `sudo wg-quick up ~/client1.conf`
   - Windows/Mac GUI: Import `client1.conf` file

4. **Verify connection**:
   ```bash
   curl ifconfig.me
   # Should show your VPS IP
   ```

**Mobile Clients (iOS/Android):**

1. **Install WireGuard app** from App Store/Play Store
2. **Generate QR code on VPS**:
   ```bash
   cat /etc/wireguard/clients/client1_qr.txt
   ```
3. **Scan QR code** in WireGuard app
4. **Connect** and verify IP

---

### 3.2 Connect to VNC Desktop

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

### 3.3 Access via SSH

**Direct SSH**:
```bash
ssh username@YOUR_VPS_IP
```

**Via Cloudflare Access**:
```bash
ssh ssh-vps.yourteam.cloudflareaccess.com
```

---

### 3.4 L2TP/IPsec Fallback (Optional)

For devices that can't run WireGuard:

```bash
sudo ./run_vpn.sh
```

Configure L2TP client with credentials from `workstation.env`.

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

**Q: Can I use both WireGuard and Cloudflare Access simultaneously?**  
A: Yes! They serve different purposes. Use WireGuard for VPN traffic, Cloudflare Access for SSH/VNC management.

**Q: Which VPN should I use - WireGuard or L2TP?**  
A: WireGuard is recommended (faster, more secure). L2TP is fallback for devices without WireGuard support.

**Q: Do I need Cloudflare One Agent for VPN?**  
A: No. WireGuard VPN connects directly to VPS. Cloudflare One Agent is only needed for accessing SSH/VNC via Cloudflare Access.

**Q: Can I add more WireGuard clients later?**  
A: Yes. Edit `WG_CLIENT_COUNT` in `workstation.env` and re-run `sudo ./setup_wg.sh`.

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
