variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "server_type" {
  description = "Hetzner Cloud server type"
  type        = string
  default     = "cx43"
}

variable "location" {
  description = "Hetzner Cloud datacenter location"
  type        = string
  default     = "fsn1"
}

variable "talos_version" {
  description = "Talos Linux version to deploy"
  type        = string
  default     = "v1.12.6"
}
