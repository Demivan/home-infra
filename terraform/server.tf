resource "hcloud_server" "controlplane" {
  name        = "k8s-cp-1"
  server_type = var.server_type
  location    = var.location
  image       = var.talos_image_id

  firewall_ids = [hcloud_firewall.kubernetes.id]

  network {
    network_id = hcloud_network.kubernetes.id
    ip         = "10.0.1.10"
  }

  labels = {
    role = "controlplane"
  }

  lifecycle {
    ignore_changes = [
      # Talos manages the OS, ignore image changes after creation
      image,
    ]
  }
}

resource "hcloud_volume" "data" {
  name     = "k8s-data"
  size     = 30
  location = var.location
  format   = "ext4"
}

resource "hcloud_volume_attachment" "data" {
  volume_id = hcloud_volume.data.id
  server_id = hcloud_server.controlplane.id
  automount = false
}
