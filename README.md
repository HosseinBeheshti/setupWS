# Secure Remote Access Gateway with Cloudflare Zero Trust

**Secure access solution combining Cloudflare Zero Trust for SSH/VNC access, OpenConnect VPN for secure internet access, and L2TP for app-specific routing in VNC sessions.**

---

## Architecture Overview

This setup provides comprehensive secure remote access:

- **Cloudflare Zero Trust**: Identity-aware SSH/VNC access management
- **OpenConnect VPN (ocserv)**: AnyConnect-compatible VPN server for secure internet access
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
- ✅ **OpenConnect VPN Server** - AnyConnect-compatible VPN (port 443, looks like HTTPS)
- ✅ **L2TP/IPsec VPN** - Application-specific routing in VNC sessions
- ✅ **Multiple VNC Users** - Individual desktop sessions per user
- ✅ **Docker & Dev Tools** - VS Code, Chrome, Firefox pre-installed

---

## Prerequisites

- **VPS**: Ubuntu 24.04 with public IP
- **Cloudflare Account**: Free tier (for Zero Trust Access)
- **Domain**: A domain with DNS managed by Cloudflare (for OpenConnect VPN hostname)
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

3. **Configure required settings** in `workstation.env`:
   - `CLOUDFLARE_TUNNEL_TOKEN`: Your tunnel token from Part 1.3
   - `OCSERV_HOSTNAME`: Your VPN domain (e.g., vpn.yourdomain.com)
     - Create an A record in Cloudflare DNS pointing to your VPS IP
     - **Important**: Set DNS to "DNS only" (disable proxy/orange cloud)
   - `VPS_PUBLIC_IP`: Your VPS public IP address
   - `VNCUSER*_PASSWORD`: Set strong passwords for VNC users
   - `L2TP_*`: L2TP VPN credentials if using VPN_APPS routing
   - `FIREWALL_ALLOWED_PORTS`: Ports to allow through firewall
     - Default: `500/udp,1701/udp,4500/udp,443` (L2TP + OpenConnect)
     - Leave empty for Cloudflare tunnel-only access (most secure)

4. **Save and exit** (`:wq` in vim)

---

### 2.2 Run Automated Setup

**Run the master setup script** (installs everything in correct order):

```bash
sudo ./setup_ws.sh
```

**What this does:**
1. Installs all required packages (VNC, L2TP, Docker, VS Code, Chrome, ocserv, etc.)
2. Configures virtual router for VPN traffic
3. Sets up L2TP/IPsec for VPN_APPS routing in VNC sessions
4. Creates VNC servers for each user
5. Installs cloudflared and configures Cloudflare tunnel for secure access
6. Installs and configures OpenConnect VPN server (ocserv)
7. Configures secure firewall with custom port rules from workstation.env

**Duration**: 10-15 minutes depending on VPS speed.

**Monitor progress** - the script provides detailed status messages.

---

## Part 3: Client Setup

```bash
# Add cloudflare gpg key
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | sudo tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null

# Add this repo to your apt repositories
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

# install cloudflared
sudo apt-get update && sudo apt-get install cloudflared
```

### 3.1 Connect to VNC Desktop

**use VNC client with cloudflared:**
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

1. **SSH via cloudflared**:
    ```bash
    cloudflared access ssh --hostname ssh.yourdomain.org --url localhost:2222
    ```

    ```bash
    ssh -p 2222 username@localhost
    ```
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

### 3.4 Connect to OpenConnect VPN

OpenConnect VPN provides secure internet access through your VPS. It uses the AnyConnect-compatible protocol on port 443, making it look like standard HTTPS traffic.

#### Managing VPN Users

**Add a new VPN user:**
```bash
sudo ./manage_ocserv.sh add username
```
You'll be prompted to enter a password for the user.

**Remove a user:**
```bash
sudo ./manage_ocserv.sh remove username
```

**List all users:**
```bash
sudo ./manage_ocserv.sh list
```

**Disable/Enable a user:**
```bash
sudo ./manage_ocserv.sh disable username
sudo ./manage_ocserv.sh enable username
```

**Change user password:**
```bash
sudo ./manage_ocserv.sh passwd username
```

#### Client Connection

**On Windows/Mac:**
- Download and install [Cisco AnyConnect Client](https://www.cisco.com/c/en/us/support/security/anyconnect-secure-mobility-client/tsd-products-support-series-home.html)
- Or use [OpenConnect GUI](https://openconnect.github.io/openconnect-gui/)
- Server: `vpn.yourdomain.com:443`
- Username: Your VPN username
- Password: Your VPN password

**On Linux:**
```bash
# Install OpenConnect client
sudo apt-get install openconnect

# Connect to VPN
sudo openconnect vpn.yourdomain.com:443
```

**On Android/iOS:**
- Install Cisco AnyConnect from Play Store or App Store
- Add new connection: `vpn.yourdomain.com:443`
- Enter credentials when prompted

#### VPN Features

- ✅ **Port 443 (TCP & UDP)**: Looks like HTTPS, bypasses most firewalls
- ✅ **One Connection Per User**: max-same-clients = 1
- ✅ **Capacity Control**: Supports up to 16 concurrent users (configurable)
- ✅ **Full Traffic Routing**: All client traffic routes through VPS
- ✅ **DNS Privacy**: Uses Google DNS (8.8.8.8) or Cloudflare DNS (1.1.1.1)
- ✅ **Auto-start**: Service starts automatically on boot

---

## Firewall Configuration

The setup includes a centralized firewall configuration via `setup_fw.sh`:

### Default Configuration
- **All incoming ports blocked** except those specified in `FIREWALL_ALLOWED_PORTS`
- **L2TP/IPsec ports**: UDP 500, 1701, 4500 (for L2TP VPN)
- **OpenConnect VPN**: Port 443 TCP/UDP (for ocserv)
- **SSH/VNC access**: Only through Cloudflare tunnel (most secure)

### Customizing Firewall Rules

Edit `FIREWALL_ALLOWED_PORTS` in `workstation.env`:

```bash
# Examples:
# Default (L2TP + OpenConnect):
FIREWALL_ALLOWED_PORTS="500/udp,1701/udp,4500/udp,443"

# OpenConnect only:
FIREWALL_ALLOWED_PORTS="443"

# Add custom web ports:
FIREWALL_ALLOWED_PORTS="80/tcp,443,500/udp,1701/udp,4500/udp"

# Cloudflare tunnel-only (most secure, no direct access):
FIREWALL_ALLOWED_PORTS=""
```

### Manual Firewall Changes

To reconfigure firewall after initial setup:
```bash
sudo ./setup_fw.sh
```

### Security Notes
- Direct SSH/VNC access is **always blocked** for security
- All SSH/VNC access **must go through Cloudflare tunnel**
- L2TP ports (500, 1701, 4500) are opened for L2TP VPN connectivity
- OpenConnect port (443) is opened for VPN access
- Modify `FIREWALL_ALLOWED_PORTS` only if you need additional services

---

## License

See [LICENSE](LICENSE) file.

---

**Setup completed!** Enjoy your secure remote access gateway with VPN and Cloudflare Zero Trust Access.
