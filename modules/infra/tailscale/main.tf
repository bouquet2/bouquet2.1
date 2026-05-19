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
      { for cp in cluster.control_planes : "${cluster_name}-${cp.name}" => { cluster_name = cluster_name, node_name = cp.name } },
      { for w in cluster.workers : "${cluster_name}-${w.name}" => { cluster_name = cluster_name, node_name = w.name } }
    )
  ]...)

  all_devices = local.talos_nodes
}

resource "null_resource" "cluster_ready" {
  count = local.talos_nodes != {} ? 1 : 0

  triggers = {
    install_complete = jsonencode(var.cluster_install_complete)
  }
}

data "external" "tailscale_devices" {
  count      = local.talos_nodes != {} ? 1 : 0
  depends_on = [null_resource.cluster_ready]

  program = ["bash", "-c", <<-EOT
    set -euo pipefail
    EXPECTED_JSON='${jsonencode(keys(local.all_devices))}'
    TAILNET='${var.tailnet}'
    CLIENT_ID='${var.oauth_client_id}'
    CLIENT_SECRET='${var.oauth_client_secret}'
    TOKEN_DEADLINE=0

    get_token() {
      if [ "$SECONDS" -lt "$TOKEN_DEADLINE" ] && [ -n "$${TOKEN:-}" ]; then
        return
      fi
      local resp
      resp=$(curl -sf -X POST "https://api.tailscale.com/api/v2/oauth/token" \
        -d "client_id=$CLIENT_ID" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "grant_type=client_credentials")
      TOKEN=$(echo "$resp" | jq -r '.access_token')
      local expires_in
      expires_in=$(echo "$resp" | jq -r '.expires_in // 3600')
      TOKEN_DEADLINE=$(( SECONDS + expires_in - 60 ))
    }

    EXPECTED_COUNT=$(echo "$EXPECTED_JSON" | jq 'length')
    DEADLINE=$((SECONDS + 120))
    RESULT="{}"
    FIRST_POLL=true

    while [ $SECONDS -lt $DEADLINE ]; do
      if [ "$FIRST_POLL" = true ]; then
        FIRST_POLL=false
      else
        sleep 5
      fi
      get_token
      RESULT=$(curl -sf "https://api.tailscale.com/api/v2/tailnet/$TAILNET/devices" \
        -H "Authorization: Bearer $TOKEN" | jq -c --argjson names "$EXPECTED_JSON" '
          [.devices[] | select(.hostname as $h | $names | index($h))] |
          reduce .[] as $d ({}; .[$d.hostname] = $d.addresses[0])
        ')
      FOUND_COUNT=$(echo "$RESULT" | jq 'length')
      if [ "$FOUND_COUNT" -eq "$EXPECTED_COUNT" ]; then
        echo "$RESULT"
        exit 0
      fi
    done
    echo "$RESULT"
  EOT
  ]
}

locals {
  node_ips = var.create_key_only ? {} : (
    length(data.external.tailscale_devices) > 0 ? data.external.tailscale_devices[0].result : {}
  )

  cluster_node_ips = var.create_key_only ? {} : {
    for cluster_name, cluster in var.clusters : cluster_name => merge(
      { for cp in cluster.control_planes : "${cluster_name}-${cp.name}" => try(local.node_ips["${cluster_name}-${cp.name}"], null) },
      { for w in cluster.workers : "${cluster_name}-${w.name}" => try(local.node_ips["${cluster_name}-${w.name}"], null) }
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
