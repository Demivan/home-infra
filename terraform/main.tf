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
  }
}

provider "hcloud" {
  token = var.hcloud_token
}
