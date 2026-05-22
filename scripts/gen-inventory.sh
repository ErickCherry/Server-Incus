#!/usr/bin/env bash
set -euo pipefail
LAB_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${LAB_ROOT}/generated/inventory.ini"
python3 - "$LAB_ROOT/lab.config.yaml" "$OUT" <<'PY'
import os, sys, yaml
cfg_path, out_path = sys.argv[1], sys.argv[2]
lab_pass = os.environ.get("LAB_SSH_PASS", "lab123")
import os
with open(cfg_path) as f:
    data = yaml.safe_load(f)

lines = ["# Generado por scripts/gen-inventory.sh", "[all]"]
hosts = []
for n in data.get("nodes", []):
    if not n.get("enabled", True):
        continue
    name, ip, role = n["name"], n["ip"], n.get("role", "generic")
    lines.append(
        f"{name} ansible_host={ip} lab_ip={ip} lab_role={role} "
        f"ansible_user=ubuntu ansible_ssh_pass={lab_pass} "
        f"ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
    )
    hosts.append((name, ip, role))

lines.append("\n[control]")
lines += [n for n, _, r in hosts if r == "control"]
lines.append("\n[apps]")
lines += [n for n, _, r in hosts if r in ("api", "core", "worker")]
lines.append("\n[data]")
lines += [n for n, _, r in hosts if r in ("database", "storage")]
lines.append("\n[monitoring]")
lines += [n for n, _, r in hosts if r == "monitoring"]
lines.append("\n[db_postgres]")
lines += [n for n, _, r in hosts if r == "database"]
lines.append("\n[ceph_node]")
lines += [n for n, _, r in hosts if r == "storage"]

open(out_path, "w").write("\n".join(lines) + "\n")
print(out_path)
PY
