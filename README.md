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

## Part 2: VPS Server Setup

### 2.1 Prepare VPS Configuration

1. **SSH into your VPS**:
   ```bash
   ssh root@YOUR_VPS_IP
   ```

2. **Clone this repository and edit `workstation.env`**:
   ```bash
   git clone https://github.com/HosseinBeheshti/setupWS.git
   cd setupWS
    vim workstation.env
   ```

3. **Save and exit** (`:wq` in vim)

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
6. Sets up WARP UDP relay (socat) to bypass ISP filtering (if WARP_ROUTING_ENABLED=true)
7. Configures secure firewall (blocks direct SSH/VNC, forces Cloudflare tunnel)

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

### 3.4 Client Setup for Iran Filtering (Linux)

If you're in Iran or regions where Cloudflare IPs are filtered, configure WARP to use your VPS as a custom endpoint.

**Prerequisites:**
- Cloudflare One Agent installed and registered
- VPS setup completed (Part 2)
- WARP relay service running on VPS

**Configure Custom Endpoint:**

```bash
# Set custom endpoint (requires sudo for Zero Trust)


# Verify it's set
warp-cli settings | grep endpoint
# Should show: (user set) Override WARP endpoint: YOUR_VPS_IP:443

# Connect
warp-cli connect

# Check status
warp-cli status
```

**How It Works:**
- Your device connects to VPS:443 (UDP) instead of Cloudflare's default IPs
- VPS relay (socat) forwards traffic to Cloudflare's MASQUE endpoint (162.159.197.5:443)
- Bypasses ISP blocking of Cloudflare IP ranges
- All SSH/VNC access through Cloudflare tunnel works normally

**Reset to Default (if needed):**
```bash
sudo warp-cli tunnel endpoint reset
```

**Troubleshooting:**

If connection fails:
1. Verify VPS relay is running:
   ```bash
   ssh root@YOUR_VPS_IP "systemctl status warp-relay"
   ```

2. Check WARP mode is correct:
   ```bash
   warp-cli settings | grep Mode
   # Should show: Mode: WarpWithDnsOverHttps or Gateway with WARP
   ```

3. Verify you're using MASQUE protocol:
   ```bash
   warp-cli settings | grep protocol
   # Should show: WARP tunnel protocol: MASQUE
   ```

4. Monitor VPS relay logs:
   ```bash
   ssh root@YOUR_VPS_IP "sudo journalctl -u warp-relay -f"
   ```

---

## License

See [LICENSE](LICENSE) file.

---

**Setup completed!** Enjoy your secure remote access gateway with VPN and Cloudflare Zero Trust Access.
