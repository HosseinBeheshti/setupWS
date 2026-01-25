# Quick Reference: Gateway with WARP Configuration

## 🎯 The One Critical Setting

**Location:** Settings → WARP Client → Device settings → Default profile

```
┌─────────────────────────────────────────┐
│  Service mode: Gateway with WARP ✅     │
│  (This is THE setting for system-wide)  │
└─────────────────────────────────────────┘
```

**Other modes DON'T work for system-wide routing:**
- ❌ Gateway with DoH → DNS only
- ❌ Proxy mode → localhost proxy only  
- ❌ Secure Web Gateway without DNS → No DNS routing

---

## ⚡ Quick Verification (30 seconds)

```bash
# Test 1: Check DNS (MOST IMPORTANT)
nslookup cloudflare.com
# MUST show: 172.64.36.1 or 172.64.36.2
# If you see 8.8.8.8 or ISP DNS → NOT WORKING!

# Test 2: Check exit IP
curl ifconfig.me
# MUST show: 65.109.210.232 (your VPS IP)
```

**If DNS test fails → Service mode is NOT Gateway with WARP!**

---

## 🔧 Essential Configuration Steps

### 1️⃣ Set Service Mode (Dashboard)
Settings → WARP Client → Device settings → Default profile
- Service mode: **Gateway with WARP**
- Save profile

### 2️⃣ Create Gateway Policies (Dashboard)
Traffic policies → Firewall policies → Network
- Policy 1: `Admin - Full Access + System-wide Routing` (specific emails)
- Policy 2: `User - System-wide Routing Only` (all Gmail users)
- Both policies: Action = Allow

### 3️⃣ Configure Split Tunnels (Dashboard)
Settings → WARP Client → Device settings → Split Tunnels
- Mode: **Exclude IPs and domains**
- Add: `65.109.210.232/32` (your VPS IP)
- Add: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`

### 4️⃣ Client Setup (User Device)
- Install: Cloudflare One Agent
- Login: Team name `noise-ztna`
- Auth: Gmail + One-time PIN
- Connect: Toggle ON

### 5️⃣ Verify (User Device)
```bash
nslookup cloudflare.com  # Must show 172.64.36.x
curl ifconfig.me         # Must show 65.109.210.232
```

---

## 🚨 Troubleshooting Decision Tree

```
Problem: Not all traffic routing through VPS
    ↓
Is DNS using Gateway (172.64.36.x)?
    ├─ YES → Check Gateway policies
    │         └─ User email in policy? → Add email
    └─ NO → Service mode NOT Gateway with WARP!
             ↓
             Go to Device Profile settings
             ↓
             Set: Service mode = Gateway with WARP
             ↓
             Disconnect and reconnect WARP
             ↓
             Test again: nslookup cloudflare.com
```

---

## 📱 What Users See

### Working Correctly ✅
- All websites show VPS IP (65.109.210.232)
- All apps connect through VPS
- Games connect from VPS location
- Streaming shows VPS location
- DNS lookups go through Gateway

### Not Working ❌
- Some apps show real IP
- DNS shows ISP resolver (8.8.8.8, etc.)
- Inconsistent IP between apps
- VPN status shows disconnected

**Fix:** Check Service mode = Gateway with WARP!

---

## 🎓 Understanding the Modes

| Mode | DNS | Network | HTTP | Use Case |
|------|-----|---------|------|----------|
| **Gateway with WARP** | ✅ | ✅ | ✅ | **System-wide VPN replacement** ✅ |
| Gateway with DoH | ✅ | ❌ | ❌ | DNS filtering only |
| Secure Web Gateway | ❌ | ✅ | ✅ | Web filtering (keep existing DNS) |
| Proxy mode | ❌ | ❌ | ✅ | Specific apps only |

**You want: Gateway with WARP = Full VPN replacement**

---

## 📋 Pre-Deployment Checklist

```
Dashboard Configuration:
□ Device Profile: Service mode = Gateway with WARP
□ Gateway Policy: Admin policy created
□ Gateway Policy: User policy created  
□ Split Tunnels: VPS IP excluded
□ WARP Connector: Running on VPS (warp-cli status)

Client Verification:
□ DNS test: nslookup shows 172.64.36.x ← CRITICAL!
□ IP test: curl shows VPS IP
□ WARP status: Connected
□ All apps show VPS IP

If DNS test fails:
□ Double-check Service mode setting
□ Disconnect/reconnect WARP client
□ Check user email in Gateway policy
```

---

## 💡 Key Insights

**The DNS test is the most important:**
```bash
nslookup cloudflare.com
```

- Shows `172.64.36.1` or `172.64.36.2` → ✅ Gateway with WARP is working
- Shows anything else → ❌ System-wide routing NOT active

**Why DNS matters:**
- Gateway with WARP routes ALL traffic, starting with DNS
- If DNS isn't going through Gateway, nothing is
- Other modes might route HTTP but not DNS
- DNS is the first check for proper configuration

---

## 🔗 Quick Links

- Dashboard: https://one.dash.cloudflare.com/
- Device settings: Settings → WARP Client → Device settings
- Gateway policies: Traffic policies → Firewall policies
- Client downloads: https://1.1.1.1/
- Documentation: [SYSTEM-WIDE-ROUTING.md](SYSTEM-WIDE-ROUTING.md)

---

## 🆘 Emergency Fix

**Traffic not routing? Try this:**

1. Dashboard → Device settings → Default profile
2. Verify: Service mode = **Gateway with WARP**
3. Save (even if unchanged)
4. Client → Disconnect WARP
5. Wait 10 seconds
6. Client → Connect WARP
7. Test: `nslookup cloudflare.com`

If still fails → Check Gateway policy includes user email

---

**Remember: "Gateway with WARP" is THE mode for system-wide routing!**
