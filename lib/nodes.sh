#!/usr/bin/env bash
# Gestión declarativa de nodos (crear / quitar / aplicar)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

GW="${LAB_GATEWAY:-$(cfg_get lab network gateway)}"
PROFILE="${LAB_PROFILE:-$(cfg_get lab profile)}"
IMAGE="${LAB_IMAGE:-$(cfg_get lab image_alias)}"

apply_netplan() {
  local name="$1" ip="$2"
  incus exec "$name" -- bash -c "
    cat > /etc/netplan/50-lab.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      addresses: [${ip}/24]
      routes:
        - to: default
          via: ${GW}
      nameservers:
        addresses: [${GW}, 8.8.8.8]
EOF
    chmod 600 /etc/netplan/50-lab.yaml
    hostnamectl set-hostname ${name} 2>/dev/null || echo ${name} > /etc/hostname
    netplan apply
  " 2>/dev/null || warn "netplan en $name puede requerir reinicio"
}

set_node_ip_config() {
  local name="$1" ip="$2"
  if incus config device show "$name" 2>/dev/null | grep -q '^eth0:'; then
    incus config device unset "$name" eth0 ipv4.address 2>/dev/null || true
    incus config device set "$name" eth0 ipv4.address="$ip" 2>/dev/null || true
  fi
}

attach_disks() {
  local name="$1" disks="$2"
  [[ -z "$disks" ]] && return 0
  local IFS='|'
  for entry in $disks; do
    [[ -z "$entry" ]] && continue
    local dname path size
    dname="${entry%%:*}"
    path="${entry#*:}"; path="${path%%:*}"
    size="${entry##*:}"
    if incus config device show "$name" 2>/dev/null | grep -q "^${dname}:"; then
      continue
    fi
    log "Disco $dname en $name -> $path ($size)"
    incus config device add "$name" "$dname" disk pool="$(cfg_get lab storage_pool)" \
      path="$path" size="$size" 2>/dev/null || warn "No se pudo adjuntar disco $dname en $name"
  done
}

create_from_image() {
  local name="$1" cpu="$2" mem="$3"
  log "Creando $name desde imagen (semilla)"
  incus init "local:${IMAGE}" "$name" \
    --profile "$PROFILE" \
    -c "limits.cpu=${cpu}" \
    -c "limits.memory=${mem}"
}

create_from_seed() {
  local name="$1" seed="$2" cpu="$3" mem="$4"
  log "Clonando $name desde $seed"
  incus copy "$seed" "$name" --instance-only
  incus stop "$name" --force 2>/dev/null || true
  incus config set "$name" limits.cpu="$cpu" 2>/dev/null || true
  incus config set "$name" limits.memory="$mem" 2>/dev/null || true
}

ensure_node() {
  local name role ip cpu mem disk disks
  name="$1"; role="$2"; ip="$3"; cpu="$4"; mem="$5"; disk="$6"; disks="${7:-}"

  if instance_exists "$name"; then
    log "Nodo '$name' ya existe — actualizando red"
    set_node_ip_config "$name" "$ip"
    attach_disks "$name" "$disks"
    incus start "$name" 2>/dev/null || true
    apply_netplan "$name" "$ip"
    return 0
  fi

  local seed
  seed="$(cfg_seed_node)"

  if [[ "$name" == "$seed" ]]; then
    create_from_image "$name" "$cpu" "$mem"
  elif instance_exists "$seed"; then
    create_from_seed "$name" "$seed" "$cpu" "$mem"
  else
    create_from_image "$name" "$cpu" "$mem"
  fi

  set_node_ip_config "$name" "$ip"
  attach_disks "$name" "$disks"
  incus start "$name"
  sleep 2
  apply_netplan "$name" "$ip"
  log "Nodo '$name' ($role) listo en $ip"
}

remove_node() {
  local name="$1"
  if ! instance_exists "$name"; then
    warn "Nodo '$name' no existe"
    return 0
  fi
  log "Eliminando nodo '$name'"
  incus stop "$name" --force 2>/dev/null || true
  incus delete "$name" --force
}

apply_all_nodes() {
  local filter="${1:-}"
  local seed_created=false
  local seed
  seed="$(cfg_seed_node)"

  while IFS='|' read -r name role ip cpu mem disk disks; do
    [[ -z "$name" ]] && continue
    if [[ -n "$filter" && "$name" != "$filter" ]]; then
      continue
    fi
    if [[ "$name" == "$seed" ]]; then
      ensure_node "$name" "$role" "$ip" "$cpu" "$mem" "$disk" "$disks"
      seed_created=true
    fi
  done < <(cfg_nodes_enabled)

  while IFS='|' read -r name role ip cpu mem disk disks; do
    [[ -z "$name" ]] && continue
    [[ -n "$filter" && "$name" != "$filter" ]] && continue
    [[ "$name" == "$seed" ]] && continue
    if [[ "$seed_created" == false ]] && ! instance_exists "$seed"; then
      die "Semilla '$seed' no existe. Cree primero el nodo semilla."
    fi
    ensure_node "$name" "$role" "$ip" "$cpu" "$mem" "$disk" "$disks"
  done < <(cfg_nodes_enabled)
}

stop_all_nodes() {
  while IFS='|' read -r name _ _ _ _ _ _; do
    [[ -z "$name" ]] && continue
    instance_exists "$name" && incus stop "$name" --force 2>/dev/null || true
  done < <(cfg_nodes_enabled)
}

start_all_nodes() {
  while IFS='|' read -r name _ _ _ _ _ _; do
    [[ -z "$name" ]] && continue
    instance_exists "$name" && incus start "$name" 2>/dev/null || true
  done < <(cfg_nodes_enabled)
}

list_status() {
  incus list
}

generate_ansible_inventory() {
  mkdir -p "$GENERATED_DIR"
  local out="$GENERATED_DIR/inventory.ini"
  local ctrl_ip
  ctrl_ip="$(cfg_get lab network gateway)"
  seed="$(cfg_seed_node)"

  {
    echo "[all]"
    while IFS='|' read -r name role ip _ _ _ _; do
      [[ -z "$name" ]] && continue
      echo "${name} ansible_host=${ip} lab_role=${role}"
    done < <(cfg_nodes_enabled)
    echo ""
    echo "[control]"
    while IFS='|' read -r name role ip _ _ _ _; do
      [[ "$role" == "control" ]] && echo "$name ansible_host=$ip"
    done < <(cfg_nodes_enabled)
    echo ""
    echo "[apps]"
    while IFS='|' read -r name role ip _ _ _ _; do
      [[ "$role" == "api" || "$role" == "core" || "$role" == "worker" ]] && echo "$name ansible_host=$ip"
    done < <(cfg_nodes_enabled)
    echo ""
    echo "[data]"
    while IFS='|' read -r name role ip _ _ _ _; do
      [[ "$role" == "database" || "$role" == "storage" ]] && echo "$name ansible_host=$ip"
    done < <(cfg_nodes_enabled)
    echo ""
    echo "[monitoring]"
    while IFS='|' read -r name role ip _ _ _ _; do
      [[ "$role" == "monitoring" ]] && echo "$name ansible_host=$ip"
    done < <(cfg_nodes_enabled)
  } > "$out"
  log "Inventario Ansible: $out"
}

prune_disabled_nodes() {
  python3 - "$CONFIG_FILE" <<'PY'
import sys, yaml, subprocess
cfg_path = sys.argv[1]
with open(cfg_path) as f:
    data = yaml.safe_load(f)
enabled = {n["name"] for n in data.get("nodes", []) if n.get("enabled", True)}
try:
    out = subprocess.check_output(["incus", "list", "--format", "csv"], text=True)
except Exception:
    sys.exit(0)
for line in out.strip().splitlines():
    if not line:
        continue
    name = line.split(",")[0].strip('"')
    if name in enabled:
        continue
    # solo eliminar contenedores que parecen del lab (prefijos conocidos)
    prefixes = ("node-", "app-", "db-", "monitoring", "ceph-")
    if not any(name.startswith(p) for p in prefixes):
        continue
    print(name)
PY
}
