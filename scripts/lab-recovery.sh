#!/usr/bin/env bash
set -euo pipefail
LAB="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=load-secrets.sh
source "$LAB/scripts/load-secrets.sh" 2>/dev/null || true
export SUDO_PASS="${SUDO_PASS:-${HOST_SUDO_PASS:-}}"
log() { echo "[lab-recovery] $*"; }
log "Inicio $(date -Iseconds)"

for i in $(seq 1 60); do
  ip=$(hostname -I | awk '{print $1}')
  [[ "$ip" == 192.168.1.* ]] && break
  sleep 2
done

"$LAB/scripts/fix-incus-ip.sh" || true
for i in $(seq 1 60); do
  systemctl is-active --quiet incus && break
  sleep 2
done

for n in node-control db-postgres app-api app-core monitoring ceph-node; do
  incus start "$n" 2>/dev/null || true
done
sleep 8
"$LAB/scripts/fix-network.sh" 2>/dev/null || true

if ! curl -sf --connect-timeout 10 http://10.10.0.20:8080/health >/dev/null; then
  log "Reiniciando stack reservas"
  "$LAB/start-reservas.sh" 2>/dev/null || true
fi
log "Fin"
