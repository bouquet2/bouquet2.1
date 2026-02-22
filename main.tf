provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "tailscale" {
  oauth_client_id     = var.tailscale.oauth_client_id
  oauth_client_secret = var.tailscale_oauth_secret
  tailnet             = var.tailscale.tailnet
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_secret" {
  description = "Tailscale OAuth client secret"
  type        = string
  sensitive   = true
  default     = ""
}

data "http" "talos_latest_release" {
  count = var.talos_version == null ? 1 : 0
  url   = "https://api.github.com/repos/siderolabs/talos/releases/latest"
}

data "http" "kubelet_latest_release" {
  count = var.kubernetes_version == null ? 1 : 0
  url   = "https://api.github.com/repos/siderolabs/kubelet/releases/latest"
}

resource "terraform_data" "talos_version" {
  count = var.talos_version == null ? 1 : 0
  input = jsondecode(data.http.talos_latest_release[0].response_body).tag_name
  lifecycle {
    ignore_changes = [input]
  }
}

resource "terraform_data" "kubernetes_version" {
  count = var.kubernetes_version == null ? 1 : 0
  input = jsondecode(data.http.kubelet_latest_release[0].response_body).tag_name
  lifecycle {
    ignore_changes = [input]
  }
}

locals {
  talos_version      = coalesce(var.talos_version, terraform_data.talos_version[0].input)
  kubernetes_version = coalesce(var.kubernetes_version, terraform_data.kubernetes_version[0].input)
}

resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

module "tailscale_key" {
  source = "./modules/tailscale"
  count  = var.tailscale.enabled ? 1 : 0

  create_key_only = true
  tag             = var.tailscale.tag
}

module "talos" {
  source = "./modules/talos"

  cluster_name       = var.cluster_name
  talos_version      = local.talos_version
  kubernetes_version = local.kubernetes_version
  control_planes     = var.control_planes
  workers            = var.workers
  network            = var.network
  cilium             = var.cilium

  tailscale_enabled  = var.tailscale.enabled
  tailscale_auth_key = var.tailscale.enabled ? module.tailscale_key[0].auth_key : ""
  tailscale_routes   = var.tailscale.enabled ? var.tailscale.routes : []

  dns_enabled = var.dns.enabled
  dns_domain  = var.dns.domain
}

module "hetzner" {
  source = "./modules/hetzner"

  cluster_name          = var.cluster_name
  control_planes        = var.control_planes
  workers               = var.workers
  ssh_public_key        = tls_private_key.ssh.public_key_openssh
  ssh_private_key       = tls_private_key.ssh.private_key_openssh
  talos_version         = local.talos_version
  hcloud_token          = var.hcloud_token
  control_plane_configs = module.talos.control_plane_configs
  worker_configs        = module.talos.worker_configs
}

resource "talos_machine_bootstrap" "this" {
  count = length(var.control_planes) > 0 ? 1 : 0

  client_configuration = module.talos.client_configuration
  node                 = values(module.hetzner.control_plane_ips)[0]
  endpoint             = values(module.hetzner.control_plane_ips)[0]

  depends_on = [module.hetzner]
}

resource "talos_machine_configuration_apply" "control_plane" {
  for_each = { for cp in var.control_planes : cp.name => cp }

  client_configuration        = module.talos.client_configuration
  machine_configuration_input = module.talos.control_plane_configs[each.key]
  node                        = module.hetzner.control_plane_ips[each.key]
  endpoint                    = module.hetzner.control_plane_ips[each.key]

  depends_on = [talos_machine_bootstrap.this]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = { for w in var.workers : w.name => w }

  client_configuration        = module.talos.client_configuration
  machine_configuration_input = module.talos.worker_configs[each.key]
  node                        = module.hetzner.worker_ips[each.key]
  endpoint                    = module.hetzner.worker_ips[each.key]

  depends_on = [talos_machine_configuration_apply.control_plane]
}

resource "talos_cluster_kubeconfig" "this" {
  count = length(var.control_planes) > 0 ? 1 : 0

  client_configuration = module.talos.client_configuration
  node                 = values(module.hetzner.control_plane_ips)[0]
  endpoint             = values(module.hetzner.control_plane_ips)[0]

  depends_on = [talos_machine_configuration_apply.control_plane]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = module.talos.client_configuration
  endpoints            = var.tailscale.enabled ? values(module.tailscale_devices[0].node_ips) : values(module.hetzner.control_plane_ips)
  nodes                = var.tailscale.enabled ? values(module.tailscale_devices[0].node_ips) : concat(values(module.hetzner.control_plane_ips), values(module.hetzner.worker_ips))
}

module "k8s_cleanup" {
  source = "./modules/k8s"

  cluster_name   = var.cluster_name
  workers        = var.workers
  control_planes = var.control_planes
  kubeconfig     = length(var.control_planes) > 0 ? talos_cluster_kubeconfig.this[0].kubeconfig_raw : ""
}

module "tailscale_devices" {
  source = "./modules/tailscale"
  count  = var.tailscale.enabled ? 1 : 0

  cluster_name        = var.cluster_name
  control_planes      = var.control_planes
  workers             = var.workers
  install_complete    = module.hetzner.install_complete
  tag                 = var.tailscale.tag
  tailnet             = var.tailscale.tailnet
  oauth_client_id     = var.tailscale.oauth_client_id
  oauth_client_secret = var.tailscale_oauth_secret
}

module "dns" {
  source = "./modules/dns"
  count  = var.dns.enabled ? 1 : 0

  domain            = var.dns.domain
  internal_domain   = var.dns.internal_domain
  cluster_name      = var.cluster_name
  control_planes    = var.control_planes
  workers           = var.workers
  control_plane_ips = module.hetzner.control_plane_ips
  worker_ips        = module.hetzner.worker_ips
  tailscale_ips     = var.tailscale.enabled ? module.tailscale_devices[0].node_ips : {}

  depends_on = [talos_machine_bootstrap.this]
}
