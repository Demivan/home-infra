variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "server_type" {
  description = "Hetzner Cloud server type"
  type        = string
  default     = "cax31"
}

variable "location" {
  description = "Hetzner Cloud datacenter location"
  type        = string
  default     = "hel1"
}

variable "talos_version" {
  description = "Talos Linux version to deploy"
  type        = string
  default     = "v1.12.6"
}
