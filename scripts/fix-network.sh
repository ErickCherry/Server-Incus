#!/usr/bin/env bash
# Corrige DNS/NAT del laboratorio (UFW + netplan en nodos)
set -euo pipefail
LAB_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=load-secrets.sh
source "$(dirname "$0")/load-secrets.sh"
: "${HOST_SUDO_PASS:?Defina HOST_SUDO_PASS en secrets/lab.secrets.env}"
SUDO_PASS="${SUDO_PASS:-$HOST_SUDO_PASS}"

echo "[network] Reglas UFW para lab-br0"
echo "$SUDO_PASS" | sudo -S ufw route allow in on lab-br0 out on enp2s0 2>/dev/null || true
echo "$SUDO_PASS" | sudo -S ufw route allow in on enp2s0 out on lab-br0 2>/dev/null || true
echo "$SUDO_PASS" | sudo -S ip link set lab-br0 up 2>/dev/null || true

while IFS=: read -r n ip; do
  [[ -z "$n" ]] && continue
  incus exec "$n" -- bash -c "cat > /etc/netplan/50-lab.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      addresses: [${ip}/24]
      routes:
        - to: default
          via: 10.10.0.1
      nameservers:
        addresses: [10.10.0.1, 8.8.8.8]
EOF
netplan apply" 2>/dev/null || true
done < <(python3 - "$LAB_ROOT/lab.config.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    for n in yaml.safe_load(f).get("nodes", []):
        if n.get("enabled", True):
            print(f"{n['name']}:{n['ip']}")
PY
)
echo "[network] Listo."
