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
    type       = optional(string, "talos")

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

    floating_ip_count = optional(number) # deprecated, no-op

    gcp = optional(object({
      project_id = string
      region     = string
      zone       = string
      network    = optional(string, "default")
      subnetwork = optional(string, "")
      gcs_bucket = optional(string, "")

      node_pools = optional(list(object({
        name          = string
        machine_type  = optional(string, "e2-standard-2")
        min_count     = optional(number, 1)
        max_count     = optional(number, 3)
        disk_size_gb  = optional(number, 50)
        preemptible   = optional(bool, false)
        node_labels   = optional(map(string), {})
        node_taints   = optional(list(object({
          key    = string
          value  = string
          effect = string
        })), [])
      })), [])

      pod_cidr               = optional(string, "")
      services_cidr          = optional(string, "")
      master_ipv4_cidr_block = optional(string, "172.16.0.0/28")
      enable_private_cluster = optional(bool, true)
      deletion_protection    = optional(bool, false)
      master_authorized_networks = optional(list(object({
        cidr_block   = string
        display_name = string
      })), [])
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
    encryption_enabled     = optional(bool)
    encryption_type        = optional(string, "wireguard")
    node_encryption        = optional(bool, true)
  })
  default = {}
}

variable "network" {
  description = "Network configuration (shared across all clusters)"
  type = object({
    pod_subnets       = optional(list(string), ["10.244.0.0/16"])
    service_subnets   = optional(list(string), ["10.96.0.0/12"])
    loadbalancer_type = optional(string, "cilium")
  })
  default = {}
}

variable "hetzner" {
  description = "Hetzner-specific configuration"
  type = object({
    loadbalancer_enabled = optional(bool, false)
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
