output "kubeconfigs" {
  description = "Kubernetes kubeconfigs for each cluster"
  value       = local.all_kubeconfigs
  sensitive   = true
}

locals {
  cluster_endpoints = merge(
    # Talos clusters: use DNS domain if enabled, else Tailscale IP if enabled, else public IP
    { for name in keys(local.talos_clusters) : name =>
      var.dns.enabled && var.dns.internal_domain != ""
        ? "control-planes.${name}.${var.dns.internal_domain}"
        : (var.tailscale.enabled && length(module.tailscale_devices) > 0
            ? values(module.tailscale_devices[0].cluster_node_ips[name])[0]
            : values(local.cluster_control_plane_ips[name])[0])
    },
    # GKE clusters: use GKE endpoint directly
    { for name in keys(local.gke_clusters) : name => lookup(local.gke_cluster_endpoints, name, "") }
  )

  kubeconfig_merged = length(var.clusters) > 0 ? yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    preferences = {}
    clusters = [for name, cluster in var.clusters : {
      name = name
      cluster = {
        server = contains(keys(local.gke_clusters), name) ? "https://${local.cluster_endpoints[name]}" : "https://${local.cluster_endpoints[name]}:6443"
        certificate-authority-data = try(yamldecode(local.all_kubeconfigs[name]).clusters[0].cluster["certificate-authority-data"], "")
      }
    } if try(local.all_kubeconfigs[name], "") != ""]
    contexts = [for name, cluster in var.clusters : {
      name = name
      context = {
        cluster = name
        user    = name
      }
    } if try(local.all_kubeconfigs[name], "") != ""]
    users = [for name, cluster in var.clusters : {
      name = name
      user = {
        client-certificate-data = try(yamldecode(local.all_kubeconfigs[name]).users[0].user["client-certificate-data"], "")
        client-key-data         = try(yamldecode(local.all_kubeconfigs[name]).users[0].user["client-key-data"], "")
        token                   = try(yamldecode(local.all_kubeconfigs[name]).users[0].user["token"], null)
      }
    } if try(local.all_kubeconfigs[name], "") != ""]
  }) : ""
}

output "kubeconfig" {
  description = "Merged kubeconfig with all clusters"
  value       = local.kubeconfig_merged
  sensitive   = true
}

output "talosconfigs" {
  description = "Talos configs for each Talos cluster"
  value       = { for k, v in data.talos_client_configuration.this : k => v.talos_config }
  sensitive   = true
}

output "cluster_control_plane_ips" {
  description = "IPv4 addresses of control plane nodes per cluster"
  value       = local.cluster_control_plane_ips
}

output "cluster_worker_ips" {
  description = "IPv4 addresses of worker nodes per cluster"
  value       = local.cluster_worker_ips
}

output "all_control_plane_ips" {
  description = "IPv4 addresses of all control plane nodes across clusters"
  value       = local.all_control_plane_ips
}

output "all_worker_ips" {
  description = "IPv4 addresses of all worker nodes across clusters"
  value       = local.all_worker_ips
}

output "cluster_control_plane_ipv6s" {
  description = "IPv6 addresses of control plane nodes per cluster (Hetzner only)"
  value       = local.cluster_control_plane_ipv6s
}

output "cluster_worker_ipv6s" {
  description = "IPv6 addresses of worker nodes per cluster (Hetzner only)"
  value       = local.cluster_worker_ipv6s
}

output "all_control_plane_ipv6s" {
  description = "IPv6 addresses of all control plane nodes across clusters (Hetzner only)"
  value       = local.all_control_plane_ipv6s
}

output "all_worker_ipv6s" {
  description = "IPv6 addresses of all worker nodes across clusters (Hetzner only)"
  value       = local.all_worker_ipv6s
}

output "tailscale_ips" {
  description = "Tailscale IPs of all nodes"
  value       = var.tailscale.enabled ? module.tailscale_devices[0].all_node_ips : {}
}

output "resolved_talos_version" {
  value = local.talos_version
}

output "resolved_kubernetes_version" {
  value = local.kubernetes_version
}

output "resolved_cilium_version" {
  value = local.cilium_version
}

output "clustermesh_enabled" {
  description = "Whether Cilium Cluster Mesh is enabled"
  value       = var.cilium.clustermesh && length(var.clusters) > 1
}
