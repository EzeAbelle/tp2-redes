#!/bin/bash
# Restaura un archivo o carpeta de un usuario desde el backup
# Uso: sudo tp2-restore.sh <usuario> <ruta relativa a su home> [snapshot]
# Ej:  sudo tp2-restore.sh kakashi public_html/naruto-run.jpg
set -euo pipefail
[ $# -ge 2 ] || { echo "Uso: $0 <usuario> <ruta> [snapshot]"; ls -1 /var/backups/home; exit 1; }
U=$1; F=$2; SNAP=${3:-latest}
SRC="/var/backups/home/$SNAP/$U/$F"
DST="/home/$U/$F"
[ -e "$SRC" ] || { echo "No existe en el backup: $SRC"; exit 1; }
if [ -d "$SRC" ]; then
  rsync -aAX "$SRC/" "$DST/"
else
  rsync -aAX "$SRC" "$DST"
fi
echo "Restaurado: $DST (desde $SNAP)"
