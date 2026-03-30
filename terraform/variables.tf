variable "server_type" {
  description = "Hetzner Cloud server type"
  type        = string
  default     = "cx43"
}

variable "location" {
  description = "Hetzner Cloud location"
  type        = string
  default     = "fsn1"
}

variable "talos_version" {
  description = "Talos Linux version to deploy"
  type        = string
  default     = "v1.12.6"
}

variable "kubernetes_version" {
  description = "Kubernetes version (must match Talos support matrix)"
  type        = string
  default     = "1.35.2"
}
