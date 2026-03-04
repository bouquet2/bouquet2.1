output "kubeconfig" {
  description = "Kubernetes kubeconfig for the GKE cluster"
  value       = local.kubeconfig
  sensitive   = true
}

output "cluster_endpoint" {
  description = "The endpoint IP of the GKE cluster"
  value       = google_container_cluster.this.endpoint
}

output "cluster_name" {
  description = "The name of the GKE cluster"
  value       = google_container_cluster.this.name
}

output "pod_cidr" {
  description = "The pod CIDR range allocated for the cluster"
  value       = google_container_cluster.this.cluster_ipv4_cidr
}

output "services_cidr" {
  description = "The services CIDR range allocated for the cluster"
  value       = google_container_cluster.this.services_ipv4_cidr
}

output "install_complete" {
  description = "List of resource IDs indicating installation completion"
  value = concat(
    [google_container_cluster.this.id],
    [for np in google_container_node_pool.this : np.id],
    var.cilium.enabled ? [null_resource.cilium_install[0].id] : []
  )
}

output "node_pool_names" {
  description = "Names of the node pools created"
  value       = [for np in google_container_node_pool.this : np.name]
}

output "cluster_ca_certificate" {
  description = "Base64 encoded cluster CA certificate"
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
}
