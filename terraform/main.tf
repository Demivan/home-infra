terraform {
  cloud {
    hostname     = "app.terraform.io"
    organization = "demivan"
    workspaces {
      name = "infra"
    }
  }

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.60"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.7"
    }
    imager = {
      source  = "hcloud-talos/imager"
      version = "~> 0.1"
    }
    infisical = {
      source  = "Infisical/infisical"
      version = "~> 0.16"
    }
  }
}

# Auth via INFISICAL_UNIVERSAL_AUTH_CLIENT_ID / INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET env vars
provider "infisical" {}

data "infisical_secrets" "main" {
  env_slug     = "prod"
  workspace_id = "d17420b0-619f-4c69-a409-59bf89441439"
  folder_path  = "/"
}

locals {
  hcloud_token        = data.infisical_secrets.main.secrets["hcloud-token"].value
  storagebox_password = data.infisical_secrets.main.secrets["storagebox-password"].value
}

provider "hcloud" {
  token = local.hcloud_token
}

provider "imager" {
  token = local.hcloud_token
}

module "talos" {
  source  = "hcloud-talos/talos/hcloud"
  version = "~> 3.0"

  hcloud_token = local.hcloud_token
  cluster_name = "homelab"

  # Hetzner
  location_name            = var.location
  disable_arm              = true
  kubeconfig_endpoint_mode = "public_ip"

  # Versions
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  # Custom Talos image with extensions
  talos_image_id_x86 = imager_image.talos.image_id

  # Single control plane node, workloads scheduled on it
  control_plane_nodes = [
    { id = 1, type = var.server_type }
  ]

  # Firewall: open Talos/K8s API for bootstrap (tighten to Tailscale in Plan 2)
  # firewall_use_current_ip doesn't work with remote HCP Terraform runners
  firewall_kube_api_source  = ["0.0.0.0/0", "::/0"]
  firewall_talos_api_source = ["0.0.0.0/0", "::/0"]
  extra_firewall_rules = [
    {
      description = "HTTP"
      direction   = "in"
      protocol    = "tcp"
      port        = "80"
      source_ips  = ["0.0.0.0/0", "::/0"]
    },
    {
      description = "HTTPS"
      direction   = "in"
      protocol    = "tcp"
      port        = "443"
      source_ips  = ["0.0.0.0/0", "::/0"]
    },
    {
      description = "Tailscale WireGuard"
      direction   = "in"
      protocol    = "udp"
      port        = "41641"
      source_ips  = ["0.0.0.0/0", "::/0"]
    },
  ]

  # Cilium and CCM managed by ArgoCD, not bootstrap
  deploy_cilium     = false
  deploy_hcloud_ccm = false

  # Sysctls for Cilium
  sysctls_extra_args = {
    "net.ipv4.ip_forward"             = "1"
    "net.ipv6.conf.all.forwarding"    = "1"
    "net.ipv4.conf.all.rp_filter"     = "0"
    "net.ipv4.conf.default.rp_filter" = "0"
  }
}

# Storage Box for bulk data (Immich photos, oCIS files, DB dumps)
resource "hcloud_storage_box" "data" {
  name             = "homelab-data"
  location         = var.location
  storage_box_type = "bx11"
  password         = local.storagebox_password

  access_settings = {
    ssh_enabled = true
  }

  labels = {
    purpose = "homelab"
  }
}
