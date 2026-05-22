#!/usr/bin/env bash
set -euo pipefail
echo "=== lab-br0 (bridge + OVN ranges) ==="
incus network show lab-br0 | grep -E "name|ipv4" || true
echo "=== lab-ovn ==="
incus network show lab-ovn
incus config device add node-control ovn-demo nic network=lab-ovn name=ovn0 2>/dev/null || true
echo "OVN validado."
