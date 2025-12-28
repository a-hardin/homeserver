#!/usr/bin/env bash
set -e

### CONFIG ###
WG_IF="wg0"
WG_SUBNET="10.13.13.0/24"

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
echo "[+] Configuring FORWARD rules"

iptables -C FORWARD -i "$WG_IF" -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -i "$WG_IF" -j ACCEPT

iptables -C FORWARD -o "$WG_IF" -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -o "$WG_IF" -j ACCEPT

### NAT FOR VPN → DOCKER ###
echo "[+] Configuring NAT rules"

for subnet in "${DOCKER_SUBNETS[@]}"; do
  iptables -t nat -C POSTROUTING -s "$WG_SUBNET" -d "$subnet" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s "$WG_SUBNET" -d "$subnet" -j MASQUERADE
done

echo "[✓] WireGuard → Docker routing configured successfully"
