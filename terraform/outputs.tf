output "network_id" {
  value = hcloud_network.kubernetes.id
}

output "server_ipv4" {
  value = hcloud_server.controlplane.ipv4_address
}

output "server_ipv6" {
  value = hcloud_server.controlplane.ipv6_address
}

output "volume_id" {
  value = hcloud_volume.data.id
}

output "volume_linux_device" {
  value = hcloud_volume.data.linux_device
}
