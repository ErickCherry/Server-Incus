#!/usr/bin/env bash
# Parte 2: OpenTofu (IaC) + Ansible (configuración) + validación monitoreo
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "$0")" && pwd)"
TOFU="${TOFU_BIN:-/snap/bin/tofu}"
export LAB_CONFIG="${LAB_CONFIG:-${LAB_ROOT}/lab.config.yaml}"
export ANSIBLE_CONFIG="${LAB_ROOT}/ansible/ansible.cfg"

log() { echo "[phase2] $*"; }
die() { echo "[phase2] ERROR: $*" >&2; exit 1; }

require_tools() {
  command -v incus >/dev/null || die "incus no instalado"
  command -v ansible >/dev/null || die "ansible no instalado — sudo apt install ansible"
  command -v "$TOFU" >/dev/null || die "OpenTofu no instalado — sudo snap install opentofu --classic"
}

step_inventory() {
  log "Generando inventario Ansible (conexión LXC)"
  chmod +x "${LAB_ROOT}/scripts/gen-inventory.sh"
  "${LAB_ROOT}/scripts/gen-inventory.sh"
}

step_tofu() {
  log "OpenTofu: red, perfil, OVN e instancias"
  cd "${LAB_ROOT}/tofu"
  $TOFU init -input=false
  chmod +x import-existing.sh
  ./import-existing.sh || true
  $TOFU apply -auto-approve -compact-warnings
  $TOFU output -json instances 2>/dev/null | python3 -m json.tool || true
}

step_network_fix() {
  log "Red: UFW forward + DNS en nodos"
  chmod +x "${LAB_ROOT}/scripts/fix-network.sh"
  "${LAB_ROOT}/scripts/fix-network.sh"
}

step_ansible() {
  step_network_fix
  log "Ansible: dependencias y colecciones"
  ansible-galaxy collection install -r "${LAB_ROOT}/ansible/requirements.yml" --force-with-deps 2>/dev/null || \
    ansible-galaxy collection install community.general

  cd "${LAB_ROOT}/ansible"
  log "Bootstrap SSH (secuencial)"
  "${LAB_ROOT}/scripts/bootstrap-ssh.sh"
  log "Despliegue de servicios (site.yml)"
  ansible-playbook playbooks/site.yml -i "${LAB_ROOT}/generated/inventory.ini"
}

step_validate() {
  log "Validación final"
  cd "${LAB_ROOT}/ansible"
  ansible-playbook playbooks/site.yml -i "${LAB_ROOT}/generated/inventory.ini" --tags validate
  incus list
}

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
  local cmd="${1:-all}"
  require_tools
  case "$cmd" in
    all)
      step_inventory
      step_tofu
      step_ansible
      step_validate
      ;;
    tofu)    step_inventory; step_tofu ;;
    ansible) step_inventory; step_ansible ;;
    validate) step_inventory; step_validate ;;
    inventory) step_inventory; cat "${LAB_ROOT}/generated/inventory.ini" ;;
    help|-h) usage ;;
    *) die "Comando: all | tofu | ansible | validate | inventory" ;;
  esac
  log "Fase 2 completada."
}

main "$@"
