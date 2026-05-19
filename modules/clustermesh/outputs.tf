output "connected_clusters" {
  value = var.cluster_names
}

output "mesh_enabled" {
  value = length(var.cluster_names) > 1
}

output "merged_kubeconfig" {
  value = length(var.cluster_names) > 1 && length(compact(values(local.kubeconfig_raw))) > 0 ? yamlencode({
    apiVersion  = "v1"
    kind        = "Config"
    preferences = {}
    clusters = flatten([
      for name, raw in local.kubeconfig_raw : [
        for cluster in lookup(yamldecode(raw), "clusters", []) : merge(cluster, { name = name })
      ] if raw != ""
    ])
    contexts = flatten([
      for name, raw in local.kubeconfig_raw : [
        for ctx in lookup(yamldecode(raw), "contexts", []) : merge(ctx, {
          name = name
          context = merge(lookup(ctx, "context", {}), {
            cluster = name
            user    = "${name}-user"
          })
        })
      ] if raw != ""
    ])
    users = flatten([
      for name, raw in local.kubeconfig_raw : [
        for user in lookup(yamldecode(raw), "users", []) : merge(user, { name = "${name}-user" })
      ] if raw != ""
    ])
  }) : ""
  sensitive = true
}
