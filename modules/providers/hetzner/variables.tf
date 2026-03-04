variable "cluster_name" {
  type = string
}

variable "network_id" {
  type        = number
  description = "Hetzner private network ID to attach servers to"
}

variable "control_planes" {
  type = list(object({
    name         = string
    provider     = optional(string)
    server_type  = optional(string)
    location     = optional(string)
    install_disk = optional(string)
    machine_type = optional(string)
    disk_size    = optional(number)
  }))
}

variable "workers" {
  type = list(object({
    name         = string
    provider     = optional(string)
    server_type  = optional(string)
    location     = optional(string)
    install_disk = optional(string)
    machine_type = optional(string)
    disk_size    = optional(number)
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
