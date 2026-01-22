# WireGuard Port Configuration for Iran

## Overview

This setup uses **443/UDP** as the default WireGuard port instead of the standard 51820/UDP. This is critical for Iran where the default WireGuard port is commonly blocked by DPI (Deep Packet Inspection) systems.

## Why Port 443/UDP?

**Port 443/UDP** is the standard port for:
- HTTPS over QUIC (HTTP/3)
- Modern web traffic encryption
- Google, Cloudflare, and major CDN traffic

**Benefits:**
- ✅ Appears as normal HTTPS/QUIC traffic to DPI
- ✅ Extremely difficult to block (would break modern web)
- ✅ Common port that blends in with regular traffic
- ✅ Used by millions of websites globally

## Alternative Port Options

If 443/UDP doesn't work or you want additional obfuscation:

| Port | Protocol Mimicked | Detection Risk | Notes |
|------|------------------|----------------|-------|
| **443/UDP** | HTTPS/QUIC | Very Low | **Recommended** - Default modern web |
| **53/UDP** | DNS | Low | May conflict with actual DNS |
| **123/UDP** | NTP (time sync) | Low | Time synchronization traffic |
| **5060/UDP** | SIP (VoIP) | Medium | Voice traffic, less common |
| **40000-50000** | High ports | Medium | Generic traffic, less predictable |
| ⛔ **51820/UDP** | WireGuard | **HIGH** | **Blocked in Iran** |

## Configuration Files

The WireGuard port is configured in **one place** and propagated everywhere:

### 1. Primary Configuration: `workstation.env`

```bash
# WireGuard Configuration
WG_PORT="443"  # Obfuscated port (appears as HTTPS/QUIC traffic)
```

**This variable is used by:**
- `setup_server.sh` - UFW firewall rules
- `docker-compose-ztna.yml` - Port mapping
- `add_wg_peer.sh` - Client config generation

### 2. Files That Reference WG_PORT

| File | Purpose | Auto-Updated |
|------|---------|--------------|
| [workstation.env](workstation.env) | Central config | ✅ Manual edit |
| [setup_server.sh](setup_server.sh) | Reads from env | ✅ Automatic |
| [add_wg_peer.sh](add_wg_peer.sh) | Reads from env | ✅ Automatic |
| [docker-compose-ztna.yml](docker-compose-ztna.yml) | Uses `${WG_PORT}` | ✅ Automatic |

## Cloudflare Gateway Policy Update

**⚠️ CRITICAL**: When you change the WireGuard port, you MUST update your Cloudflare Gateway Network Policy!

### Update Gateway Network Policy:

1. Go to **Cloudflare One Dashboard** → **Traffic policies** → **Network**
2. Edit policy: **"Allow Authenticated Users to WireGuard"**
3. Update the **Traffic Conditions** table:

   | Selector | Operator | Value |
   |----------|----------|-------|
   | Destination IP | in | `<YOUR-VPS-IP>` |
   | **AND** Destination Port | is | **443** ← Update this! |
   | **AND** Protocol | is | UDP |

4. Also update the **Block policy** with same port change
5. Click **Save policy**

**If you forget this step**, users will be blocked even after authentication!

## How to Change the Port

### Option 1: Before Initial Setup (Recommended)

1. Edit `workstation.env` before running `setup_server.sh`:
   ```bash
   nano workstation.env
   # Change: WG_PORT="443"  (or your preferred port)
   ```

2. Run setup:
   ```bash
   sudo bash setup_server.sh
   ```

3. Update Cloudflare Gateway Network Policy (see above)

### Option 2: After Setup (Server Already Running)

1. Stop containers:
   ```bash
   cd /root/setupWS
   docker compose -f docker-compose-ztna.yml down
   ```

2. Update configuration:
   ```bash
   nano workstation.env
   # Change: WG_PORT="<new-port>"
   ```

3. Update firewall:
   ```bash
   # Remove old rule (if needed)
   ufw delete allow 51820/udp
   
   # Add new rule
   source workstation.env
   ufw allow ${WG_PORT}/udp comment 'WireGuard'
   ```

4. Restart containers:
   ```bash
   source workstation.env
   docker compose -f docker-compose-ztna.yml up -d
   ```

5. **CRITICAL**: Update Cloudflare Gateway Network Policy (see above)

6. Regenerate all client configs:
   ```bash
   # Delete old configs
   rm -rf /var/lib/ztna/clients/*
   
   # Regenerate for each user
   sudo bash add_wg_peer.sh username1
   sudo bash add_wg_peer.sh username2
   # ... etc
   ```

7. Distribute new configs to users

## Verification

### On Server:

```bash
# Check Docker container port mapping
docker ps
# Look for: 0.0.0.0:443->51820/udp (or your port)

# Check UFW firewall
sudo ufw status
# Should show: 443/udp ALLOW Anywhere

# Check WireGuard is listening
netstat -tuln | grep 443
# Should show: udp 0.0.0.0:443
```

### On Client:

1. Import new WireGuard config (with updated port)
2. Verify config shows correct endpoint:
   ```
   [Peer]
   Endpoint = <VPS-IP>:443
   ```
3. Ensure Cloudflare One Agent is connected
4. Connect WireGuard
5. Test internet access

### In Cloudflare Dashboard:

1. Go to **Analytics** → **Gateway** → **Network logs**
2. Filter: `Destination Port = 443` (or your port)
3. Should see **Allow** actions for authenticated users
4. Should see **Block** actions for non-authenticated attempts

## Security Considerations

### Port 443 Security:

✅ **Pros:**
- Mimics HTTPS/QUIC traffic
- Extremely difficult to block
- Blends with 90% of modern web traffic
- DPI systems would break legitimate traffic if blocked

⚠️ **Cons:**
- If you run a web server on the same VPS, you CANNOT use 443/TCP for HTTPS (different protocol though)
- 443/UDP (WireGuard) and 443/TCP (HTTPS/OpenVPN) can coexist on same server
- **Note**: This setup includes OpenVPN on 443/TCP - NO CONFLICT with WireGuard 443/UDP

### Other Ports:

- **53/UDP**: May conflict with DNS resolution on client
- **123/UDP**: May conflict with NTP time sync
- **High ports (40000+)**: Less scrutiny but also less "normal" traffic

## Testing in Iran

### Expected Behavior:

✅ **With Port 443/UDP:**
- WireGuard connects normally
- Appears as QUIC/HTTP3 traffic
- Should bypass most filtering

⛔ **With Port 51820/UDP:**
- Connection fails or times out
- May show "handshake timeout"
- Blocked by DPI systems

### Troubleshooting in Iran:

1. **Connection fails on port 443:**
   - Try 53/UDP or 123/UDP
   - Try high random port (e.g., 41194/UDP)
   - Ensure Cloudflare Gateway policy matches port

2. **Intermittent disconnections:**
   - Iran may use statistical analysis (not just port)
   - Consider running WireGuard through obfs4proxy or similar
   - Use keepalive in WireGuard config (already configured: 25 seconds)

3. **Slow speeds:**
   - Normal for obfuscated traffic
   - Try different DNS: 1.1.1.1, 8.8.8.8, or 10.202.10.202
   - Check MTU settings (configured: 1420)

## References

- **WireGuard Port Documentation**: https://www.wireguard.com/
- **Iran Internet Filtering**: Research papers on DPI in Iran
- **QUIC Protocol**: RFC 9000 (HTTP/3 over UDP)
- **Cloudflare Gateway**: https://developers.cloudflare.com/cloudflare-one/policies/gateway/

## Summary

1. **Default Port**: 443/UDP (mimics HTTPS/QUIC)
2. **Configuration**: One place - `workstation.env` → `WG_PORT="443"`
3. **Propagation**: Automatic via scripts and docker-compose
4. **Critical Step**: Update Cloudflare Gateway Network Policy to match port
5. **For Iran**: Port 443/UDP recommended, 51820/UDP blocked
6. **Verification**: Check Docker logs, UFW rules, Cloudflare Gateway logs
