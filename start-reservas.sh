#!/usr/bin/env bash
# Arranca stack mínimo y despliega app de reservas académicas
set -euo pipefail
cd "$(dirname "$0")"
export SUDO_PASS="${SUDO_PASS:-0101}"

fix_incus_ip_if_needed() {
  local current
  current=$(hostname -I | awk "{print \$1}")
  local bound
  bound=$(sudo sqlite3 /var/lib/incus/database/local.db \
    "SELECT value FROM config WHERE key='core.https_address';" 2>/dev/null || true)
  if [[ -n "$current" && -n "$bound" && "$bound" != *"$current"* ]]; then
    echo "[start] Ajustando Incus https_address a ${current}:8443"
    sudo sqlite3 /var/lib/incus/database/local.db \
      "UPDATE config SET value='${current}:8443' WHERE key IN ('core.https_address','cluster.https_address');"
    sudo systemctl restart incus
    sleep 3
  fi
}

echo "[start] Lab reservas académicas — stack mínimo"
fix_incus_ip_if_needed
./lab-deploy.sh apply 2>/dev/null || true
for n in app-api app-core db-postgres monitoring; do
  incus start "$n" 2>/dev/null || true
done
./scripts/deploy-reservas-app.sh
