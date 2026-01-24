# System-wide Traffic Routing Configuration Guide

## ✅ What This Setup Provides

**Complete VPN Replacement** - ALL traffic from your device routes through your VPS:
- ✅ Web browsing (HTTP/HTTPS)
- ✅ DNS queries
- ✅ SSH connections to external servers
- ✅ FTP, SFTP, and file transfers
- ✅ Game traffic
- ✅ Messaging apps
- ✅ Video streaming
- ✅ **Every network connection from every application**

Your **entire system** appears to be located at your VPS IP address.

---

## 🔧 Critical Configuration Requirements

### 1. Device Profile: Gateway with WARP Mode

**Location:** Settings → WARP Client → Device settings → Default profile

**Required Settings:**
- **Service mode:** `Gateway with WARP` ⚠️ CRITICAL
- **Device tunnel protocol:** `MASQUE` or `WireGuard`

**Why this matters:**
```
Gateway with WARP    → Routes DNS + Network + HTTP (EVERYTHING) ✅
Gateway with DoH     → Routes DNS only (NOT ENOUGH) ❌
Proxy mode           → Routes only localhost proxy traffic (NOT ENOUGH) ❌
Secure Web Gateway   → Routes Network + HTTP, but NO DNS ❌
```

**Only "Gateway with WARP" provides complete system-wide traffic routing.**

---

### 2. Gateway Network Policies

**Location:** Traffic policies → Firewall policies → Network

**Required Policies:**

#### Admin Policy
- **Name:** `Admin - Full Access + System-wide Routing`
- **Selector:** User Email `is` admin1@gmail.com, admin2@gmail.com, etc.
- **Action:** Allow
- **What it does:** Allows system-wide traffic routing + SSH/VNC access

#### User Policy
- **Name:** `User - System-wide Routing Only`
- **Selector:** User Email `matches regex` `.*@gmail\.com`
- **Action:** Allow
- **What it does:** Allows system-wide traffic routing only (no SSH/VNC)

---

### 3. Split Tunnels Configuration

**Location:** Settings → WARP Client → Device settings → Split Tunnels

**Mode:** Exclude IPs and domains

**Required Exclusions:**
```
65.109.210.232/32    (your VPS IP - prevents routing loop)
10.0.0.0/8           (private network)
172.16.0.0/12        (private network)
192.168.0.0/16       (private network)
```

**Why:** Prevents infinite routing loops when connecting to VPS itself.

---

## 🧪 Verification Steps

### Test 1: HTTP Traffic (Basic)
```bash
curl ifconfig.me
```
**Expected:** `65.109.210.232` (your VPS IP)

### Test 2: DNS Resolution (Critical)
```bash
nslookup cloudflare.com
```
**Expected:** DNS server should be `172.64.36.1` or `172.64.36.2` (Gateway resolver)

**If you see your ISP's DNS (like 8.8.8.8, 1.1.1.1, etc.) → Gateway with WARP is NOT working!**

### Test 3: Network Traffic
```bash
# Test SSH to external server
ssh user@external-server.com
# Connection goes through VPS

# Check routing table (Linux/macOS)
ip route show | grep CloudflareWARP
# or
netstat -rn | grep -i utun

# Windows
route print
# Look for Cloudflare WARP interface
```

### Test 4: Application Traffic
- Open any app (game, messenger, browser)
- Check its external IP at: https://www.whatismyip.com/
- **Should show:** 65.109.210.232 (VPS IP)

---

## 🚨 Troubleshooting System-wide Routing

### Problem: Only web traffic routes through VPS, other apps show my real IP

**Cause:** Service mode is NOT set to "Gateway with WARP"

**Solution:**
1. Go to: Settings → WARP Client → Device settings
2. Click: Manage on Default profile
3. Verify: Service mode = **Gateway with WARP**
4. Save profile
5. Disconnect and reconnect WARP client

### Problem: DNS still uses my ISP (nslookup shows 8.8.8.8 or ISP DNS)

**Cause:** Gateway with WARP mode not active OR DNS not routing through Gateway

**Solution:**
1. Check Service mode = Gateway with WARP (see above)
2. Check Gateway Network Policy allows your email
3. Verify device is connected to Zero Trust:
   - Open Cloudflare One Agent
   - Settings → Account → should show your team name
   - Status should be: Connected

### Problem: Some applications bypass the VPS

**Cause:** Application uses hardcoded DNS or VPN bypass techniques

**Solution:**
1. Verify Service mode = Gateway with WARP (this should prevent bypassing)
2. Check application settings for proxy/VPN bypass options
3. Some apps (like VPN apps) may conflict - disable other VPN software

### Problem: VPS IP in Split Tunnels but still routing loop

**Cause:** VPS IP not properly excluded

**Solution:**
1. Use CIDR notation: `65.109.210.232/32` (not just `65.109.210.232`)
2. Mode must be: "Exclude IPs and domains"
3. Wait 30 seconds after saving, then reconnect WARP

---

## 📊 Architecture Flow

```
Your Device
    ↓
Cloudflare One Agent (Gateway with WARP mode)
    ↓
Gateway DNS Resolver (172.64.36.1) → DNS queries
Gateway Network Policies → Check permissions
    ↓
WARP Tunnel (encrypted)
    ↓
Cloudflare Edge Network
    ↓
WARP Connector on VPS (65.109.210.232)
    ↓
Internet (all connections exit with VPS IP)
```

**Every single network packet from every application follows this path.**

---

## 🎯 Expected Behavior

### When Gateway with WARP is Working Correctly:

✅ **All DNS queries:**
- Resolved by Gateway DNS (172.64.36.1 or 172.64.36.2)
- Visible in Gateway DNS logs

✅ **All network connections:**
- Route through WARP tunnel
- Exit with VPS IP (65.109.210.232)
- Visible in Gateway Network logs

✅ **All HTTP/HTTPS traffic:**
- Inspected by Gateway (if policies configured)
- Exit with VPS IP
- Visible in Gateway HTTP logs

✅ **Everything shows VPS location:**
- IP lookup websites show VPS IP
- Geo-location shows VPS location
- Streaming services see VPS location
- Games connect from VPS IP

---

## 📱 Platform-Specific Notes

### Desktop (Windows/macOS/Linux)
- Full support for Gateway with WARP mode
- All traffic routes through VPS
- Verify with: `curl ifconfig.me` and `nslookup`

### Mobile (Android/iOS)
- Full support for Gateway with WARP mode
- All app traffic routes through VPS
- No VPN conflicts (only one VPN active: WARP)
- Check Settings → WiFi → Connected to verify no other VPN

### Verification on Mobile
1. Install "What is my IP" app or visit whatismyip.com
2. Should show VPS IP (65.109.210.232)
3. Open any app (game, social media) and check connection
4. Should connect through VPS IP

---

## 🔒 Security Benefits

1. **Complete Traffic Encryption:** All traffic encrypted from device to VPS
2. **Zero Trust Access:** Every connection authenticated and authorized
3. **Device Posture Checks:** Automatic security compliance
4. **DNS Filtering:** Block malicious domains at DNS level
5. **Network Policies:** Control what protocols/destinations allowed
6. **HTTP Inspection:** Optional content filtering and DLP
7. **No Split Tunneling Issues:** All traffic consistently routed

---

## 🆚 Comparison: Gateway with WARP vs Traditional VPN

| Feature | Traditional VPN | Gateway with WARP |
|---------|----------------|-------------------|
| DNS routing | ✅ All DNS | ✅ All DNS |
| Network routing | ✅ All protocols | ✅ All protocols |
| HTTP/HTTPS | ✅ All web traffic | ✅ All web traffic + inspection |
| Mobile support | ⚠️ VPN conflicts | ✅ Single app, no conflicts |
| Authentication | ❌ Shared keys | ✅ Identity-based (Gmail) |
| Device posture | ❌ No checking | ✅ Automatic checks |
| Zero Trust | ❌ Network-based | ✅ Identity + device |
| Management | ❌ Config files | ✅ Cloud dashboard |

**Gateway with WARP = Traditional VPN + Zero Trust + Cloud Management**

---

## 📚 Additional Resources

- **Cloudflare Docs:** [Gateway with WARP mode](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/configure-warp/warp-modes/)
- **WARP Connector:** [Site-to-Internet](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/private-net/warp-connector/site-to-internet/)
- **Your Dashboard:** https://one.dash.cloudflare.com/

---

## ✅ Final Checklist

Before deploying to users, verify:

- [ ] Device Profile: Service mode = Gateway with WARP
- [ ] Gateway Network Policies: Admin and User policies created
- [ ] Split Tunnels: VPS IP excluded (65.109.210.232/32)
- [ ] WARP Connector: Connected on VPS (`warp-cli status`)
- [ ] DNS Test: `nslookup` shows Gateway DNS (172.64.36.x)
- [ ] IP Test: `curl ifconfig.me` shows VPS IP
- [ ] Application Test: All apps show VPS IP
- [ ] Mobile Test: Tested on Android/iOS
- [ ] Access Applications: SSH/VNC restricted to admins

**If all checks pass: ✅ System-wide traffic routing is working correctly!**
