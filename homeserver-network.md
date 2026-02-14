# Homeserver Network Architecture

> **Last updated:** February 2026  
> **Purpose:** Reference for owner, future AI agents, and rebuilding on new hardware  
> **Related doc:** See `NetworkArchitecture.md` in the OVH-VPS repo for the full system overview

---

## Overview

The home server runs all self-hosted services and connects to the OVH VPS via a WireGuard
site-to-site tunnel. It is never directly exposed to the internet. All external access goes
through the VPS nginx reverse proxy over the WireGuard tunnel.

```
Internet
    |
    v
[OVH VPS — 51.81.33.222]
    |  nginx (host mode) — terminates SSL, enforces VPN-only access
    |  WireGuard server — 10.13.13.1
    |
    |  WireGuard tunnel (10.13.13.0/24)
    |
    v
[Home Server — 192.168.4.201]
    |  WireGuard client — 10.13.13.2
    |  Docker services — published on host ports
    |
    v
[Home LAN — 192.168.4.0/24]
```

---

## Host Configuration

| Property | Value |
|----------|-------|
| OS | Ubuntu 24 LTS |
| Hostname | hardin |
| LAN IP | 192.168.4.201 (must be static — see note below) |
| WireGuard peer IP | 10.13.13.2 |
| Docker compose dir | /var/www/homeserver |
| LAN interface | eno1 |

**IMPORTANT — LAN IP must be static.** The WireGuard DNAT rule hardcodes `192.168.4.201`.
If DHCP reassigns a different IP, all VPS proxying breaks silently. Set a DHCP reservation
in your router for this machine's MAC address, or configure a static IP in netplan.

---

## Docker Networks

```
homeserver_wg_bridge  (10.20.20.0/24)
    WireGuard container: 10.20.20.2  <- PINNED in docker-compose.yml
    Used for: WireGuard tunnel traffic routing

homeserver_vpn
    Services accessible over WireGuard VPN
    Containers: wireguard, nextcloud, jellyfin, guacamole, n8n, activepieces,
                mosquitto, portainer

homeserver_lan
    Services accessible from home LAN directly
    Containers: nextcloud, jellyfin, guacamole, activepieces, mosquitto, portainer

homeserver_public
    Future: nginx-proxied public websites (not currently in use)

homeserver_internal
    Container-to-container only — never exposed to host or LAN
    Containers: guacd, mysql, postgres, redis
    (also joined by all services that need database access)
```

---

## Service Reference

| Service | Host Port | Networks | Notes |
|---------|-----------|---------|-------|
| wireguard | — | wg_bridge (pinned 10.20.20.2) | Client mode, connects to VPS |
| nginx | 80, 443 | public, internal | Future public sites |
| nextcloud | 8082 | vpn, lan, internal | File sync — trusted_domains configured |
| jellyfin | 8096 | vpn, lan, internal | Media server |
| guacamole | 8080 | vpn, lan, internal | Requires /guacamole/ path |
| guacd | — | internal | Guacamole backend — internal only |
| n8n | 5678 | vpn, internal | Automation — VPN only, no LAN |
| activepieces | 8081 | vpn, lan, internal | Automation |
| mosquitto | 1883, 9001 | vpn, lan, internal | MQTT broker |
| portainer | 9000 | vpn, lan | Container management |
| mysql (mariadb) | — | internal | Guacamole DB — internal only |
| postgres | 5432 | internal | n8n + activepieces DB |
| redis | — | internal | Activepieces cache |

**Note:** postgres currently has `ports: - "5432:5432"` which exposes it to the LAN.
This should be changed to `127.0.0.1:5432:5432` unless you actively need direct DB access.

---

## WireGuard — Client Mode

The home server runs WireGuard in a Docker container in **client mode**. It connects outbound
to the VPS WireGuard server. There is no `wg0` interface on the host — the tunnel exists
only inside the container's network namespace.

### Container config summary

```
Image:          linuxserver/wireguard
Container name: wireguard
Networks:       wg_bridge (pinned 10.20.20.2)
Config path:    ./system/wireguard/wg_confs/wg0.conf
Capabilities:   NET_ADMIN (required for iptables inside container)
```

### `wg0.conf` — critical PostUp rules

```ini
[Interface]
Address = 10.13.13.2
PrivateKey = <hidden>
ListenPort = 51820
DNS = 10.13.13.1

PostUp = iptables -t nat -A POSTROUTING -s 10.13.13.0/24 -o eth0 -j MASQUERADE
PostUp = iptables -t nat -A PREROUTING -i wg0 -j DNAT --to-destination 192.168.4.201
PostUp = iptables -A FORWARD -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s 10.13.13.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D PREROUTING -i wg0 -j DNAT --to-destination 192.168.4.201
PostDown = iptables -D FORWARD -j ACCEPT

[Peer]
PublicKey = <VPS WireGuard server public key>
PresharedKey = <hidden>
Endpoint = 51.81.33.222:51820
AllowedIPs = 10.13.13.0/24
PersistentKeepalive = 25
```

### Why these PostUp rules exist

**The problem:** The VPS nginx (host mode) proxies requests to `10.13.13.2:8082`
(the homeserver's WireGuard peer IP). Those packets travel through the tunnel and arrive
at the homeserver WireGuard container on `wg0`. But port 8082 is not bound on `10.13.13.2` —
it is bound on `192.168.4.201` (the host LAN IP) where Docker publishes service ports.

**DNAT** rewrites the destination of every packet arriving on `wg0` from `10.13.13.2`
to `192.168.4.201` — where the services actually are. This happens before routing,
so the packet is delivered to the correct host port.

**MASQUERADE** rewrites the source IP of packets forwarded from `wg0` to `eth0`
so that service responses go back to the WireGuard container (which forwards them through
the tunnel) rather than directly to the VPN peer IP (which the home router wouldn't know
how to reach).

**FORWARD ACCEPT** allows the container kernel to forward packets between `wg0` (tunnel)
and `eth0` (Docker bridge toward host). Without this the kernel drops forwarded packets.

---

## Traffic Flow

### External VPN browser → Nextcloud

```
Browser (10.13.13.4)
    → HTTPS → VPS ens3:443
    → VPS nginx (host mode): proxy_pass http://10.13.13.2:8082
    → VPS host route: 10.13.13.0/24 via 10.20.30.2 (VPS WireGuard container)
    → VPS WireGuard container: eth0 → wg0 FORWARD
    → WireGuard encrypted tunnel → 51.81.33.222:51820 → 192.168.4.201:51820
    → Homeserver WireGuard container receives on wg0
    → PREROUTING DNAT: dst 10.13.13.2:8082 → 192.168.4.201:8082
    → MASQUERADE: src 10.13.13.4 → 10.13.13.2 (container)
    → Packet delivered to host 192.168.4.201:8082
    → Docker port mapping → Nextcloud container :80
    → Response: 192.168.4.201 → 10.13.13.2 (WireGuard container)
    → Tunnel back to VPS → nginx → browser
```

### Home LAN device → Nextcloud (direct)

```
LAN device (192.168.4.x)
    → http://192.168.4.201:8082  (or https://nextcloud.h4rdn.com if on VPN)
    → Docker port mapping → Nextcloud container :80
    → Response directly to LAN device
```

---

## Nextcloud Trusted Domains

Nextcloud maintains a whitelist of accepted `Host` headers. Requests from unrecognised
domains return HTTP 400. These domains must be in the trusted list:

```bash
docker exec nextcloud php occ config:system:get trusted_domains
# Should show:
# 0: 192.168.4.201:8082
# 1: localhost
# 2: 10.13.13.1
# 3: nextcloud.h4rdn.com
# 4: 10.13.13.2
```

To add a missing entry:
```bash
docker exec nextcloud php occ config:system:set trusted_domains 3 --value="nextcloud.h4rdn.com"
docker exec nextcloud php occ config:system:set trusted_domains 4 --value="10.13.13.2"
```

---

## Guacamole Path Requirement

Guacamole only responds on `/guacamole/` — requests to `/` return 404.
The VPS nginx config handles this with a redirect:

```nginx
location / {
    return 301 /guacamole/;
}
location /guacamole/ {
    proxy_pass http://homeserver_guacamole/guacamole/;
    ...
}
```

When testing Guacamole directly, always use the full path:
```bash
curl -s -o /dev/null -w "%{http_code}" http://192.168.4.201:8080/guacamole/
```

---

## Host Routing

The homeserver host routing table after `docker compose up`:

```
default via 192.168.4.1 dev eno1          <- home router
10.13.13.0/24 via 10.20.20.2 dev br-...  <- WireGuard tunnel (via container bridge)
10.20.20.0/24 dev br-... src 10.20.20.1  <- wg_bridge (Docker managed)
172.18-21.0.0/16 dev br-...              <- Docker service bridges
192.168.4.0/24 dev eno1 src 192.168.4.201 <- LAN
```

The `10.13.13.0/24` route is added automatically by Docker when the WireGuard container
joins `wg_bridge` — it routes VPN peer traffic to the container, which handles it via `wg0`.
No systemd service is needed on the homeserver (unlike the VPS).

---

## Setup Scripts

| Script | Purpose | When to run |
|--------|---------|-------------|
| `scripts/setup-hs-wireguard-routing.sh` | Verifies PostUp rules in wg0.conf, adds them if missing, tests all services | Initial setup only — PostUp handles persistence |

### What the setup script does NOT do

- Does not add crontab entries (not needed)
- Does not install systemd services (not needed — PostUp is the persistence mechanism)
- Does not modify iptables on the host (container handles its own rules)

---

## Rebuild Checklist

1. Install Docker and Docker Compose on Ubuntu 24 LTS
2. Run host setup scripts (`install.sh`, netplan config)
3. Ensure `192.168.4.201` is reserved/static in router
4. Clone repo and restore docker compose directory
5. Copy WireGuard client config from VPS: `./wireguard/config/peer_homeserver/peer_homeserver.conf`
   → place at `./system/wireguard/wg_confs/wg0.conf`
6. Verify PostUp rules are in `wg0.conf` (run setup script to check)
7. `docker compose up -d`
8. Verify tunnel: `docker exec wireguard wg show` (check for recent handshake)
9. Run setup script: `bash scripts/setup-hs-wireguard-routing.sh`
10. Configure Nextcloud trusted domains if needed (setup script will report 400 if required)
11. Test LAN access: `http://192.168.4.201:8082` (Nextcloud)
12. Test VPN access: connect WireGuard client, hit `https://nextcloud.h4rdn.com`

---

## Known Gotchas

**1. postgres exposed on 5432 to LAN**  
`ports: - "5432:5432"` in compose publishes postgres to all interfaces. Low risk on home LAN
but should be `127.0.0.1:5432:5432` if no external tool needs direct DB access.

**2. WireGuard client config is sensitive**  
`wg0.conf` contains the private key and preshared keys. Do not commit it to a public repo.
It should be in `.gitignore`. Back it up securely.

**3. linuxserver/wireguard auto-adds AllowedIPs routes**  
The container automatically runs `ip route add <AllowedIPs> dev wg0` on startup.
Do NOT add a duplicate `ip route add` in PostUp — it causes a `RTNETLINK: File exists`
error and the tunnel fails to come up.

**4. DNAT catches ALL traffic arriving on wg0**  
The PREROUTING DNAT rule rewrites the destination of every packet arriving on `wg0`
to `192.168.4.201`. This means VPN peers cannot reach individual container IPs directly —
all traffic is redirected to the host. This is intentional and correct for this setup.

**5. wg0.conf regenerates on PEERS change**  
If you change the `PEERS=` variable in the VPS WireGuard container env and recreate it,
the peer configs in `./wireguard/config/peer_homeserver/` are regenerated. The homeserver's
`wg0.conf` must be updated with the new keys if the VPS server keys change.

---

*Keep this document updated when the network architecture changes.*
*Store alongside docker-compose.yml in version control.*
