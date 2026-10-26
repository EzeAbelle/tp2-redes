#!/bin/bash
# Genera la página principal con enlaces a los public_html de cada usuario
set -e
DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$DIR/docker/web/html/index.html"
mkdir -p "$(dirname "$OUT")"
{
  echo "<!doctype html><html><head><meta charset='utf-8'><title>Servidor TP2</title></head><body>"
  echo "<h1>Servidor TP2 - Administración de Sistemas y Redes</h1>"
  echo "<h2>Directorios públicos de usuarios</h2><ul>"
  for d in /home/*/public_html; do
    [ -d "$d" ] || continue
    u=$(basename "$(dirname "$d")")
    echo "  <li><a href=\"/~$u/\">~$u</a></li>"
  done
  echo "</ul><p>Generado: $(date '+%d/%m/%Y %H:%M')</p></body></html>"
} > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
chmod 644 "$OUT"
