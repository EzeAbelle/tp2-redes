#!/bin/bash
# Agrega un cliente (peer) a la VPN y genera su archivo de configuracion
# Uso: sudo agregar-peer.sh <nombre> <ip_vpn> <endpoint_ip:puerto>
# Ej:  sudo agregar-peer.sh compa 10.10.0.3 192.168.1.20:51820
set -euo pipefail
[ $# -eq 3 ] || { echo "Uso: $0 <nombre> <ip_vpn> <endpoint_ip:puerto>"; exit 1; }
NOMBRE=$1; IP=$2; ENDPOINT=$3
CONF=/etc/wireguard/wg0.conf
OUT_DIR=/etc/wireguard/clientes

grep -q "AllowedIPs = $IP/32" "$CONF" && { echo "Ya existe un peer con $IP"; exit 1; }

mkdir -p "$OUT_DIR"; chmod 700 "$OUT_DIR"
PRIV=$(wg genkey)
PUB=$(echo "$PRIV" | wg pubkey)
SERVER_PUB=$(cat /etc/wireguard/server.pub)

cat >> "$CONF" << EOF

[Peer]
# $NOMBRE
PublicKey = $PUB
AllowedIPs = $IP/32
EOF
wg set wg0 peer "$PUB" allowed-ips "$IP/32"

umask 077
cat > "$OUT_DIR/$NOMBRE.conf" << EOF
[Interface]
PrivateKey = $PRIV
Address = $IP/32

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $ENDPOINT
AllowedIPs = 10.10.0.0/24
PersistentKeepalive = 25
EOF
echo "Peer '$NOMBRE' agregado ($IP). Config del cliente: $OUT_DIR/$NOMBRE.conf"
