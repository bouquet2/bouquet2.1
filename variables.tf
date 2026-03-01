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

variable "clusters" {
  description = "Multi-cluster configuration with Cilium Cluster Mesh support"
  type = map(object({
    cluster_id = number

    control_planes = list(object({
      name         = string
      provider     = string
      server_type  = optional(string, "cx23")
      location     = optional(string, "fsn1")
      install_disk = optional(string, "/dev/sda")
      machine_type = optional(string, "e2-standard-2")
      disk_size    = optional(number, 50)
    }))

    workers = list(object({
      name         = string
      provider     = string
      server_type  = optional(string, "cx23")
      location     = optional(string, "fsn1")
      install_disk = optional(string, "/dev/sda")
      machine_type = optional(string, "e2-standard-2")
      disk_size    = optional(number, 50)
    }))

    gcp = optional(object({
      project_id = string
      region     = string
      zone       = string
      network    = optional(string, "default")
      subnetwork = optional(string, "")
      gcs_bucket = optional(string, "")
    }))
  }))
  default = {}
}

variable "tailscale" {
  description = "Tailscale VPN configuration (shared across all clusters)"
  type = object({
    enabled         = bool
    tailnet         = optional(string, "")
    tag             = optional(string, "tag:k8s-operator")
    routes          = optional(list(string), [])
    manage_acl      = optional(bool, false)
    acl_policy      = optional(string, "")
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

variable "cilium" {
  description = "Cilium CNI configuration (shared across all clusters)"
  type = object({
    enabled                = optional(bool, true)
    kube_proxy_replacement = optional(bool, true)
    ipam_mode              = optional(string, "kubernetes")
    clustermesh            = optional(bool, false)
    gateway_api            = optional(bool, false)
  })
  default = {}
}

variable "network" {
  description = "Network configuration (shared across all clusters)"
  type = object({
    pod_subnets     = optional(list(string), ["10.244.0.0/16"])
    service_subnets = optional(list(string), ["10.96.0.0/12"])
  })
  default = {}
}

variable "onepassword_vault" {
  description = "1Password vault name for secrets"
  type        = string
  default     = "Infrastructure"
}

variable "onepassword_account" {
  description = "1Password account name (as shown in desktop app sidebar). Alternatively, set OP_ACCOUNT environment variable."
  type        = string
  default     = null
}
