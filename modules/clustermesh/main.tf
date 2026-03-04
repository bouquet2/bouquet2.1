variable "cluster_names" {
  type = list(string)
}

variable "kubeconfigs" {
  type      = map(string)
  sensitive = true
}

variable "control_plane_tailscale_ips" {
  type        = map(string)
  description = "Map of cluster name to control plane Tailscale IP, used to patch kubeconfig server URLs for local DNS resolution."
  default     = {}
}

locals {
  first_cluster = var.cluster_names[0]
  kubeconfig_paths = join(":", [for name in var.cluster_names : "/tmp/kubeconfig-${name}"])
}

resource "null_resource" "clustermesh_connect" {
  count = length(var.cluster_names) > 1 ? 1 : 0

  triggers = {
    clusters     = join(",", var.cluster_names)
    kubeconfigs  = sha256(join("", [for name in var.cluster_names : sha256(var.kubeconfigs[name])]))
    script_ver   = "5"  # Bump this when changing the script
  }

  provisioner "local-exec" {
    environment = merge(
      { for name in var.cluster_names : "KUBECONFIG_${replace(name, "-", "_")}" => base64encode(var.kubeconfigs[name]) },
      { for name, ip in var.control_plane_tailscale_ips : "TAILSCALE_IP_${replace(name, "-", "_")}" => ip },
      { PATH = "/opt/homebrew/bin:/etc/profiles/per-user/kreato/bin:/usr/local/bin:/usr/bin:/bin" }
    )
    command = <<-EOT
      set -e
      
      # Decode and write kubeconfig files, patching server URL and renaming context to cluster name
      %{for name in var.cluster_names~}
      echo "$${KUBECONFIG_${replace(name, "-", "_")}}" | base64 -d > /tmp/kubeconfig-${name}
      if [ -n "$${TAILSCALE_IP_${replace(name, "-", "_")}:-}" ]; then
        sed -i.bak "s|https://[^:]*:6443|https://$${TAILSCALE_IP_${replace(name, "-", "_")}}:6443|g" /tmp/kubeconfig-${name}
        rm -f /tmp/kubeconfig-${name}.bak
      fi
      # Rename context/cluster/user to the cluster name so cilium can find it by name
      export KUBECONFIG=/tmp/kubeconfig-${name}
      OLD_CTX=$(kubectl config current-context)
      kubectl config rename-context "$${OLD_CTX}" ${name} 2>/dev/null || true
      %{endfor~}
      
      # Merge all kubeconfigs into one
      export KUBECONFIG="${local.kubeconfig_paths}"
      kubectl config view --flatten > /tmp/kubeconfig-merged
      
      # Wait for each cluster to be accessible
      %{for name in var.cluster_names~}
      export KUBECONFIG=/tmp/kubeconfig-${name}
      echo "Waiting for cluster ${name}..."
      for i in $(seq 1 30); do
        kubectl get ns default >/dev/null 2>&1 && break
        sleep 10
      done
      %{endfor~}

      # Wait for Cilium to be ready on each cluster (helm-install-cilium Job must complete first)
      %{for name in var.cluster_names~}
      export KUBECONFIG=/tmp/kubeconfig-${name}
      echo "Waiting for helm-install-cilium job on ${name}..."
      kubectl wait --for=condition=complete job/helm-install-cilium -n kube-system --timeout=600s || true
      echo "Waiting for Cilium agent on ${name}..."
      kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s
      %{endfor~}

      # Wait for clustermesh-apiserver to be ready on each cluster
      %{for name in var.cluster_names~}
      export KUBECONFIG=/tmp/kubeconfig-${name}
      echo "Waiting for clustermesh-apiserver on ${name}..."
      kubectl wait --for=condition=ready pod -l k8s-app=clustermesh-apiserver -n kube-system --timeout=300s
      %{endfor~}
      
      # Connect clusters
      export KUBECONFIG=/tmp/kubeconfig-merged
      CTX1="${var.cluster_names[0]}"
      CTX2="${var.cluster_names[1]}"
      echo "Connecting $${CTX1} <-> $${CTX2}..."
      cilium clustermesh connect --context "$${CTX1}" --destination-context "$${CTX2}" --allow-mismatching-ca
      
      # Cleanup
      %{for name in var.cluster_names~}
      rm -f /tmp/kubeconfig-${name}
      %{endfor~}
      rm -f /tmp/kubeconfig-merged
    EOT
  }
}
