variable "domain" {
  type = string
}

variable "internal_domain" {
  type = string
}

variable "cluster_names" {
  type = list(string)
}

variable "cluster_control_plane_ips" {
  type = map(map(string))
}

variable "cluster_worker_ips" {
  type = map(map(string))
}

variable "tailscale_ips" {
  type    = map(string)
  default = {}
}

variable "lb_subdomain" {
  type    = string
  default = "lb"
}

data "cloudflare_zone" "this" {
  name = var.domain
}

locals {
  all_control_plane_ips = merge(values(var.cluster_control_plane_ips)...)
  all_worker_ips        = merge(values(var.cluster_worker_ips)...)
  all_node_ips          = merge(local.all_control_plane_ips, local.all_worker_ips)
}

resource "cloudflare_record" "control_plane_api_global" {
  for_each = local.all_control_plane_ips

  zone_id = data.cloudflare_zone.this.id
  name    = "control-planes.internal"
  type    = "A"
  ttl     = 300
  content = lookup(var.tailscale_ips, each.key, each.value)
  proxied = false
}

resource "cloudflare_record" "control_plane_api_cluster" {
  for_each = merge([
    for cluster_name, ips in var.cluster_control_plane_ips : {
      for node_name, ip in ips : "${cluster_name}-${node_name}" => {
        cluster_name = cluster_name
        node_name    = node_name
        ip           = ip
      }
    }
  ]...)

  zone_id = data.cloudflare_zone.this.id
  name    = "control-planes.${each.value.cluster_name}.internal"
  type    = "A"
  content = lookup(var.tailscale_ips, "${each.value.cluster_name}-${each.value.node_name}", each.value.ip)
  ttl     = 300
  proxied = false
}

resource "cloudflare_record" "worker_global" {
  for_each = local.all_worker_ips

  zone_id = data.cloudflare_zone.this.id
  name    = "workers.internal"
  type    = "A"
  content = lookup(var.tailscale_ips, each.key, each.value)
  ttl     = 300
  proxied = false
}

resource "cloudflare_record" "worker_cluster" {
  for_each = merge([
    for cluster_name, ips in var.cluster_worker_ips : {
      for node_name, ip in ips : "${cluster_name}-${node_name}" => {
        cluster_name = cluster_name
        node_name    = node_name
        ip           = ip
      }
    }
  ]...)

  zone_id = data.cloudflare_zone.this.id
  name    = "workers.${each.value.cluster_name}.internal"
  type    = "A"
  content = lookup(var.tailscale_ips, "${each.value.cluster_name}-${each.value.node_name}", each.value.ip)
  ttl     = 300
  proxied = false
}

resource "cloudflare_record" "node_internal" {
  for_each = merge([
    for cluster_name, cluster in {
      for cn, ips in var.cluster_control_plane_ips : cn => {
        ips         = ips
        node_type   = "control-planes"
      }
    } : {
      for node_name, ip in cluster.ips : "${cluster_name}-${node_name}" => {
        cluster_name = cluster_name
        node_name    = node_name
        node_type    = cluster.node_type
        ip           = ip
      }
    }
  ]...)

  zone_id = data.cloudflare_zone.this.id
  name    = "${each.value.node_name}.${each.value.cluster_name}.internal"
  type    = "A"
  content = lookup(var.tailscale_ips, each.key, each.value.ip)
  ttl     = 300
  proxied = false
}

resource "cloudflare_record" "lb" {
  for_each = local.all_node_ips

  zone_id = data.cloudflare_zone.this.id
  name    = var.lb_subdomain
  type    = "A"
  content = each.value
  ttl     = 1
  proxied = true
}
