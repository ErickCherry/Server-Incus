output "network_bridge" {
  value = incus_network.lab_bridge.name
}

output "network_ovn" {
  value = incus_network.lab_ovn.name
}

output "profile" {
  value = incus_profile.lab.name
}

output "instances" {
  value = {
    for k, v in incus_instance.nodes : k => {
      ipv4   = v.ipv4_address
      status = v.status
      role   = local.nodes[k].role
    }
  }
}
