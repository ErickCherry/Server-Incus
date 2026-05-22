#!/usr/bin/env bash
# Funciones compartidas del laboratorio Incus
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${LAB_CONFIG:-${LAB_ROOT}/lab.config.yaml}"
GENERATED_DIR="${LAB_ROOT}/generated"

log()  { echo "[lab] $*"; }
warn() { echo "[lab] WARN: $*" >&2; }
die()  { echo "[lab] ERROR: $*" >&2; exit 1; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "Comando requerido no encontrado: $c"
  done
}

require_incus() {
  require_cmd incus python3
  timeout 10 incus list >/dev/null 2>&1 || die "Incus no responde. Revise: systemctl status incus"
}

cfg_get() {
  python3 - "$CONFIG_FILE" "$@" <<'PY'
import sys, yaml
path = sys.argv[1]
keys = sys.argv[2:]
with open(path) as f:
    data = yaml.safe_load(f)
cur = data
for k in keys:
    if isinstance(cur, dict):
        cur = cur.get(k)
    else:
        cur = None
        break
if cur is None:
    sys.exit(1)
if isinstance(cur, (dict, list)):
    import json
    print(json.dumps(cur))
else:
    print(cur)
PY
}

cfg_nodes_enabled() {
  python3 - "$CONFIG_FILE" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
lab = data.get("lab", {})
base = lab.get("network", {}).get("gateway", "10.10.0.1")
parts = base.rsplit(".", 1)
ip_base = parts[0] + ".0" if len(parts) == 2 else "10.10.0.0"

for n in data.get("nodes", []):
    if not n.get("enabled", True):
        continue
    name = n["name"]
    ip = n.get("ip")
    if not ip and "ip_offset" in n:
        ip = f"{ip_base.rsplit('.', 1)[0]}.{n['ip_offset']}" if "ip_base" not in n else f"{n.get('ip_base', ip_base).rsplit('.',1)[0]}.{n['ip_offset']}"
    if not ip:
        sys.stderr.write(f"nodo {name}: falta ip o ip_offset\n")
        sys.exit(1)
    disks = n.get("disks", [])
    disk_str = "|".join(f"{d['name']}:{d['path']}:{d.get('size','5GiB')}" for d in disks)
    print("|".join([
        name,
        n.get("role", "generic"),
        ip,
        str(n.get("cpu", 1)),
        n.get("memory", "1GiB"),
        n.get("disk", "8GiB"),
        disk_str,
    ]))
PY
}

cfg_seed_node() {
  cfg_get lab seed_node 2>/dev/null || echo "node-control"
}

instance_exists() {
  incus info "$1" &>/dev/null
}

network_exists() {
  incus network show "$1" &>/dev/null
}
