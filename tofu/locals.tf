locals {
  cfg = yamldecode(file("${path.module}/../lab.config.yaml"))
  lab = local.cfg.lab

  bridge_name = local.lab.network.bridge
  gateway     = local.lab.network.gateway
  ovn_name    = local.lab.network.ovn_network
  ovn_parent  = local.lab.network.ovn_parent
  pool        = local.lab.storage_pool
  profile     = local.lab.profile
  image       = local.lab.image_alias

  nodes = {
    for n in local.cfg.nodes : n.name => n
    if lookup(n, "enabled", true)
  }

  seed_node = local.lab.seed_node
}
