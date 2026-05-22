#!/usr/bin/env bash
set -euo pipefail
LAB="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=load-secrets.sh
source "$LAB/scripts/load-secrets.sh" 2>/dev/null || true
SUDO_PASS="${SUDO_PASS:-${HOST_SUDO_PASS:-}}"
sudo_cmd() {
  [[ -n "$SUDO_PASS" ]] && echo "$SUDO_PASS" | sudo -S "$@" || sudo "$@"
}
current=$(hostname -I | awk '{print $1}')
[[ -z "$current" ]] && exit 0
bound=$(sudo_cmd sqlite3 /var/lib/incus/database/local.db "SELECT value FROM config WHERE key='core.https_address';" 2>/dev/null || true)
if [[ -n "$bound" && "$bound" != *"$current"* ]]; then
  echo "[fix-incus-ip] $bound -> ${current}:8443"
  sudo_cmd sqlite3 /var/lib/incus/database/local.db \
    "UPDATE config SET value='${current}:8443' WHERE key IN ('core.https_address','cluster.https_address');"
  sudo_cmd systemctl restart incus
  for i in $(seq 1 30); do
    systemctl is-active --quiet incus && break
    sleep 2
  done
fi
