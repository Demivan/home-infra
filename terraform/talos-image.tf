resource "talos_image_factory_schematic" "this" {
  schematic = jsonencode({
    customization = {
      systemExtensions = {
        officialExtensions = [
          "siderolabs/qemu-guest-agent",
          "siderolabs/nfs-utils",
          "siderolabs/iscsi-tools",
        ]
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "hcloud"
  architecture  = "amd64"
}

resource "imager_image" "talos" {
  image_url    = data.talos_image_factory_urls.this.urls.disk_image
  architecture = "x86"
  location     = var.location
}
