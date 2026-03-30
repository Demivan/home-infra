output "server_ipv4" {
  value = module.talos.public_ipv4_list[0]
}

output "network_id" {
  value = module.talos.hetzner_network_id
}

output "talosconfig" {
  value     = module.talos.talosconfig
  sensitive = true
}

output "kubeconfig" {
  value     = module.talos.kubeconfig
  sensitive = true
}

output "storagebox_server" {
  value = hcloud_storage_box.data.server
}

output "storagebox_username" {
  value = hcloud_storage_box.data.username
}
