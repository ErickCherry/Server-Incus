#!/usr/bin/env bash
# Red del laboratorio (bridge + OVN)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ensure_ovn_host() {
  require_cmd ovs-vsctl
  if ! systemctl is-active --quiet openvswitch-switch 2>/dev/null; then
    warn "openvswitch-switch no activo; instale: sudo apt install openvswitch-switch ovn-central ovn-host"
    return 0
  fi
  echo '0101' | sudo -S ovs-vsctl set open_vswitch . \
    external_ids:ovn-remote=unix:/run/ovn/ovnsb_db.sock \
    external_ids:ovn-encap-type=geneve \
    external_ids:ovn-encap-ip=127.0.0.1 2>/dev/null || true
  incus config set network.ovn.northbound_connection unix:/var/run/ovn/ovnnb_db.sock 2>/dev/null || true
}

ensure_bridge() {
  local br gw dhcp ovn_rng nat
  br="$(cfg_get lab network bridge)"
  gw="$(cfg_get lab network gateway)"
  dhcp="$(cfg_get lab network dhcp_dynamic)"
  ovn_rng="$(cfg_get lab network ovn_ranges)"
  nat="$(cfg_get lab network nat)"

  if network_exists "$br"; then
    log "Red bridge '$br' ya existe"
  else
    log "Creando bridge '$br' ($gw/24)"
    incus network create "$br" \
      ipv4.address="${gw}/24" \
      ipv4.nat="$nat" \
      ipv4.dhcp.ranges="$dhcp"
  fi

  incus network set "$br" ipv4.dhcp.ranges="$dhcp" 2>/dev/null || true
  incus network set "$br" ipv4.ovn.ranges="$ovn_rng" 2>/dev/null || true
  echo '0101' | sudo -S ip link set "$br" up 2>/dev/null || true
}

ensure_ovn_network() {
  local ovn parent gw
  ovn="$(cfg_get lab network ovn_network)"
  parent="$(cfg_get lab network ovn_parent)"
  gw="$(cfg_get lab network gateway)"

  ensure_ovn_host
  ensure_bridge

  if network_exists "$ovn"; then
    log "Red OVN '$ovn' ya existe"
    return 0
  fi

  log "Creando red OVN '$ovn' (uplink: $parent)"
  timeout 180 incus network create "$ovn" --type=ovn network="$parent" || {
    warn "OVN '$ovn' no creada en 180s; el laboratorio puede usar solo '$parent'"
    return 0
  }
}

ensure_profile() {
  local profile pool br disk
  profile="$(cfg_get lab profile)"
  pool="$(cfg_get lab storage_pool)"
  br="$(cfg_get lab network bridge)"
  disk="8GiB"

  if ! incus profile show "$profile" &>/dev/null; then
    log "Creando perfil '$profile'"
    incus profile create "$profile"
  fi

  if ! incus profile device show "$profile" 2>/dev/null | grep -q '^root:'; then
    incus profile device add "$profile" root disk path=/ pool="$pool" size="$disk" 2>/dev/null || \
      incus profile device set "$profile" root pool="$pool" path=/ size="$disk" 2>/dev/null || true
  fi

  if ! incus profile device show "$profile" 2>/dev/null | grep -q '^eth0:'; then
    incus profile device add "$profile" eth0 nic network="$br" name=eth0 2>/dev/null || true
  else
    incus profile device set "$profile" eth0 network="$br" 2>/dev/null || true
  fi
}

ensure_image() {
  local alias remote
  alias="$(cfg_get lab image_alias)"
  remote="$(cfg_get lab image_remote)"

  if incus image list --format csv | awk -F, '{print $1}' | grep -qx "$alias"; then
    log "Imagen local '$alias' disponible"
    return 0
  fi
  log "Descargando imagen images:${remote} -> local:${alias}"
  incus image copy "images:${remote}" "local:" --alias "$alias"
}

setup_network_stack() {
  require_incus
  ensure_image
  ensure_bridge
  ensure_ovn_network
  ensure_profile
  log "Stack de red y perfil listo"
}
