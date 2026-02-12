#!/usr/bin/env bash
# setup-hs-wireguard-nat.sh
# Loads config from .env file in same directory
# Purpose: Add MASQUERADE in WireGuard container for proper return traffic

set -euo pipefail

# Load environment variables from .env
ENV_FILE="${PWD}/../.env"
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Error: .env file not found at ${ENV_FILE}"
    echo "Please create .env with the required variables (see below)."
    exit 1
fi

set -a
source "${ENV_FILE}"
set +a

# Required variables (example .env contents shown in comments)
# WG_CONTAINER_NAME=wireguard
# WG_INTERFACE=wg0

# Validate required variables
required_vars=("WG_CONTAINER_NAME" "WG_INTERFACE")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: Required variable $var is not set in .env"
        exit 1
    fi
done

echo "=== Homeserver WireGuard NAT Setup ==="
echo "Using configuration from .env:"
echo "  WG_CONTAINER_NAME = ${WG_CONTAINER_NAME}"
echo "  WG_INTERFACE      = ${WG_INTERFACE}"
echo ""

# Check container is running
if ! docker ps --filter name="^${WG_CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "${WG_CONTAINER_NAME}"; then
    echo "Error: Container '${WG_CONTAINER_NAME}' not running."
    echo "Run 'docker compose up -d' first."
    exit 1
fi

# Add MASQUERADE rule inside container
echo "Adding POSTROUTING MASQUERADE in ${WG_CONTAINER_NAME} container..."
docker exec "${WG_CONTAINER_NAME}" iptables -t nat -A POSTROUTING -o "${WG_INTERFACE}" -j MASQUERADE

# Verify
echo ""
echo "Current NAT rules in container:"
docker exec "${WG_CONTAINER_NAME}" iptables -t nat -L -n -v

echo ""
echo "To make this persistent, add one of these to your docker-compose.yml under the wireguard service:"

cat << 'EOF'

# Option A: Custom entrypoint (recommended - runs on every container start)
entrypoint: ["/bin/sh", "-c", "iptables -t nat -A POSTROUTING -o ${WG_INTERFACE} -j MASQUERADE && /init"]

# Option B: Use linuxserver/wireguard post-up hook (if supported in your version)
# Create ./system/wireguard/post-up.sh:
# #!/bin/sh
# iptables -t nat -A POSTROUTING -o ${WG_INTERFACE} -j MASQUERADE
# Then in compose:
# command: --post-up /config/post-up.sh

EOF

echo "After updating compose, run:"
echo "  docker compose down && docker compose up -d"

echo ""
echo "Test from VPS after this change:"
echo "  curl -I http://192.168.4.201:5678     # should receive proper response"