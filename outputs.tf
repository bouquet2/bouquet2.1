output "kubeconfigs" {
  description = "Kubernetes kubeconfigs for each cluster"
  value       = { for k, v in var.clusters : k => try(talos_cluster_kubeconfig.this[k].kubeconfig_raw, "") }
  sensitive   = true
}

locals {
  cluster_endpoints = var.tailscale.enabled && length(module.tailscale_devices) > 0 ? {
    for name in keys(var.clusters) : name => values(module.tailscale_devices[0].cluster_node_ips[name])[0]
  } : { for name in keys(var.clusters) : name => values(local.cluster_control_plane_ips[name])[0] }

  kubeconfig_merged = length(var.clusters) > 0 ? yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    preferences = {}
    clusters = [for name, cluster in var.clusters : {
      name = name
      cluster = {
        server = "https://${local.cluster_endpoints[name]}:6443"
        certificate-authority-data = try(yamldecode(talos_cluster_kubeconfig.this[name].kubeconfig_raw).clusters[0].cluster["certificate-authority-data"], "")
      }
    } if try(talos_cluster_kubeconfig.this[name].kubeconfig_raw, "") != ""]
    contexts = [for name, cluster in var.clusters : {
      name = name
      context = {
        cluster = name
        user    = name
      }
    } if try(talos_cluster_kubeconfig.this[name].kubeconfig_raw, "") != ""]
    users = [for name, cluster in var.clusters : {
      name = name
      user = {
        client-certificate-data = try(yamldecode(talos_cluster_kubeconfig.this[name].kubeconfig_raw).users[0].user["client-certificate-data"], "")
        client-key-data         = try(yamldecode(talos_cluster_kubeconfig.this[name].kubeconfig_raw).users[0].user["client-key-data"], "")
      }
    } if try(talos_cluster_kubeconfig.this[name].kubeconfig_raw, "") != ""]
  }) : ""
}

output "kubeconfig" {
  description = "Merged kubeconfig with all clusters"
  value       = local.kubeconfig_merged
  sensitive   = true
}

output "talosconfigs" {
  description = "Talos configs for each cluster"
  value       = { for k, v in data.talos_client_configuration.this : k => v.talos_config }
  sensitive   = true
}

output "cluster_control_plane_ips" {
  description = "IP addresses of control plane nodes per cluster"
  value       = local.cluster_control_plane_ips
}

output "cluster_worker_ips" {
  description = "IP addresses of worker nodes per cluster"
  value       = local.cluster_worker_ips
}

output "all_control_plane_ips" {
  description = "IP addresses of all control plane nodes across clusters"
  value       = local.all_control_plane_ips
}

output "all_worker_ips" {
  description = "IP addresses of all worker nodes across clusters"
  value       = local.all_worker_ips
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

output "clustermesh_enabled" {
  description = "Whether Cilium Cluster Mesh is enabled"
  value       = var.cilium.clustermesh && length(var.clusters) > 1
}
