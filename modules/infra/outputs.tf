output "control_plane_ips" {
  value = local.control_plane_ips
}

output "worker_ips" {
  value = local.worker_ips
}

output "client_configuration" {
  value     = module.talos.client_configuration
  sensitive = true
}

output "control_plane_configs" {
  value     = module.talos.control_plane_configs
  sensitive = true
}

output "worker_configs" {
  value     = module.talos.worker_configs
  sensitive = true
}

output "tailscale_control_plane_ips" {
  value = var.tailscale.enabled ? {
    for cp in var.cluster_config.control_planes : cp.name => module.tailscale_devices[0].cluster_node_ips[var.cluster_name]["${var.cluster_name}-${cp.name}"]
  } : {}
}

output "tailscale_worker_ips" {
  value = var.tailscale.enabled ? {
    for w in var.cluster_config.workers : w.name => module.tailscale_devices[0].cluster_node_ips[var.cluster_name]["${var.cluster_name}-${w.name}"]
  } : {}
}

output "hetzner_control_plane_provider_ids" {
  value = local.has_hetzner ? module.hetzner[0].control_plane_provider_ids : {}
}

output "hetzner_worker_provider_ids" {
  value = local.has_hetzner ? module.hetzner[0].worker_provider_ids : {}
}

output "kubeconfig_raw" {
  value     = length(var.cluster_config.control_planes) > 0 ? talos_cluster_kubeconfig.this[0].kubeconfig_raw : ""
  sensitive = true
}

output "kubeconfig_path" {
  value = length(var.cluster_config.control_planes) > 0 ? nonsensitive(local_file.kubeconfig[0].filename) : ""
}

output "talosconfig" {
  value     = length(var.cluster_config.control_planes) > 0 ? data.talos_client_configuration.this[0].talos_config : ""
  sensitive = true
}

output "vpc_self_link" {
  value = local.has_gcp ? module.gcp[0].vpc_self_link : ""
}

output "ceph_disk_ids" {
  value = local.has_gcp ? module.gcp[0].ceph_disk_ids : []
}

output "has_gcp" {
  value = local.has_gcp
}

output "tailscale_enabled" {
  value = var.tailscale.enabled
}
