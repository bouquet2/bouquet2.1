variable "cluster_name" {
  type = string
}

variable "cluster_id" {
  type        = number
  description = "Unique cluster ID for Cilium Cluster Mesh (1-255)"
}

variable "talos_version" {
  type = string
}

variable "kubernetes_version" {
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

variable "network" {
  type = object({
    pod_subnets     = optional(list(string))
    service_subnets = optional(list(string))
  })
  default = {}
}

variable "cilium" {
  type = object({
    enabled                = optional(bool)
    kube_proxy_replacement = optional(bool)
    ipam_mode              = optional(string)
    clustermesh            = optional(bool, false)
  })
  default = {}
}

variable "tailscale_enabled" {
  type    = bool
  default = false
}

variable "tailscale_auth_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "tailscale_routes" {
  type    = list(string)
  default = []
}

variable "dns_enabled" {
  type    = bool
  default = false
}

variable "dns_domain" {
  type    = string
  default = ""
}
