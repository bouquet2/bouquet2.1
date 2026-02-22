variable "tag" {
  type    = string
  default = "tag:k8s-operator"
}

variable "create_key_only" {
  type    = bool
  default = false
}

variable "cluster_name" {
  type    = string
  default = ""
}

variable "routes" {
  type    = list(string)
  default = []
}

variable "control_planes" {
  type = list(object({
    name = string
  }))
  default = []
}

variable "workers" {
  type = list(object({
    name = string
  }))
  default = []
}

variable "install_complete" {
  type    = list(string)
  default = []
}

variable "tailnet" {
  type    = string
  default = ""
}

variable "oauth_client_id" {
  type    = string
  default = ""
}

variable "oauth_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

resource "tailscale_tailnet_key" "auth" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = [var.tag]
  expiry        = 3600
}

data "tailscale_device" "control_planes" {
  for_each = var.create_key_only ? {} : { for cp in var.control_planes : cp.name => cp }

  hostname = "${var.cluster_name}-${each.key}"
  wait_for = "60s"

  depends_on = [var.install_complete]
}

data "tailscale_device" "workers" {
  for_each = var.create_key_only ? {} : { for w in var.workers : w.name => w }

  hostname = "${var.cluster_name}-${each.key}"
  wait_for = "60s"

  depends_on = [var.install_complete]
}

locals {
  node_ips = var.create_key_only ? {} : merge(
    { for name, device in data.tailscale_device.control_planes : device.hostname => split("/", device.addresses[0])[0] },
    { for name, device in data.tailscale_device.workers : device.hostname => split("/", device.addresses[0])[0] }
  )
}

resource "null_resource" "device_cleanup" {
  for_each = var.create_key_only ? {} : merge(
    { for k, d in data.tailscale_device.control_planes : k => d },
    { for k, d in data.tailscale_device.workers : k => d }
  )

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
    node_name           = "${var.cluster_name}-${each.key}"
    tailnet             = var.tailnet
    oauth_client_id     = var.oauth_client_id
    oauth_client_secret = var.oauth_client_secret
  }
}

output "auth_key" {
  value     = tailscale_tailnet_key.auth.key
  sensitive = true
}

output "node_ips" {
  value = local.node_ips
}
