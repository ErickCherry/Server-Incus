#!/usr/bin/env bash
set -euo pipefail
current=$(hostname -I | awk '{print $1}')
bound=$(sudo sqlite3 /var/lib/incus/database/local.db "SELECT value FROM config WHERE key='core.https_address';" 2>/dev/null || true)
if [[ -n "$current" && -n "$bound" && "$bound" != *"$current"* ]]; then
  echo "[fix-incus-ip] $bound -> ${current}:8443"
  sudo sqlite3 /var/lib/incus/database/local.db \
    "UPDATE config SET value='${current}:8443' WHERE key IN ('core.https_address','cluster.https_address');"
  sudo systemctl restart incus
  sleep 3
fi
