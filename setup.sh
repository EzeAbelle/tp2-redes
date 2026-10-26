#!/bin/bash
# setup.sh - Aprovisionamiento automatico del servidor TP2 (idempotente)
# Uso: sudo ./setup.sh
# Variables opcionales: ADMIN_USER, USUARIOS, PUB_IF
set -euo pipefail

ADMIN_USER="${ADMIN_USER:-${SUDO_USER:-eze}}"
USUARIOS="${USUARIOS:-kakashi naruto sakura}"
WG_ADDR="10.10.0.1/24"
WG_PORT=51820
PUB_IF="${PUB_IF:-$(ip route show default | awk '{print $5; exit}')}"
REPO="$(cd "$(dirname "$0")" && pwd)"
ADMIN_KEYS="/home/$ADMIN_USER/.ssh/authorized_keys"

log() { echo -e "\n==> $*"; }

[ "$(id -u)" -eq 0 ] || { echo "Ejecutar con sudo"; exit 1; }
[ -n "$PUB_IF" ] || { echo "No se detecto la interfaz publica"; exit 1; }
[ -s "$ADMIN_KEYS" ] || { echo "Falta $ADMIN_KEYS: copiar la clave publica del admin antes de correr (si no, SSH queda bloqueado)"; exit 1; }

log "1. Paquetes"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q openssh-server wireguard nftables docker.io docker-compose-v2 rsync fail2ban cron git openssl

log "2. SSH (solo claves, grupo sshusers) + fail2ban"
groupadd -f sshusers
usermod -aG sshusers,docker "$ADMIN_USER"
install -m 644 "$REPO/config/00-tp2-hardening.conf" /etc/ssh/sshd_config.d/00-tp2-hardening.conf
sshd -t
systemctl enable ssh fail2ban
systemctl restart ssh
systemctl start fail2ban

log "3. WireGuard"
if [ ! -f /etc/wireguard/wg0.conf ]; then
  umask 077
  wg genkey > /etc/wireguard/server.key
  wg pubkey < /etc/wireguard/server.key > /etc/wireguard/server.pub
  cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = $WG_ADDR
ListenPort = $WG_PORT
PrivateKey = $(cat /etc/wireguard/server.key)
EOF
  umask 022
else
  echo "wg0.conf ya existe, no se modifica"
fi
systemctl enable --now wg-quick@wg0

log "4. Firewall nftables (interfaz publica: $PUB_IF)"
systemctl disable --now ufw 2>/dev/null || true
sed "s/\"enp0s3\"/\"$PUB_IF\"/g" "$REPO/config/nftables.conf" > /etc/nftables.conf
chmod 755 /etc/nftables.conf
mkdir -p /etc/systemd/system/nftables.service.d
install -m 644 "$REPO/config/nftables-override.conf" /etc/systemd/system/nftables.service.d/override.conf
systemctl daemon-reload
nft -c -f /etc/nftables.conf
systemctl enable --now nftables
nft -f /etc/nftables.conf

log "5. Docker (arranca despues de wg0)"
install -m 644 "$REPO/config/99-tp2.conf" /etc/sysctl.d/99-tp2.conf
sysctl --system > /dev/null
mkdir -p /etc/systemd/system/docker.service.d
install -m 644 "$REPO/config/docker-override.conf" /etc/systemd/system/docker.service.d/override.conf
systemctl daemon-reload
systemctl enable --now docker

log "6. Usuarios y public_html"
for u in $USUARIOS; do
  id "$u" > /dev/null 2>&1 || useradd -m -s /bin/bash "$u"
  usermod -aG sshusers "$u"
  chmod 711 "/home/$u"
  install -d -o "$u" -g "$u" -m 755 "/home/$u/public_html"
  install -d -o "$u" -g "$u" -m 700 "/home/$u/.ssh"
  [ -f "/home/$u/.ssh/authorized_keys" ] || install -o "$u" -g "$u" -m 600 "$ADMIN_KEYS" "/home/$u/.ssh/authorized_keys"
  if [ ! -f "/home/$u/public_html/index.html" ]; then
    echo "<!doctype html><html><head><meta charset='utf-8'><title>~$u</title></head><body><h1>Pagina de $u</h1></body></html>" > "/home/$u/public_html/index.html"
    chown "$u:$u" "/home/$u/public_html/index.html"
    chmod 644 "/home/$u/public_html/index.html"
  fi
done
if id kakashi > /dev/null 2>&1; then
  install -d -o kakashi -g kakashi -m 755 /home/kakashi/public_html/privado
  if [ ! -f /home/kakashi/public_html/privado/index.html ]; then
    echo "<h1>Zona privada de kakashi</h1>" > /home/kakashi/public_html/privado/index.html
    chown kakashi:kakashi /home/kakashi/public_html/privado/index.html
  fi
fi

log "7. Servidor web: htpasswd y pagina principal"
mkdir -p "$REPO/docker/web/html"
if [ ! -f "$REPO/docker/web/htpasswd" ]; then
  PASS=$(openssl rand -base64 9)
  printf 'profe:%s\n' "$(openssl passwd -apr1 "$PASS")" > "$REPO/docker/web/htpasswd"
  echo "Usuario HTTP basico: profe / contrasena: $PASS (anotala)"
fi
chmod 644 "$REPO/docker/web/htpasswd"
bash "$REPO/scripts/generar-index.sh"

log "8. Backups y tareas cron"
install -m 750 "$REPO/scripts/tp2-backup.sh" /usr/local/sbin/tp2-backup.sh
install -m 750 "$REPO/scripts/tp2-restore.sh" /usr/local/sbin/tp2-restore.sh
echo "0 * * * * root /usr/local/sbin/tp2-backup.sh" > /etc/cron.d/tp2-backup
echo "*/10 * * * * root $REPO/scripts/generar-index.sh" > /etc/cron.d/tp2-index
chmod 644 /etc/cron.d/tp2-backup /etc/cron.d/tp2-index
systemctl enable --now cron

log "9. Contenedores"
cd "$REPO/docker"
docker compose up -d
docker compose ps

log "Listo"
echo "Clave publica WireGuard del servidor: $(cat /etc/wireguard/server.pub)"
echo "Agregar cliente VPN: sudo $REPO/scripts/agregar-peer.sh <nombre> <ip_vpn> <endpoint_ip:puerto>"
