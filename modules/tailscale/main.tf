variable "tag" {
  type    = string
  default = "tag:k8s-operator"
}

variable "create_key_only" {
  type    = bool
  default = false
}

variable "clusters" {
  type = map(object({
    control_planes = list(object({ name = string }))
    workers        = list(object({ name = string }))
  }))
  default = {}
}

variable "gke_clusters" {
  type    = list(string)
  default = []
}

variable "cluster_install_complete" {
  type    = map(list(string))
  default = {}
}

variable "tailnet" {
  type    = string
  default = ""
}

variable "oauth_client_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "oauth_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "manage_acl" {
  type    = bool
  default = false
}

variable "acl_policy" {
  type    = string
  default = ""
}

resource "tailscale_acl" "k8s_operator" {
  count = var.manage_acl ? 1 : 0

  acl = coalesce(var.acl_policy, jsonencode({
    acls = [
      {
        action = "accept"
        src    = [var.tag]
        dst    = ["${var.tag}:*"]
      }
    ]
    tagOwners = {
      "tag:k8s-operator" = ["autogroup:admin"]
    }
  }))

  overwrite_existing_content = true
}

resource "tailscale_tailnet_key" "auth" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = [var.tag]
  expiry        = 3600
}

locals {
  talos_nodes = var.create_key_only ? {} : merge([
    for cluster_name, cluster in var.clusters : merge(
      { for cp in cluster.control_planes : "${cluster_name}-${cp.name}" => { cluster_name = cluster_name, node_name = cp.name, is_gke = false } },
      { for w in cluster.workers : "${cluster_name}-${w.name}" => { cluster_name = cluster_name, node_name = w.name, is_gke = false } }
    )
    if !contains(var.gke_clusters, cluster_name)
  ]...)

  gke_connectors = var.create_key_only ? {} : {
    for cluster_name in var.gke_clusters : "${cluster_name}-connector" => {
      cluster_name = cluster_name
      node_name    = "connector"
      is_gke       = true
    }
  }

  all_devices = merge(local.talos_nodes, local.gke_connectors)
}

data "tailscale_device" "nodes" {
  for_each = local.all_devices

  hostname   = each.key
  wait_for   = "60s"
  depends_on = [var.cluster_install_complete]
}

locals {
  node_ips = var.create_key_only ? {} : {
    for name, device in data.tailscale_device.nodes : device.hostname => split("/", device.addresses[0])[0]
  }

  cluster_node_ips = var.create_key_only ? {} : {
    for cluster_name, cluster in var.clusters : cluster_name => merge(
      { for cp in cluster.control_planes : "${cluster_name}-${cp.name}" => split("/", data.tailscale_device.nodes["${cluster_name}-${cp.name}"].addresses[0])[0] if !contains(var.gke_clusters, cluster_name) },
      { for w in cluster.workers : "${cluster_name}-${w.name}" => split("/", data.tailscale_device.nodes["${cluster_name}-${w.name}"].addresses[0])[0] if !contains(var.gke_clusters, cluster_name) },
      contains(var.gke_clusters, cluster_name) ? { "${cluster_name}-connector" = split("/", data.tailscale_device.nodes["${cluster_name}-connector"].addresses[0])[0] } : {}
    )
  }
}

resource "null_resource" "device_cleanup" {
  for_each = var.create_key_only ? {} : local.all_devices

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      TOKEN=$(curl -s -X POST "https://api.tailscale.com/api/v2/oauth/token" \
        -d "client_id=${self.triggers.oauth_client_id}" \
        -d "client_secret=${self.triggers.oauth_client_secret}" \
        -d "grant_type=client_credentials" | jq -r '.access_token')
      
      DEVICE_ID=$(curl -s "https://api.tailscale.com/api/v2/tailnet/${self.triggers.tailnet}/devices" \
        -H "Authorization: Bearer $TOKEN" | jq -r '.devices[] | select(.hostname == "${self.triggers.node_name}") | .id')
      
      if [ -n "$DEVICE_ID" ]; then
        curl -s -X DELETE "https://api.tailscale.com/api/v2/device/$DEVICE_ID" \
          -H "Authorization: Bearer $TOKEN" || true
      fi
    EOT
  }

  triggers = {
    node_name           = each.key
    tailnet             = var.tailnet
    oauth_client_id     = var.oauth_client_id
    oauth_client_secret = var.oauth_client_secret
  }
}

output "auth_key" {
  value     = tailscale_tailnet_key.auth.key
  sensitive = true
}

output "all_node_ips" {
  value = local.node_ips
}

output "cluster_node_ips" {
  value = local.cluster_node_ips
}
