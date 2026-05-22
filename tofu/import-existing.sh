#!/usr/bin/env bash
# Importa recursos ya creados por lab-deploy.sh al estado de OpenTofu (idempotente).
set -euo pipefail
cd "$(dirname "$0")"
TOFU="${TOFU_BIN:-/snap/bin/tofu}"
IMG="local:ubuntu2404"

[[ -f terraform.tfstate ]] && exit 0

$TOFU init -input=false

$TOFU import incus_network.lab_bridge lab-br0 || true
$TOFU import incus_network.lab_ovn lab-ovn || true
$TOFU import incus_profile.lab lab || true

for n in node-control app-api app-core db-postgres monitoring ceph-node; do
  $TOFU import "incus_instance.nodes[\"${n}\"]" "default/${n},image=${IMG}" 2>/dev/null || \
  $TOFU import "incus_instance.nodes[\"${n}\"]" "default/${n}" 2>/dev/null || true
done

echo "Import completado (o recursos nuevos en próximo apply)."
