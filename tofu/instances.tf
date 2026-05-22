resource "incus_instance" "nodes" {
  for_each = local.nodes

  name     = each.key
  image    = "local:${local.image}"
  profiles = [incus_profile.lab.name]
  running  = true

  config = {
    "limits.cpu"            = tostring(each.value.cpu)
    "limits.memory"         = each.value.memory
    "user.hostname"         = each.key
    "user.access_interface" = "eth0"
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      network        = incus_network.lab_bridge.name
      name           = "eth0"
      "ipv4.address" = each.value.ip
    }
  }

  dynamic "device" {
    for_each = lookup(each.value, "disks", [])
    content {
      name = device.value.name
      type = "disk"
      properties = {
        pool = local.pool
        path = device.value.path
        size = lookup(device.value, "size", "5GiB")
      }
    }
  }

  file {
    content = templatefile("${path.module}/netplan.yaml.tftpl", {
      ip      = each.value.ip
      gateway = local.gateway
    })
    target_path        = "/etc/netplan/50-lab-tofu.yaml"
    mode               = "0600"
    create_directories = false
  }

  exec = {
    "netplan-apply" = {
      command = ["netplan", "apply"]
      trigger = "on_change"
    }
    "openssh" = {
      command = ["bash", "-c", "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server python3 sudo && systemctl enable --now ssh"]
      timeout = "10m"
      trigger = "once"
    }
  }

  wait_for {
    type = "ipv4"
    nic  = "eth0"
  }
}
