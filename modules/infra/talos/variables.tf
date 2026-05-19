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
    routing_mode           = optional(string, "native")
    clustermesh            = optional(bool, false)
    gateway_api            = optional(bool, false)
    encryption_enabled     = optional(bool, false)
    encryption_type        = optional(string, "wireguard")
    node_encryption        = optional(bool, false)
    big_tcp                = optional(bool, true)
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

variable "clustermesh_service_type" {
  type        = string
  default     = "NodePort"
  description = "Service type for Cilium ClusterMesh API server (NodePort or LoadBalancer)"
}

variable "cilium_version" {
  type        = string
  description = "Cilium Helm chart version to install (e.g. 1.17.3)"
}

variable "gateway_api_version" {
  type        = string
  default     = "v1.0.0"
  description = "Gateway API CRD version for Cilium Gateway API support"
}

variable "hcloud_token" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Hetzner Cloud API token (required for hcloud-cloud-controller-manager)"
}

variable "hcloud_network_id" {
  type        = number
  default     = null
  description = "Hetzner Cloud network ID for load balancer traffic (optional)"
}

variable "hetzner_loadbalancer_enabled" {
  type        = bool
  default     = false
  description = "When true, deploy hcloud-ccm to provision Hetzner Cloud LoadBalancers for type:LoadBalancer services"
}

variable "node_ip_subnets" {
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fd20::/20"]
  description = "Valid subnets for kubelet node IP assignment"

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

variable "hetzner_network_cidr" {
  type        = string
  default     = ""
  description = "Hetzner Cloud private network CIDR for etcd advertisedSubnets"
}

variable "approved_underlay_ula_subnets" {
  type        = list(string)
  default     = ["fd20::/20"]
  description = "Explicit non-Tailscale ULA CIDRs allowed for kubelet node IP assignment"

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
