variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "cluster_name" {
  type = string
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

variable "talos_version" {
  type = string
}

variable "schematic_id" {
  type    = string
  default = "4a0d65c669d46663f377e7161e50cfd570c401f26fd9e7bda34a0216b6f1922b"
}

variable "ssh_public_key" {
  type = string
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

variable "network" {
  type    = string
  default = "default"
}

variable "subnetwork" {
  type    = string
  default = ""
}

variable "gcs_bucket" {
  type    = string
  default = ""
}
