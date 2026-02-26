variable "cluster_names" {
  type = list(string)
}

variable "cluster_ids" {
  type = map(number)
}

variable "kubeconfigs" {
  type      = map(string)
  sensitive = true
}

variable "control_plane_ips" {
  type = map(map(string))
}

locals {
  first_cluster = var.cluster_names[0]
}

resource "null_resource" "clustermesh_connect" {
  count = length(var.cluster_names) > 1 ? 1 : 0

  triggers = {
    clusters = join(",", var.cluster_names)
  }

  provisioner "local-exec" {
    environment = merge(
      { for name in var.cluster_names : "KUBECONFIG_${replace(name, "-", "_")}" => base64encode(var.kubeconfigs[name]) },
      { for name in var.cluster_names : "CP_IP_${replace(name, "-", "_")}" => values(var.control_plane_ips[name])[0] },
      { PATH = "/opt/homebrew/bin:/etc/profiles/per-user/kreato/bin:/usr/local/bin:/usr/bin:/bin" }
    )
    command = <<-EOT
      set -e
      
      # Decode and write kubeconfig files
      %{for name in var.cluster_names~}
      echo "$KUBECONFIG_${replace(name, "-", "_")}" | base64 -d > /tmp/kubeconfig-${name}
      %{endfor~}
      
      # Merge all kubeconfigs into one
      export KUBECONFIG="/tmp/kubeconfig-${local.first_cluster}:/tmp/kubeconfig-hetzner"
      kubectl config view --flatten > /tmp/kubeconfig-merged || true
      cat /tmp/kubeconfig-merged | head -30
      
      # Enable clustermesh on each cluster
      %{for name in var.cluster_names~}
      export KUBECONFIG=/tmp/kubeconfig-${name}
      cilium clustermesh enable --service-type NodePort
      %{endfor~}
      
      # Wait for clustermesh-apiserver to be ready
      for name in ${join(" ", var.cluster_names)}; do
        export KUBECONFIG=/tmp/kubeconfig-$name
        echo "Waiting for clustermesh-apiserver in cluster $name..."
        kubectl wait --for=condition=ready pod -l k8s-app=clustermesh-apiserver -n kube-system --timeout=300s
      done
      
      # Connect clusters using colon-separated kubeconfigs (both contexts available)
      export KUBECONFIG=/tmp/kubeconfig-gcp:/tmp/kubeconfig-hetzner
      kubectl config get-contexts -o name > /tmp/contexts.txt || true
      echo "Available contexts:"
      cat /tmp/contexts.txt
      SOURCE_CTX=$(head -n 1 /tmp/contexts.txt)
      DEST_CTX=$(tail -n 1 /tmp/contexts.txt)
      echo "Connecting $SOURCE_CTX -> $DEST_CTX"
      cilium clustermesh connect --context "$SOURCE_CTX" --destination-context "$DEST_CTX" --allow-mismatching-ca
      
      # Cleanup
      %{for name in var.cluster_names~}
      rm -f /tmp/kubeconfig-${name}
      %{endfor~}
      rm -f /tmp/kubeconfig-merged
    EOT
  }
}
