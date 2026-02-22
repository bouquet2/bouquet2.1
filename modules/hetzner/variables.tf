variable "cluster_name" {
  type = string
}

variable "control_planes" {
  type = list(object({
    name         = string
    server_type  = optional(string)
    location     = optional(string)
    install_disk = optional(string)
  }))
}

variable "workers" {
  type = list(object({
    name         = string
    server_type  = optional(string)
    location     = optional(string)
    install_disk = optional(string)
  }))
}

variable "ssh_public_key" {
  type = string
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "talos_version" {
  type = string
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "schematic_id" {
  type    = string
  default = "4a0d65c669d46663f377e7161e50cfd570c401f26fd9e7bda34a0216b6f1922b"
}

variable "control_plane_configs" {
  type      = map(string)
  sensitive = true
  default   = {}
}

variable "worker_configs" {
  type      = map(string)
  sensitive = true
  default   = {}
}
