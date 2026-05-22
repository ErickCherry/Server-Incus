#!/usr/bin/env bash
# Despliegue completo del laboratorio (suficiente para demo académica)
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=scripts/load-secrets.sh
source "$(dirname "$0")/scripts/load-secrets.sh"
: "${DB_PASS:?Define DB_PASS en secrets/lab.secrets.env}"
: "${LAB_SSH_PASS:?Define LAB_SSH_PASS en secrets/lab.secrets.env}"
export DB_PASS LAB_SSH_PASS
export SUDO_PASS="${SUDO_PASS:-$HOST_SUDO_PASS}"

echo "=== 1/7 Incus IP + contenedores ==="
chmod +x scripts/fix-incus-ip.sh scripts/ovn-demo.sh scripts/smoke-test.sh start-reservas.sh
./scripts/fix-incus-ip.sh
./lab-deploy.sh apply
for n in app-api app-core db-postgres monitoring node-control ceph-node; do
  incus start "$n" 2>/dev/null || true
done
./scripts/fix-network.sh 2>/dev/null || true

echo "=== 2/7 OpenTofu (idempotente) ==="
./deploy-phase2.sh tofu || true

echo "=== 3/7 Bootstrap SSH ==="
./scripts/gen-inventory.sh
./scripts/bootstrap-ssh.sh

echo "=== 4/7 Ansible ==="
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
mkdir -p ansible/playbooks/group_vars
cp -f ansible/group_vars/all.yml ansible/playbooks/group_vars/all.yml
cd ansible
ansible-playbook -i ../generated/inventory.ini playbooks/site.yml --limit 'app-api,app-core,db-postgres,monitoring,ceph-node'
cd ..

echo "=== 5/7 OVN demo ==="
./scripts/ovn-demo.sh

echo "=== 6/7 Smoke test ==="
./scripts/smoke-test.sh

echo "=== 7/7 Listo ==="
incus list
