#!/usr/bin/env bash
set -e

### CONFIG ###
WG_SUBNET="10.13.13.0/24"
WG_DOCKER_SUBNET="10.20.20.0/24"
LAN_SUBNET="192.168.4.0/24"
WIREGUARD_CONTAINER_IP="10.20.20.2"

# Find the bridge interface name dynamically
get_bridge_interface() {
  local network_name=""
  
  # Check for network with and without compose project prefix
  if docker network inspect homeserver_wg_bridge >/dev/null 2>&1; then
    network_name="homeserver_wg_bridge"
  elif docker network inspect wg_bridge >/dev/null 2>&1; then
    network_name="wg_bridge"
  else
    echo "ERROR: Cannot find wg_bridge Docker network. Checked: wg_bridge, homeserver_wg_bridge" >&2
    echo "Available networks:" >&2
    docker network ls >&2
    exit 1
  fi
  
  # Try to get custom bridge name first
  local bridge=$(docker network inspect "$network_name" --format '{{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null)
  
  # If no custom name, get the auto-generated br-XXXX name
  if [ -z "$bridge" ]; then
    local net_id=$(docker network inspect "$network_name" --format '{{.Id}}' | cut -c1-12)
    bridge="br-${net_id}"
  fi
  
  # Verify the interface actually exists
  if ! ip link show "$bridge" >/dev/null 2>&1; then
    echo "ERROR: Bridge interface $bridge does not exist" >&2
    echo "Network $network_name found, but interface $bridge not present" >&2
    echo "Available bridges:" >&2
    ip link show type bridge >&2
    exit 1
  fi
  
  echo "$bridge"
}

echo "[+] Checking Docker network..."
BRIDGE_IFACE=$(get_bridge_interface)
echo "[+] Using bridge interface: $BRIDGE_IFACE"

# Verify WireGuard container is running
if ! docker inspect wireguard >/dev/null 2>&1; then
  echo "ERROR: WireGuard container is not running" >&2
  exit 1
fi

# to find the docker network subnets
# docker network inspect $(docker network ls -q) --format '{{.Name}} -> {{range .IPAM.Config}}{{.Subnet}}{{end}}'
# Docker subnets (adjust if yours differ)
DOCKER_SUBNETS=(
  "172.18.0.0/16"
  "172.19.0.0/16"
  "172.20.0.0/16"
  "172.21.0.0/16"
)

### ENABLE IP FORWARDING ###
echo "[+] Enabling IPv4 forwarding"
sysctl -w net.ipv4.ip_forward=1

# Persist forwarding
SYSCTL_FILE="/etc/sysctl.d/99-ip-forward.conf"
if ! grep -q "net.ipv4.ip_forward=1" "$SYSCTL_FILE" 2>/dev/null; then
  echo "net.ipv4.ip_forward=1" > "$SYSCTL_FILE"
fi

### CRITICAL: ADD ROUTE FOR VPN SUBNET ###
echo "[+] Adding route: $WG_SUBNET via $WIREGUARD_CONTAINER_IP dev $BRIDGE_IFACE"

# Remove old route if exists
if ip route show | grep -q "$WG_SUBNET"; then
  ip route del $WG_SUBNET 2>/dev/null && echo "    [i] Removed existing route" || true
fi

# Add route for VPN clients to go through WireGuard container
if ip route add $WG_SUBNET via $WIREGUARD_CONTAINER_IP dev $BRIDGE_IFACE; then
  echo "    [✓] Route added successfully"
else
  echo "    [!] Failed to add route" >&2
  exit 1
fi

### IPTABLES FORWARD RULES ###
echo "[+] Configuring FORWARD rules (subnet-based)"

# VPN clients → LAN
iptables -C FORWARD -s "$WG_SUBNET" -d "$LAN_SUBNET" -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -s "$WG_SUBNET" -d "$LAN_SUBNET" -j ACCEPT

# LAN → VPN clients (return traffic)
iptables -C FORWARD -s "$LAN_SUBNET" -d "$WG_SUBNET" -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -s "$LAN_SUBNET" -d "$WG_SUBNET" -j ACCEPT

# VPN clients → Docker
for subnet in "${DOCKER_SUBNETS[@]}"; do
  iptables -C FORWARD -s "$WG_SUBNET" -d "$subnet" -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -s "$WG_SUBNET" -d "$subnet" -j ACCEPT

  iptables -C FORWARD -s "$subnet" -d "$WG_SUBNET" -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -s "$subnet" -d "$WG_SUBNET" -j ACCEPT
done

# WireGuard bridge → all traffic
iptables -C FORWARD -s "$WG_DOCKER_SUBNET" -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -s "$WG_DOCKER_SUBNET" -j ACCEPT

iptables -C FORWARD -d "$WG_DOCKER_SUBNET" -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -d "$WG_DOCKER_SUBNET" -j ACCEPT

### NAT FOR VPN → DOCKER ###
echo "[+] Configuring NAT rules"

for subnet in "${DOCKER_SUBNETS[@]}"; do
  iptables -t nat -C POSTROUTING -s "$WG_SUBNET" -d "$subnet" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s "$WG_SUBNET" -d "$subnet" -j MASQUERADE
done

# NAT for VPN clients accessing LAN (optional, but helpful)
iptables -t nat -C POSTROUTING -s "$WG_SUBNET" -d "$LAN_SUBNET" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -s "$WG_SUBNET" -d "$LAN_SUBNET" -j MASQUERADE

echo "[✓] WireGuard → Docker routing configured successfully"

# Display final routing table
echo ""
echo "[+] Current routing table:"
ip route | grep -E "(10.13.13|10.20.20|default)"