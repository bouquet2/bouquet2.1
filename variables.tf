variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
  default     = "bouquet21"
}

variable "talos_version" {
  description = "Talos Linux version (null = latest)"
  type        = string
  default     = null
}

variable "kubernetes_version" {
  description = "Kubernetes version (null = latest)"
  type        = string
  default     = null
}

variable "control_planes" {
  description = "Control plane node configurations"
  type = list(object({
    name         = string
    server_type  = optional(string, "cx23")
    location     = optional(string, "fsn1")
    install_disk = optional(string, "/dev/sda")
  }))
  default = []
}

variable "workers" {
  description = "Worker node configurations"
  type = list(object({
    name         = string
    server_type  = optional(string, "cx23")
    location     = optional(string, "fsn1")
    install_disk = optional(string, "/dev/sda")
  }))
  default = []
}

variable "tailscale" {
  description = "Tailscale VPN configuration"
  type = object({
    enabled         = bool
    tailnet         = optional(string, "")
    oauth_client_id = optional(string, "")
    tag             = optional(string, "tag:k8s-operator")
    routes          = optional(list(string), [])
  })
  default = {
    enabled = false
  }
}

variable "dns" {
  description = "DNS configuration"
  type = object({
    enabled         = bool
    domain          = optional(string, "")
    internal_domain = optional(string, "")
  })
  default = {
    enabled = false
  }
}

variable "network" {
  description = "Network configuration"
  type = object({
    pod_subnets     = optional(list(string), ["10.244.0.0/16"])
    service_subnets = optional(list(string), ["10.96.0.0/12"])
  })
  default = {}
}

variable "cilium" {
  description = "Cilium CNI configuration"
  type = object({
    enabled                = optional(bool, true)
    kube_proxy_replacement = optional(bool, true)
    ipam_mode              = optional(string, "kubernetes")
  })
  default = {}
}
