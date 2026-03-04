variable "cluster_name" {
  type = string
}

variable "cluster_id" {
  type = number
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "network" {
  type    = string
  default = "default"
}

variable "subnetwork" {
  type    = string
  default = ""
}

variable "node_pools" {
  type = list(object({
    name         = string
    machine_type = optional(string, "e2-standard-2")
    min_count    = optional(number, 1)
    max_count    = optional(number, 3)
    disk_size_gb = optional(number, 50)
    preemptible  = optional(bool, false)
    node_labels  = optional(map(string), {})
    node_taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = []
}

variable "pod_cidr" {
  type    = string
  default = "10.248.0.0/14"
}

variable "services_cidr" {
  type    = string
  default = "10.100.0.0/20"
}

variable "master_ipv4_cidr_block" {
  type    = string
  default = "172.16.0.0/28"
}

variable "enable_private_cluster" {
  type    = bool
  default = true
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "cilium" {
  type = object({
    enabled                = optional(bool, true)
    kube_proxy_replacement = optional(bool, true)
    ipam_mode              = optional(string, "kubernetes")
    clustermesh            = optional(bool, false)
    gateway_api            = optional(bool, false)
    encryption_enabled     = optional(bool, false)
    encryption_type        = optional(string, "wireguard")
    node_encryption        = optional(bool, true)
  })
  default = {}
}

variable "network_policy_enabled" {
  type    = bool
  default = false
}

variable "kubernetes_version" {
  type    = string
  default = ""
}

variable "deletion_protection" {
  type        = bool
  default     = false
  description = "Whether to protect the cluster from accidental deletion"
}

variable "cilium_version" {
  type        = string
  description = "Cilium Helm chart version to install"
}
