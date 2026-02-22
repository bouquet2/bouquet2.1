resource "null_resource" "worker_node_cleanup" {
  for_each = { for w in var.workers : w.name => w }

  triggers = {
    node_name  = "${var.cluster_name}-${each.key}"
    kubeconfig = var.kubeconfig
  }

  lifecycle {
    ignore_changes = [triggers["kubeconfig"]]
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      KUBECONFIG_FILE=$(mktemp)
      printf '%s' '${self.triggers.kubeconfig}' > "$KUBECONFIG_FILE"
      export KUBECONFIG="$KUBECONFIG_FILE"
      
      echo "Cleaning up node: ${self.triggers.node_name}"
      
      for i in 1 2 3; do
        if kubectl get node ${self.triggers.node_name} >/dev/null 2>&1; then
          echo "Node found, attempting cordon..."
          kubectl cordon ${self.triggers.node_name} 2>&1 || true
          
          echo "Attempting drain..."
          kubectl drain ${self.triggers.node_name} --ignore-daemonsets --delete-emptydir-data --force --grace-period=30 --timeout=90s 2>&1 || true
          
          echo "Deleting node..."
          kubectl delete node ${self.triggers.node_name} 2>&1 && break || true
        else
          echo "Node not found, skipping cleanup"
          break
        fi
        
        echo "Retry $i/3..."
        sleep 5
      done
      
      rm -f "$KUBECONFIG_FILE"
    EOT
  }
}

resource "null_resource" "control_plane_node_cleanup" {
  for_each = { for cp in var.control_planes : cp.name => cp }

  triggers = {
    node_name  = "${var.cluster_name}-${each.key}"
    kubeconfig = var.kubeconfig
  }

  lifecycle {
    ignore_changes = [triggers["kubeconfig"]]
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      KUBECONFIG_FILE=$(mktemp)
      printf '%s' '${self.triggers.kubeconfig}' > "$KUBECONFIG_FILE"
      export KUBECONFIG="$KUBECONFIG_FILE"
      
      echo "Cleaning up node: ${self.triggers.node_name}"
      
      for i in 1 2 3; do
        if kubectl get node ${self.triggers.node_name} >/dev/null 2>&1; then
          echo "Node found, attempting cordon..."
          kubectl cordon ${self.triggers.node_name} 2>&1 || true
          
          echo "Attempting drain..."
          kubectl drain ${self.triggers.node_name} --ignore-daemonsets --delete-emptydir-data --force --grace-period=30 --timeout=90s 2>&1 || true
          
          echo "Deleting node..."
          kubectl delete node ${self.triggers.node_name} 2>&1 && break || true
        else
          echo "Node not found, skipping cleanup"
          break
        fi
        
        echo "Retry $i/3..."
        sleep 5
      done
      
      rm -f "$KUBECONFIG_FILE"
    EOT
  }
}
