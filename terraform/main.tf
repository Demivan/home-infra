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
      version = "~> 0.12"
    }
    imager = {
      source  = "hcloud-talos/imager"
      version = "~> 1.0"
    }
    infisical = {
      source  = "Infisical/infisical"
      version = "~> 0.19"
    }
  }
}

# Auth via INFISICAL_UNIVERSAL_AUTH_CLIENT_ID / INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET env vars
provider "infisical" {
  host = "https://eu.infisical.com"
}

data "infisical_secrets" "main" {
  env_slug     = "prod"
  workspace_id = "41eab2df-3208-4fff-a0aa-036970ba8b6f"
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
      # slskd Soulseek P2P listen port (NodePort on the node). Must allow all
      # source IPs — Soulseek peers connect from arbitrary addresses.
      description = "slskd Soulseek P2P"
      direction   = "in"
      protocol    = "tcp"
      port        = "30300"
      source_ips  = ["0.0.0.0/0", "::/0"]
    },
    {
      # Stalwart mail ports (a node-IPAM LoadBalancer on the node IP): inbound
      # SMTP, implicit-TLS and STARTTLS submission, IMAPS.
      description = "SMTP"
      direction   = "in"
      protocol    = "tcp"
      port        = "25"
      source_ips  = ["0.0.0.0/0", "::/0"]
    },
    {
      description = "SMTP submissions"
      direction   = "in"
      protocol    = "tcp"
      port        = "465"
      source_ips  = ["0.0.0.0/0", "::/0"]
    },
    {
      description = "SMTP submission"
      direction   = "in"
      protocol    = "tcp"
      port        = "587"
      source_ips  = ["0.0.0.0/0", "::/0"]
    },
    {
      description = "IMAPS"
      direction   = "in"
      protocol    = "tcp"
      port        = "993"
      source_ips  = ["0.0.0.0/0", "::/0"]
    },
    {
      # Tailscale WireGuard direct-connection port. Not strictly required
      # (Tailscale falls back to DERP relays) but enables direct P2P.
      # Kept in Terraform so applies don't prune it from the firewall.
      description = "Tailscale WireGuard"
      direction   = "in"
      protocol    = "udp"
      port        = "41641"
      source_ips  = ["0.0.0.0/0", "::/0"]
    },
  ]

  # Cilium, CCM, and CoreDNS managed by ArgoCD, not bootstrap
  deploy_cilium         = false
  deploy_hcloud_ccm     = false
  disable_talos_coredns = true

  # Sysctls for Cilium
  sysctls_extra_args = {
    "net.ipv4.ip_forward"             = "1"
    "net.ipv6.conf.all.forwarding"    = "1"
    "net.ipv4.conf.all.rp_filter"     = "0"
    "net.ipv4.conf.default.rp_filter" = "0"
  }
}

# Reverse DNS for the node's public IPv4, which is also the mail host
# (mail.demivan.me): receiving servers check that the connecting IP's PTR
# resolves back to it. The reverse zone is Hetzner's, so this cannot live in
# Cloudflare. Set on the Primary IP, which the module keeps across server
# re-creation (auto_delete = false).
data "hcloud_primary_ip" "control_plane_ipv4" {
  ip_address = module.talos.public_ipv4_list[0]
}

resource "hcloud_rdns" "mail" {
  primary_ip_id = data.hcloud_primary_ip.control_plane_ipv4.id
  ip_address    = data.hcloud_primary_ip.control_plane_ipv4.ip_address
  dns_ptr       = "mail.demivan.me"
}

# Storage Box for bulk data (Immich photos, oCIS files, DB dumps)
resource "hcloud_storage_box" "data" {
  name             = "homelab-data"
  location         = var.location
  storage_box_type = "bx11"
  password         = local.storagebox_password

  access_settings = {
    ssh_enabled          = true
    samba_enabled        = true
    reachable_externally = true
  }

  labels = {
    purpose = "homelab"
  }
}
