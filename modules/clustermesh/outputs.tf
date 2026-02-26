output "connected_clusters" {
  value = var.cluster_names
}

output "mesh_enabled" {
  value = length(var.cluster_names) > 1
}
