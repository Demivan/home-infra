resource "hcloud_network" "kubernetes" {
  name     = "kubernetes"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "kubernetes" {
  type         = "cloud"
  network_id   = hcloud_network.kubernetes.id
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}
