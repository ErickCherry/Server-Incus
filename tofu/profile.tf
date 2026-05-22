resource "incus_profile" "lab" {
  name = local.profile

  device {
    name = "root"
    type = "disk"

    properties = {
      pool = local.pool
      path = "/"
      size = "8GiB"
    }
  }

  device {
    name = "eth0"
    type = "nic"

    properties = {
      network = incus_network.lab_bridge.name
      name    = "eth0"
    }
  }
}
