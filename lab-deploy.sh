#!/usr/bin/env bash
# Despliegue declarativo del laboratorio Incus (sin intervención manual).
#
# Uso:
#   ./lab-deploy.sh apply          # Red + perfil + todos los nodos enabled
#   ./lab-deploy.sh apply <nodo>   # Solo un nodo (añadir/actualizar)
#   ./lab-deploy.sh remove <nodo>  # Eliminar un contenedor
#   ./lab-deploy.sh prune          # Quitar contenedores no listados/enabled en config
#   ./lab-deploy.sh stop|start     # Parar o arrancar todos los nodos enabled
#   ./lab-deploy.sh status         # Estado Incus
#   ./lab-deploy.sh inventory      # Generar Ansible inventory
#   ./lab-deploy.sh destroy        # Eliminar TODOS los nodos del config (no borra redes)
#
# Variables:
#   LAB_CONFIG=/ruta/lab.config.yaml
#   LAB_SKIP_OVN=1                 # Omitir creación OVN si tarda/falla
#
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "$0")" && pwd)"
export LAB_CONFIG="${LAB_CONFIG:-${LAB_ROOT}/lab.config.yaml}"

source "${LAB_ROOT}/lib/common.sh"
source "${LAB_ROOT}/lib/network.sh"
source "${LAB_ROOT}/lib/nodes.sh"

usage() {
  sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

cmd_apply() {
  local target="${1:-}"
  require_incus
  setup_network_stack
  apply_all_nodes "$target"
  generate_ansible_inventory
  log "Apply completado."
  list_status
}

cmd_remove() {
  local name="${1:-}"
  [[ -z "$name" ]] && die "Uso: $0 remove <nombre-nodo>"
  require_incus
  remove_node "$name"
  generate_ansible_inventory
}

cmd_prune() {
  require_incus
  local n
  while read -r n; do
    [[ -z "$n" ]] && continue
    log "Prune: eliminando '$n' (no está enabled en config)"
    remove_node "$n"
  done < <(prune_disabled_nodes || true)
  generate_ansible_inventory
}

cmd_destroy() {
  require_incus
  while IFS='|' read -r name _ _ _ _ _ _; do
    [[ -z "$name" ]] && continue
    remove_node "$name" || true
  done < <(cfg_nodes_enabled)
  # También nodos deshabilitados que aún existan
  cmd_prune
  log "Nodos destruidos. Redes y perfil se conservan."
}

cmd_stop() { require_incus; stop_all_nodes; list_status; }
cmd_start() { require_incus; start_all_nodes; list_status; }
cmd_status() { require_incus; list_status; }
cmd_inventory() { generate_ansible_inventory; cat "${GENERATED_DIR}/inventory.ini"; }

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    apply)    cmd_apply "$@";;
    remove)   cmd_remove "$@";;
    prune)    cmd_prune;;
    destroy)  cmd_destroy;;
    stop)     cmd_stop;;
    start)    cmd_start;;
    status)   cmd_status;;
    inventory) cmd_inventory;;
    -h|--help|help|"") usage 0;;
    *) die "Comando desconocido: $cmd. Use: $0 help";;
  esac
}

main "$@"
