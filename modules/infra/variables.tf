variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "cluster_config" {
  description = "Configuration for the cluster"
  type = object({
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

    gcp = optional(object({
      project_id = string
      region     = string
      zone       = string
      network    = optional(string, "default")
      subnetwork = optional(string, "")
      gcs_bucket = optional(string, "")
    }))
  })
}

variable "talos_version" {
  type    = string
  default = null
}

variable "kubernetes_version" {
  type    = string
  default = null
}

variable "cilium_version" {
  type    = string
  default = null
}

variable "gateway_api_version" {
  type    = string
  default = "v1.0.0"
}

variable "cilium" {
  type = any
}

variable "network" {
  type = any
}

variable "tailscale" {
  type = any
}

variable "dns" {
  type = any
}

variable "hetzner" {
  type    = any
  default = {}
}

variable "hcloud_token" {
  type      = string
  sensitive = true
  default   = null
}

variable "tailscale_oauth_client_id" {
  type      = string
  sensitive = true
  default   = null
}

variable "tailscale_oauth_secret" {
  type      = string
  sensitive = true
  default   = null
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
  default   = null
}

variable "primary_cluster" {
  description = "Name of the primary cluster for global DNS CNAMEs"
  type        = string
  default     = ""
}

variable "vpc_peering" {
  description = "List of VPC peerings to establish with other cluster VPCs"
  type = list(object({
    name        = string
    vpc_link    = string
    ipv6_prefix = optional(string)
  }))
  default = []
}

variable "subnet_cidr" {
  description = "CIDR range for the GCP subnet (must be unique across peered VPCs)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "hetzner_network_cidr" {
  description = "CIDR range for the Hetzner private network (must be unique per Hetzner cluster)"
  type        = string
  default     = "10.100.0.0/16"
}

variable "node_ip_subnets" {
  description = "Valid subnets for kubelet node IP assignment"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fd20::/20"]

  validation {
    condition = alltrue([
      for cidr in var.node_ip_subnets : (
        can(cidrhost(cidr, 0))
        && lower(cidr) != "100.64.0.0/10"
        && lower(cidr) != "fd7a:115c:a1e0::/48"
        && lower(cidr) != "fc00::/7"
        && (
          (
            !can(regex(":", cidr))
            && (
              cidrcontains("10.0.0.0/8", cidrhost(cidr, 0))
              || cidrcontains("172.16.0.0/12", cidrhost(cidr, 0))
              || cidrcontains("192.168.0.0/16", cidrhost(cidr, 0))
            )
          )
          || (
            can(regex(":", cidr))
            && contains([for s in var.approved_underlay_ula_subnets : lower(s)], lower(cidr))
          )
        )
      )
    ])
    error_message = "node_ip_subnets must only include RFC1918 IPv4 CIDRs and explicit approved_underlay_ula_subnets IPv6 CIDRs; Tailscale and broad ULA CIDRs are not allowed."
  }
}

variable "node_providers" {
  description = "Map of node name to provider (hetzner/gcp) for Talos config branching"
  type        = map(string)
  default     = {}
}

variable "approved_underlay_ula_subnets" {
  description = "Explicit non-Tailscale ULA CIDRs allowed for kubelet node IP assignment"
  type        = list(string)
  default     = ["fd20::/20"]

  validation {
    condition = alltrue([
      for cidr in var.approved_underlay_ula_subnets : (
        can(cidrhost(cidr, 0))
        && can(regex(":", cidr))
        && startswith(lower(cidr), "fd")
        && lower(cidr) != "fd7a:115c:a1e0::/48"
        && lower(cidr) != "fc00::/7"
      )
    ])
    error_message = "approved_underlay_ula_subnets must be explicit non-Tailscale ULA IPv6 CIDRs and must not include fd7a:115c:a1e0::/48 or fc00::/7."
  }
}

variable "ceph" {
  type = object({
    enabled  = optional(bool, false)
    data_dir = optional(string, "/var/lib/rook")
    mon = optional(object({
      count                   = optional(number, 1)
      allow_multiple_per_node = optional(bool, true)
    }))
    mgr = optional(object({
      count = optional(number, 1)
    }))
    dashboard = optional(object({
      enabled = optional(bool, true)
      ssl     = optional(bool, false)
    }))
    cephfs = optional(object({
      enabled                = optional(bool, true)
      name                   = optional(string, "cephfs")
      metadata_pool_replicas = optional(number, 2)
      data_pool_replicas     = optional(number, 2)
    }))
    storage_classes = optional(object({
      block   = optional(bool, true)
      fs      = optional(bool, true)
      default = optional(string, "fs")
    }))
    osd_disk_size         = optional(number, 50)
    osd_on_control_planes = optional(bool, false)
  })
  default     = {}
  description = "Ceph storage configuration"
}
