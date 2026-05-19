variable "cluster_names" {
  type = list(string)
}

variable "kubeconfig_paths" {
  type = map(string)
  description = "Map of cluster name to kubeconfig file path (from infra module output)"
  default     = {}
}

variable "control_plane_tailscale_ips" {
  type        = map(string)
  description = "Map of cluster name to a control plane Tailscale IP, used to patch kubeconfig server URLs"
  default     = {}
}

locals {
  hub_cluster      = var.cluster_names[0]
  spoke_clusters   = slice(var.cluster_names, 1, length(var.cluster_names))
  kubeconfig_paths = join(":", [for name in var.cluster_names : "/tmp/kubeconfig-${name}"])

  kubeconfig_raw = { for name, path in var.kubeconfig_paths : name => path != "" ? try(file(path), "") : "" }
}

resource "null_resource" "clustermesh_connect" {
  count = length(var.cluster_names) > 1 ? 1 : 0

  triggers = {
    clusters     = join(",", var.cluster_names)
    kubeconfigs  = sha256(join("", [for name in var.cluster_names : sha256(local.kubeconfig_raw[name])]))
    script_ver   = "8"
  }

  provisioner "local-exec" {
    environment = merge(
      { for name, ip in var.control_plane_tailscale_ips : "TAILSCALE_IP_${replace(name, "-", "_")}" => ip },
      { PATH = "/opt/homebrew/bin:/etc/profiles/per-user/kreato/bin:/usr/local/bin:/usr/bin:/bin" }
    )
    command = <<-EOT
      set -e

      wait_for_cmd() {
        name="$1"
        tries="$2"
        delay="$3"
        shift 3
        for i in $(seq 1 "$tries"); do
          if "$@" >/dev/null 2>&1; then
            return 0
          fi
          echo "[$name] not ready yet ($i/$tries)"
          sleep "$delay"
        done
        echo "Timed out waiting for $name" >&2
        return 1
      }

      wait_for_resource_exists() {
        name="$1"
        tries="$2"
        delay="$3"
        shift 3
        wait_for_cmd "$name" "$tries" "$delay" "$@"
      }

      wait_for_resource_ready() {
        name="$1"
        tries="$2"
        delay="$3"
        shift 3
        wait_for_cmd "$name" "$tries" "$delay" "$@"
      }
      
      # Copy kubeconfigs from file paths, patching server URL and renaming context to cluster name
      %{for name in var.cluster_names~}
      %{if var.kubeconfig_paths[name] != ""~}
      cp "${var.kubeconfig_paths[name]}" /tmp/kubeconfig-${name}
      if [ -n "$${TAILSCALE_IP_${replace(name, "-", "_")}:-}" ]; then
        TAIL_IP="$${TAILSCALE_IP_${replace(name, "-", "_")}}"
        sed -i.bak "s|https://[^:]*:6443|https://$${TAIL_IP}:6443|g" /tmp/kubeconfig-${name}
        rm -f /tmp/kubeconfig-${name}.bak
      fi
      export KUBECONFIG=/tmp/kubeconfig-${name}
      OLD_CTX=$(kubectl config current-context)
      kubectl config rename-context "$${OLD_CTX}" ${name} 2>/dev/null || true
      %{endif~}
      %{endfor~}
      
      # Exit early if no kubeconfigs were available
      if ! ls /tmp/kubeconfig-* >/dev/null 2>&1; then
        echo "No kubeconfigs available, skipping cluster connectivity checks."
        exit 0
      fi

      # Merge all kubeconfigs into one
      export KUBECONFIG="${local.kubeconfig_paths}"
      kubectl config view --flatten > /tmp/kubeconfig-merged
      
      # Wait for each cluster to be accessible
      %{for name in var.cluster_names~}
      %{if var.kubeconfig_paths[name] != ""~}
      export KUBECONFIG=/tmp/kubeconfig-${name}
      echo "Waiting for cluster ${name}..."
      wait_for_cmd "cluster ${name} API" 60 10 kubectl get ns default
      %{endif~}
      %{endfor~}

      # Wait for Cilium to be ready on each cluster
      %{for name in var.cluster_names~}
      %{if var.kubeconfig_paths[name] != ""~}
      export KUBECONFIG=/tmp/kubeconfig-${name}
      echo "Waiting for helm-install-cilium job on ${name}..."
      wait_for_resource_exists "helm-install-cilium job on ${name}" 60 10 \
        kubectl get job helm-install-cilium -n kube-system
      wait_for_resource_ready "helm-install-cilium completion on ${name}" 60 10 \
        kubectl wait --for=condition=complete job/helm-install-cilium -n kube-system --timeout=10s
      echo "Waiting for Cilium agent on ${name}..."
      wait_for_resource_exists "cilium pods on ${name}" 60 10 \
        kubectl get pods -n kube-system -l k8s-app=cilium
      wait_for_resource_ready "cilium pods ready on ${name}" 60 10 \
        kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=10s
      %{endif~}
      %{endfor~}

      # Wait for clustermesh-apiserver to be ready on each cluster
      %{for name in var.cluster_names~}
      %{if var.kubeconfig_paths[name] != ""~}
      export KUBECONFIG=/tmp/kubeconfig-${name}
      echo "Waiting for clustermesh-apiserver on ${name}..."
      wait_for_resource_exists "clustermesh-apiserver pods on ${name}" 60 10 \
        kubectl get pods -n kube-system -l k8s-app=clustermesh-apiserver
      wait_for_resource_ready "clustermesh-apiserver ready on ${name}" 60 10 \
        kubectl wait --for=condition=ready pod -l k8s-app=clustermesh-apiserver -n kube-system --timeout=10s
      %{endif~}
      %{endfor~}
      
      # Connect all clusters using hub model
      export KUBECONFIG=/tmp/kubeconfig-merged
      HUB="${local.hub_cluster}"
      %{for name in local.spoke_clusters~}
      echo "Connecting $${HUB} <-> ${name}..."
      SRC_EP="$${TAILSCALE_IP_${replace(local.hub_cluster, "-", "_")}:-}"
      DST_EP="$${TAILSCALE_IP_${replace(name, "-", "_")}:-}"
      if [ -n "$${SRC_EP}" ] && [ -n "$${DST_EP}" ]; then
        cilium clustermesh connect --context "$${HUB}" --destination-context "${name}" --allow-mismatching-ca \
          --source-endpoint "$${SRC_EP}:32379" --destination-endpoint "$${DST_EP}:32379"
      else
        cilium clustermesh connect --context "$${HUB}" --destination-context "${name}" --allow-mismatching-ca
      fi
      %{endfor~}
      
      # Cleanup
      %{for name in var.cluster_names~}
      rm -f /tmp/kubeconfig-${name}
      %{endfor~}
      rm -f /tmp/kubeconfig-merged
    EOT
  }
}
