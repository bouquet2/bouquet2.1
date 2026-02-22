output "kubeconfig" {
  description = "Kubernetes kubeconfig for the cluster"
  value       = length(var.control_planes) > 0 ? talos_cluster_kubeconfig.this[0].kubeconfig_raw : ""
  sensitive   = true
}

output "talosconfig" {
  description = "Talos config for the cluster"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "control_plane_ips" {
  description = "IP addresses of control plane nodes"
  value       = module.hetzner.control_plane_ips
}

output "worker_ips" {
  description = "IP addresses of worker nodes"
  value       = module.hetzner.worker_ips
}

output "tailscale_ips" {
  description = "Tailscale IPs of all nodes"
  value       = var.tailscale.enabled ? module.tailscale_devices[0].node_ips : {}
}

output "resolved_talos_version" {
  value = local.talos_version
}

output "resolved_kubernetes_version" {
  value = local.kubernetes_version
}
