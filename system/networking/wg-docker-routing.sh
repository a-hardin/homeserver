#!/usr/bin/env bash
set -e

### CONFIG ###
WG_SUBNET="10.13.13.0/24"

WG_DOCKER_SUBNET="10.20.20.0/24"
LAN_SUBNET="192.168.4.0/24"


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

### MSS CLAMPING (PREROUTING — REQUIRED) ###
# echo "[+] Applying TCP MSS clamping (PREROUTING)"
echo "[!] TCP MSS clamping disabled (nftables compatibility)"

# iptables -t mangle -C PREROUTING -s "$WG_SUBNET" -p tcp --tcp-flags SYN,RST SYN \
#   -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
# iptables -t mangle -A PREROUTING -s "$WG_SUBNET" -p tcp --tcp-flags SYN,RST SYN \
#   -j TCPMSS --clamp-mss-to-pmtu

# iptables -t mangle -C PREROUTING -d "$WG_SUBNET" -p tcp --tcp-flags SYN,RST SYN \
#   -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
# iptables -t mangle -A PREROUTING -d "$WG_SUBNET" -p tcp --tcp-flags SYN,RST SYN \
#   -j TCPMSS --clamp-mss-to-pmtu

### NAT FOR VPN → DOCKER ###
echo "[+] Configuring NAT rules"

for subnet in "${DOCKER_SUBNETS[@]}"; do
  iptables -t nat -C POSTROUTING -s "$WG_SUBNET" -d "$subnet" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s "$WG_SUBNET" -d "$subnet" -j MASQUERADE
done

echo "[✓] WireGuard → Docker routing configured successfully"
