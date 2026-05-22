resource "incus_network" "lab_bridge" {
  name = local.bridge_name
  type = "bridge"

  config = {
    "ipv4.address"     = "${local.gateway}/24"
    "ipv4.nat"         = "true"
    "ipv4.dhcp.ranges" = local.lab.network.dhcp_dynamic
    "ipv4.ovn.ranges"  = local.lab.network.ovn_ranges
  }
}

resource "incus_network" "lab_ovn" {
  depends_on = [incus_network.lab_bridge]

  name = local.ovn_name
  type = "ovn"

  config = {
    network = incus_network.lab_bridge.name
  }
}
