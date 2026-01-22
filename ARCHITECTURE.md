# Architecture: Zero Trust + WireGuard VPN

## The Two-Layer Security Model

### Layer 1: Cloudflare One Agent (Zero Trust) - AUTHENTICATION
**Purpose**: Identity verification, device posture checks, access control

**What it does:**
- Authenticates user identity (2FA)
- Checks device health (OS version, firewall, encryption)
- Enforces corporate policies
- Allows/denies access to WireGuard service

**What it does NOT do:**
- Does NOT route internet traffic
- Does NOT replace VPN functionality
- Does NOT provide IP address masking

### Layer 2: WireGuard VPN - CONNECTIVITY
**Purpose**: Secure VPN tunnel for internet routing

**What it does:**
- Routes all internet traffic through VPS
- Masks user's real IP address
- Provides fast, encrypted VPN tunnel
- Gives access to geo-restricted content

**What it does NOT do:**
- Does NOT authenticate users
- Does NOT check device health
- Does NOT enforce policies

---

## Traffic Flow

```
User Device:
┌──────────────────────────────────────┐
│  Cloudflare One Agent (WARP)         │ ← Always running, provides authentication
│  Status: Connected                   │
│  - User authenticated (2FA)          │
│  - Device posture: PASS              │
└──────────────────────────────────────┘
          │
          │ Authentication verified
          │
          ▼
┌──────────────────────────────────────┐
│  Cloudflare Gateway                  │ ← Checks if user is authenticated
│  Network Policy Engine               │
│                                       │
│  IF (user authenticated + posture OK)│
│  THEN allow port 51820               │
│  ELSE block                          │
└──────────────────────────────────────┘
          │
          │ Access granted to port 51820
          │
          ▼
┌──────────────────────────────────────┐
│  WireGuard Client                    │ ← Separate app, actual VPN
│  Status: Connected                   │
│  - Tunnel to VPS                     │
│  - Internet via VPS IP               │
└──────────────────────────────────────┘
          │
          │ All internet traffic
          │
          ▼
┌──────────────────────────────────────┐
│  VPS WireGuard Server (51820)        │
│  Routes traffic to internet          │
└──────────────────────────────────────┘
          │
          ▼
      Internet
```

---

## Example User Experience

### Step 1: User enrolls device (one-time)
- Downloads Cloudflare One Agent
- Enrolls with company team name
- Authenticates with 2FA
- Device posture checks pass

### Step 2: Daily usage
**Without Zero Trust (old way - INSECURE):**
```
User → Opens WireGuard app → Connects → Internet via VPS
❌ Anyone with config file can connect
❌ No identity verification
❌ No device health check
```

**With Zero Trust (new way - SECURE):**
```
User → Ensures Cloudflare One Agent is running →
       Opens WireGuard app → Connects → Internet via VPS

✅ Zero Trust verifies:
   - User identity (2FA)
   - Device health (OS, firewall, etc.)
   - Corporate policies
   
✅ If any check fails → WireGuard connection blocked
✅ If user is fired → Revoke in dashboard → Instant block
```

---

## Key Benefits

| Without Zero Trust | With Zero Trust |
|-------------------|-----------------|
| Anyone with .conf file can connect | Must authenticate + pass device checks |
| No visibility into who's connected | Full audit log of all users |
| Can't check device health | Only healthy devices allowed |
| Manual user management | Centralized dashboard management |
| If user leaves, must manually remove config | Revoke access instantly from dashboard |
| No 2FA | 2FA required |

---

## Split Tunnel Configuration

**Important**: Configure split tunnels so WARP and WireGuard don't conflict:

### Cloudflare One Agent Split Tunnel
Configure to EXCLUDE WireGuard subnet:
```
Exclude Mode:
- 10.13.13.0/24 (WireGuard subnet)
- 192.168.0.0/16 (local network)
- 10.0.0.0/8 (local network)
```

This ensures:
- WARP handles authentication
- WireGuard handles actual VPN routing
- No routing conflicts

---

## Summary

**Cloudflare One Agent**: The BOUNCER at the door
- Checks your ID
- Verifies you're healthy
- Decides if you can enter

**WireGuard**: The SERVICE inside
- Once you're in, you use this
- Provides actual VPN functionality
- Routes your internet traffic

**Both must be running simultaneously for full security + functionality.**
