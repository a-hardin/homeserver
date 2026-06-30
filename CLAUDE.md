# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Home server running self-hosted services via Docker Compose. The server (`192.168.4.201`) is never directly exposed to the internet — all external traffic routes through an OVH VPS (`51.81.33.222`) via a WireGuard site-to-site tunnel. The repo lives at `/var/www/homeserver` on the server.

## Common Commands

```bash
# Start all services
docker compose up -d

# Restart a single service
docker compose restart <service>

# Reload nginx config (no downtime)
docker exec nginx nginx -s reload

# Test nginx config before reloading
docker compose exec nginx nginx -t

# Check WireGuard tunnel status
docker exec wireguard wg show

# Update all submodules to latest
git submodule update --remote --recursive

# Update a single submodule
git submodule update --remote system/<site-name>

# Initialize submodules after cloning
git submodule update --init --recursive
```

## Architecture

### Network Topology

```
Internet → OVH VPS (51.81.33.222) → nginx (SSL termination) → WireGuard tunnel
       → Home Server (192.168.4.201) → nginx (Host header routing) → services
```

SSL terminates at the VPS. The homeserver nginx routes requests by `Host` header on port 80. The WireGuard container (Docker, not host) uses DNAT/MASQUERADE PostUp rules in `system/wireguard/wg_confs/wg0.conf` to forward all tunnel traffic to `192.168.4.201`.

**The homeserver LAN IP must remain static at `192.168.4.201`** — the DNAT rule hardcodes it, and changing it silently breaks all VPS proxying.

### Docker Networks

| Network | Purpose |
|---------|---------|
| `wg_bridge` (10.20.20.0/24) | WireGuard container pinned at 10.20.20.2 |
| `vpn` | Services accessible only over WireGuard |
| `lan` | Services accessible from home LAN directly |
| `public` | nginx-proxied public websites |
| `internal` | Container-to-container only, never exposed |

### Services

| Service | Port | Networks |
|---------|------|---------|
| wireguard | — | wg_bridge |
| nginx | 80, 443 | public, internal |
| nextcloud | 8082 | vpn, lan, internal |
| jellyfin | 8096 | vpn, lan, internal |
| guacamole | 8080 | vpn, lan, internal |
| n8n | 5678 | vpn, internal |
| activepieces | 8081 | vpn, lan, internal |
| mosquitto | 1883, 9001 | vpn, lan, internal |
| portainer | 9000 | vpn, lan |
| title-exam | — | public, internal |
| docuseal | — | public, internal |
| ocr-api | — | internal |
| postgres | 5432 | internal |
| db (mariadb) | — | internal |
| redis | — | internal |

### Static Sites (Git Submodules)

Three public static sites live as submodules, mounted into the nginx container as read-only volumes:

| Submodule path | Domain | nginx conf |
|----------------|--------|-----------|
| `system/hardin-resources` | hardinresources.com | `system/nginx/conf.d/hardin-resources.conf` |
| `system/streamline` | TBD | `system/nginx/conf.d/streamline.conf` |
| `system/tyler-storm` | tylerstormsoccer.com | `system/nginx/conf.d/tyler-storm.conf` |

To add a new static site: add submodule → add nginx conf in `system/nginx/conf.d/` → add volume mount in `docker-compose.yaml` nginx service → `docker exec nginx nginx -s reload`.

To deploy a static site update:
```bash
git submodule update --remote system/<site-name>
docker exec nginx nginx -s reload
```

### Dynamic App — title-exam

Runs as a Docker container (`ghcr.io/${GITHUB_USERNAME}/title-exam-app:latest`) with its own `.env` at `system/title-exam/.env`. nginx proxies it at `title-exam.h4rdn.com`.

### n8n Integration

The `hardin-resources` nginx conf proxies `/contact` to `http://n8n:5678/webhook/hardin-resources/contact` — n8n handles form submissions.

## Troubleshooting

See `README.md` for the full 502 Bad Gateway checklist. Short version:
1. Check `docker compose exec nginx cat /var/log/nginx/<site>-error.log`
2. Ping `10.13.13.2` from VPS — if it fails, restart the WireGuard container
3. Verify PostUp DNAT/MASQUERADE rules exist in `system/wireguard/wg_confs/wg0.conf`

See `homeserver-network.md` for full network architecture, WireGuard PostUp rule explanation, traffic flow diagrams, and rebuild checklist.