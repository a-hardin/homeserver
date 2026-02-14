#!/usr/bin/env bash
# setup-hs-wireguard-routing.sh
#
# PURPOSE:
#   Sets up WireGuard NAT/forwarding on the home server so the VPS can proxy
#   to home server services through the tunnel.
#
# ARCHITECTURE:
#   - WireGuard is fully containerized (client mode) — no wg0 on host
#   - Services are published on host LAN IP (192.168.4.201) via Docker ports
#   - VPS nginx proxies to 10.13.13.2 (homeserver WireGuard peer IP)
#   - Packets arrive at homeserver WireGuard container on wg0
#   - DNAT rewrites destination: 10.13.13.2 → 192.168.4.201 (host LAN IP)
#   - MASQUERADE rewrites source so responses return via the container
#   - FORWARD ACCEPT allows the container to forward between wg0 and eth0
#
# WHAT THIS SCRIPT DOES:
#   1. Verifies WireGuard container is running and tunnel is up
#   2. Checks PostUp rules exist in wg0.conf (they are the persistent mechanism)
#   3. If PostUp rules are missing — adds them and restarts the container
#   4. Verifies iptables rules are active inside the container
#   5. Runs end-to-end service reachability tests
#
# PERSISTENCE:
#   Rules are applied via PostUp in ./system/wireguard/wg_confs/wg0.conf
#   They reapply automatically every time the WireGuard container starts.
#   This script does NOT need to run on every boot — only on initial setup.
#
# PREREQUISITES:
#   - Docker and docker-compose installed and running
#   - Home server stack up (wireguard container running)
#   - WireGuard client config at ./system/wireguard/wg_confs/wg0.conf
#   - VPS WireGuard server reachable (tunnel handshake required)
#   - .env file in parent directory (../.env)
#
# USAGE:
#   bash setup-hs-wireguard-routing.sh
#   (run from repo root — does not require root)

set -euo pipefail

# ─── Paths (relative to repo root) ──────────────────────────────────────────
# Repo structure:
#   homeserver/
#   ├── system/
#   │   └── wireguard/
#   │       └── wg_confs/
#   │           └── wg0.conf
#   ├── .env
#   ├── docker-compose.yml
#   └── setup-hs-wireguard-routing.sh   <- this file (repo root)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"               # script lives at repo root
ENV_FILE="${REPO_ROOT}/.env"
WG0_CONF="${REPO_ROOT}/system/wireguard/wg_confs/wg0.conf"

# ─── Load .env ───────────────────────────────────────────────────────────────
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Error: .env file not found at ${ENV_FILE}"
    exit 1
fi

set -a
source "${ENV_FILE}"
set +a

# ─── Configuration ────────────────────────────────────────────────────────────
# All stable values — derived from pinned IPs in docker-compose.yml and network design.
# HOMESERVER_LAN_IP must be static (DHCP reservation or netplan static).
# If it changes, the DNAT rule breaks silently.

HOMESERVER_LAN_IP="${HOMESERVER_LAN_IP:-192.168.4.201}"
HOMESERVER_WG_IP="${HOMESERVER_WG_IP:-10.13.13.2}"
VPS_WG_IP="${VPS_WG_IP:-10.13.13.1}"
WG_TUNNEL_SUBNET="${WG_TUNNEL_SUBNET:-10.13.13.0/24}"
WG_CONTAINER="${WG_CONTAINER_NAME:-wireguard}"

# ─── Validate required vars ───────────────────────────────────────────────────
required_vars=("HOMESERVER_LAN_IP" "HOMESERVER_WG_IP")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: Required variable ${var} is not set in .env"
        exit 1
    fi
done

echo ""
echo "========================================================"
echo "       Homeserver WireGuard Routing Setup"
echo "========================================================"
echo ""
echo "Configuration:"
echo "  Homeserver LAN IP (DNAT target) : ${HOMESERVER_LAN_IP}"
echo "  Homeserver WireGuard peer IP    : ${HOMESERVER_WG_IP}"
echo "  VPS WireGuard server IP         : ${VPS_WG_IP}"
echo "  WireGuard tunnel subnet         : ${WG_TUNNEL_SUBNET}"
echo "  WireGuard container name        : ${WG_CONTAINER}"
echo ""

# ─── Step 1: Verify container is running ─────────────────────────────────────
echo "-- Step 1: Checking WireGuard container ---------------------"
if ! docker ps --filter "name=^${WG_CONTAINER}$" --format '{{.Names}}' | grep -q "${WG_CONTAINER}"; then
    echo "  ERROR: Container '${WG_CONTAINER}' is not running."
    echo "  Start the stack: cd ${REPO_ROOT} && docker compose up -d"
    exit 1
fi
echo "  OK  Container '${WG_CONTAINER}' is running"

# ─── Step 2: Verify tunnel is up ─────────────────────────────────────────────
echo ""
echo "-- Step 2: Checking tunnel ----------------------------------"
WG_STATUS=$(docker exec "${WG_CONTAINER}" wg show 2>/dev/null || echo "")
if [[ -z "${WG_STATUS}" ]]; then
    echo "  ERROR: WireGuard tunnel is not up."
    echo "  Check logs: docker logs ${WG_CONTAINER} --tail 30"
    exit 1
fi

HANDSHAKE=$(echo "${WG_STATUS}" | grep "latest handshake" | head -1 || true)
TRANSFER=$(echo "${WG_STATUS}" | grep "transfer" | head -1 || true)
echo "  OK  Tunnel is up"
echo "      ${HANDSHAKE:-no handshake yet}"
echo "      ${TRANSFER}"

if docker exec "${WG_CONTAINER}" ping -c1 -W3 "${VPS_WG_IP}" > /dev/null 2>&1; then
    echo "  OK  Can ping VPS at ${VPS_WG_IP}"
else
    echo "  WARN  Cannot ping VPS at ${VPS_WG_IP} — continuing anyway"
fi
echo ""

# ─── Step 3: Check wg0.conf PostUp rules ─────────────────────────────────────
echo "-- Step 3: Checking wg0.conf PostUp rules -------------------"

if [[ ! -f "${WG0_CONF}" ]]; then
    echo "  ERROR: wg0.conf not found at ${WG0_CONF}"
    exit 1
fi

HAS_MASQ=$(grep -c "POSTROUTING.*MASQUERADE" "${WG0_CONF}" || true)
HAS_DNAT=$(grep -c "PREROUTING.*DNAT" "${WG0_CONF}" || true)
HAS_FWD=$(grep -c "FORWARD.*ACCEPT" "${WG0_CONF}" || true)
NEEDS_UPDATE=false

[[ "${HAS_MASQ}" -eq 0 ]] && { echo "  MISSING  POSTROUTING MASQUERADE"; NEEDS_UPDATE=true; }
[[ "${HAS_DNAT}" -eq 0 ]] && { echo "  MISSING  PREROUTING DNAT"; NEEDS_UPDATE=true; }
[[ "${HAS_FWD}"  -eq 0 ]] && { echo "  MISSING  FORWARD ACCEPT"; NEEDS_UPDATE=true; }

if [[ "${NEEDS_UPDATE}" == "true" ]]; then
    echo ""
    echo "  PostUp rules missing. Adding to wg0.conf..."

    # Backup original
    cp "${WG0_CONF}" "${WG0_CONF}.bak"
    echo "  Backup saved: ${WG0_CONF}.bak"

    # Build new config: insert PostUp/PostDown before first [Peer] block
    TMPFILE=$(mktemp)
    INSERTED=false
    while IFS= read -r line; do
        if [[ "${line}" == "[Peer]"* ]] && [[ "${INSERTED}" == "false" ]]; then
            # Write PostUp block before [Peer]
            printf '\n' >> "${TMPFILE}"
            printf 'PostUp = iptables -t nat -A POSTROUTING -s %s -o eth0 -j MASQUERADE\n' "${WG_TUNNEL_SUBNET}" >> "${TMPFILE}"
            printf 'PostUp = iptables -t nat -A PREROUTING -i wg0 -j DNAT --to-destination %s\n' "${HOMESERVER_LAN_IP}" >> "${TMPFILE}"
            printf 'PostUp = iptables -A FORWARD -j ACCEPT\n' >> "${TMPFILE}"
            printf 'PostDown = iptables -t nat -D POSTROUTING -s %s -o eth0 -j MASQUERADE\n' "${WG_TUNNEL_SUBNET}" >> "${TMPFILE}"
            printf 'PostDown = iptables -t nat -D PREROUTING -i wg0 -j DNAT --to-destination %s\n' "${HOMESERVER_LAN_IP}" >> "${TMPFILE}"
            printf 'PostDown = iptables -D FORWARD -j ACCEPT\n' >> "${TMPFILE}"
            printf '\n' >> "${TMPFILE}"
            INSERTED=true
        fi
        printf '%s\n' "${line}" >> "${TMPFILE}"
    done < "${WG0_CONF}"

    mv "${TMPFILE}" "${WG0_CONF}"
    echo "  OK  PostUp rules added to wg0.conf"
    echo ""
    echo "  Restarting WireGuard container to apply rules..."
    cd "${REPO_ROOT}" && docker compose restart "${WG_CONTAINER}"
    sleep 6
    echo "  OK  Container restarted"
else
    echo "  OK  POSTROUTING MASQUERADE : present"
    echo "  OK  PREROUTING DNAT        : present"
    echo "  OK  FORWARD ACCEPT         : present"
fi
echo ""

# ─── Step 4: Verify rules are active in the container ────────────────────────
echo "-- Step 4: Verifying active iptables rules ------------------"

DNAT_ACTIVE=$(docker exec "${WG_CONTAINER}" iptables -t nat -L PREROUTING -v -n 2>/dev/null | grep "DNAT" || true)
MASQ_ACTIVE=$(docker exec "${WG_CONTAINER}" iptables -t nat -L POSTROUTING -v -n 2>/dev/null | grep "MASQUERADE" | grep -v "DOCKER" || true)
FWD_ACTIVE=$(docker exec "${WG_CONTAINER}"  iptables -L FORWARD -v -n 2>/dev/null | grep "ACCEPT" || true)
ALL_RULES_OK=true

if [[ -n "${DNAT_ACTIVE}" ]]; then
    DNAT_TARGET=$(echo "${DNAT_ACTIVE}" | awk '{print $NF}' | head -1)
    echo "  OK  DNAT active → ${DNAT_TARGET}"
else
    echo "  FAIL  DNAT rule not active in container"
    ALL_RULES_OK=false
fi

if [[ -n "${MASQ_ACTIVE}" ]]; then
    echo "  OK  MASQUERADE active"
else
    echo "  FAIL  MASQUERADE rule not active"
    ALL_RULES_OK=false
fi

if [[ -n "${FWD_ACTIVE}" ]]; then
    echo "  OK  FORWARD ACCEPT active"
else
    echo "  FAIL  FORWARD ACCEPT not active"
    ALL_RULES_OK=false
fi

if [[ "${ALL_RULES_OK}" == "false" ]]; then
    echo ""
    echo "  Rules not active despite PostUp being set."
    echo "  Check: docker logs ${WG_CONTAINER} --tail 30"
    echo "  Try:   cd ${REPO_ROOT} && docker compose restart ${WG_CONTAINER}"
fi
echo ""

# ─── Step 5: Service tests ────────────────────────────────────────────────────
echo "-- Step 5: Service reachability tests -----------------------"
echo "  Testing from inside WireGuard container (simulates VPS tunnel traffic)..."
echo ""

declare -A SERVICES
SERVICES["nextcloud"]="${HOMESERVER_LAN_IP}:8082"
SERVICES["guacamole"]="${HOMESERVER_LAN_IP}:8080/guacamole/"
SERVICES["n8n"]="${HOMESERVER_LAN_IP}:5678"
SERVICES["home-portainer"]="${HOMESERVER_LAN_IP}:9000"

declare -A DOMAINS
DOMAINS["nextcloud"]="${NEXTCLOUD_DOMAIN:-nextcloud.h4rdn.com}"
DOMAINS["guacamole"]="${GUACAMOLE_DOMAIN:-guacamole.h4rdn.com}"
DOMAINS["n8n"]="${N8N_DOMAIN:-n8n.h4rdn.com}"
DOMAINS["home-portainer"]="${HOME_PORTAINER_DOMAIN:-home-portainer.h4rdn.com}"

ALL_PASS=true
for service in nextcloud guacamole n8n home-portainer; do
    url="http://${SERVICES[$service]}"
    domain="${DOMAINS[$service]}"
    code=$(docker exec "${WG_CONTAINER}" \
        curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 5 --max-time 10 \
        -H "Host: ${domain}" "${url}" 2>/dev/null || echo "000")

    if [[ "${code}" == "000" ]]; then
        echo "  FAIL  ${service}: no response — check DNAT and that container is running"
        ALL_PASS=false
    elif [[ "${code}" =~ ^[23] ]]; then
        echo "  OK    ${service}: ${code}"
    elif [[ "${code}" == "400" ]]; then
        echo "  WARN  ${service}: 400 — likely trusted_domains not configured (see below)"
        ALL_PASS=false
    else
        echo "  WARN  ${service}: ${code}"
    fi
done
echo ""

# ─── Summary ─────────────────────────────────────────────────────────────────
echo "-- Summary --------------------------------------------------"
if [[ "${ALL_PASS}" == "true" ]]; then
    echo "  All services reachable. Homeserver routing is fully configured."
    echo ""
    echo "  Rules are persistent via PostUp in wg0.conf."
    echo "  No crontab or host-level service needed."
    echo ""
    echo "  Verify from VPS after this is done:"
    echo "    docker exec wireguard curl -s -o /dev/null -w '%{http_code}' \\"
    echo "      -H 'Host: nextcloud.h4rdn.com' http://${HOMESERVER_WG_IP}:8082"
else
    echo "  Some services failed. Common fixes:"
    echo ""
    echo "  Nextcloud 400 (trusted_domains):"
    echo "    docker exec nextcloud php occ config:system:get trusted_domains"
    echo "    docker exec nextcloud php occ config:system:set trusted_domains 3 --value=nextcloud.h4rdn.com"
    echo "    docker exec nextcloud php occ config:system:set trusted_domains 4 --value=${HOMESERVER_WG_IP}"
    echo ""
    echo "  Service not running:"
    echo "    docker ps --format 'table {{.Names}}\t{{.Ports}}'"
    echo ""
    echo "  Restart WireGuard:"
    echo "    cd ${REPO_ROOT} && docker compose restart ${WG_CONTAINER}"
fi
echo ""