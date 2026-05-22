#!/usr/bin/env bash
set -euo pipefail
LAB_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAB_PASS="${LAB_SSH_PASS:-lab123}"

while IFS=: read -r n ip; do
  [[ -z "$n" ]] && continue
  echo "[bootstrap] $n ($ip)"
  incus exec "$n" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq openssh-server python3 sudo
    echo 'ubuntu:${LAB_PASS}' | chpasswd
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    systemctl enable --now ssh
  "
  sshpass -p "${LAB_PASS}" ssh -o StrictHostKeyChecking=no ubuntu@"${ip}" echo "SSH OK $n"
done < <(python3 - "$LAB_ROOT/lab.config.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    for n in yaml.safe_load(f).get("nodes", []):
        if n.get("enabled", True):
            print(f"{n['name']}:{n['ip']}")
PY
)
echo "[bootstrap] Completado."
