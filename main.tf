provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_secret
  tailnet             = var.tailscale.tailnet
}

provider "google" {
  project     = local.gcp_project_id
  region      = local.gcp_region
  zone        = local.gcp_zone
  credentials = var.gcp_credentials != "" ? var.gcp_credentials : null
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

variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth client ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gcp_credentials" {
  description = "GCP service account credentials JSON (empty for ADC)"
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

  gcp_project_id = length([for k, v in var.clusters : v.gcp.project_id if try(v.gcp.project_id, "") != ""]) > 0 ? values(var.clusters)[0].gcp.project_id : ""
  gcp_region     = length([for k, v in var.clusters : v.gcp.region if try(v.gcp.region, "") != ""]) > 0 ? values(var.clusters)[0].gcp.region : ""
  gcp_zone       = length([for k, v in var.clusters : v.gcp.zone if try(v.gcp.zone, "") != ""]) > 0 ? values(var.clusters)[0].gcp.zone : ""
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
  source   = "./modules/talos"
  for_each = var.clusters

  cluster_name       = each.key
  cluster_id         = each.value.cluster_id
  talos_version      = local.talos_version
  kubernetes_version = local.kubernetes_version
  control_planes     = each.value.control_planes
  workers            = each.value.workers
  network            = var.network
  cilium             = var.cilium

  tailscale_enabled  = var.tailscale.enabled
  tailscale_auth_key = var.tailscale.enabled ? module.tailscale_key[0].auth_key : ""
  tailscale_routes   = var.tailscale.enabled ? var.tailscale.routes : []

  dns_enabled = var.dns.enabled
  dns_domain  = var.dns.domain
}

locals {
  cluster_hetzner_nodes = {
    for k, v in var.clusters : k => {
      control_planes = [for cp in v.control_planes : cp if cp.provider == "hetzner"]
      workers        = [for w in v.workers : w if w.provider == "hetzner"]
    }
  }

  cluster_gcp_nodes = {
    for k, v in var.clusters : k => {
      control_planes = [for cp in v.control_planes : cp if cp.provider == "gcp"]
      workers        = [for w in v.workers : w if w.provider == "gcp"]
      gcp_config     = try(v.gcp, {})
    }
  }
}

module "hetzner" {
  source   = "./modules/providers/hetzner"
  for_each = { for k, v in local.cluster_hetzner_nodes : k => v if length(v.control_planes) > 0 || length(v.workers) > 0 }

  cluster_name          = each.key
  control_planes        = each.value.control_planes
  workers               = each.value.workers
  ssh_public_key        = tls_private_key.ssh.public_key_openssh
  ssh_private_key       = tls_private_key.ssh.private_key_openssh
  talos_version         = local.talos_version
  hcloud_token          = var.hcloud_token
  control_plane_configs = { for cp in each.value.control_planes : cp.name => module.talos[each.key].control_plane_configs[cp.name] }
  worker_configs        = { for w in each.value.workers : w.name => module.talos[each.key].worker_configs[w.name] }
}

module "gcp" {
  source   = "./modules/providers/gcp"
  for_each = { for k, v in local.cluster_gcp_nodes : k => v if length(v.control_planes) > 0 || length(v.workers) > 0 }

  project_id            = each.value.gcp_config.project_id
  region                = each.value.gcp_config.region
  zone                  = each.value.gcp_config.zone
  network               = try(each.value.gcp_config.network, "default")
  subnetwork            = try(each.value.gcp_config.subnetwork, "")
  gcs_bucket            = try(each.value.gcp_config.gcs_bucket, "")
  cluster_name          = each.key
  control_planes        = each.value.control_planes
  workers               = each.value.workers
  talos_version         = local.talos_version
  ssh_public_key        = tls_private_key.ssh.public_key_openssh
  control_plane_configs = { for cp in each.value.control_planes : cp.name => module.talos[each.key].control_plane_configs[cp.name] }
  worker_configs        = { for w in each.value.workers : w.name => module.talos[each.key].worker_configs[w.name] }
}

locals {
  cluster_control_plane_ips = {
    for cluster_name, cluster in var.clusters : cluster_name => merge(
      length(local.cluster_hetzner_nodes[cluster_name].control_planes) > 0 ? module.hetzner[cluster_name].control_plane_ips : {},
      length(local.cluster_gcp_nodes[cluster_name].control_planes) > 0 ? module.gcp[cluster_name].control_plane_ips : {}
    )
  }

  cluster_worker_ips = {
    for cluster_name, cluster in var.clusters : cluster_name => merge(
      length(local.cluster_hetzner_nodes[cluster_name].workers) > 0 ? module.hetzner[cluster_name].worker_ips : {},
      length(local.cluster_gcp_nodes[cluster_name].workers) > 0 ? module.gcp[cluster_name].worker_ips : {}
    )
  }

  cluster_install_complete = {
    for cluster_name, cluster in var.clusters : cluster_name => concat(
      length(local.cluster_hetzner_nodes[cluster_name].control_planes) > 0 || length(local.cluster_hetzner_nodes[cluster_name].workers) > 0 ? module.hetzner[cluster_name].install_complete : [],
      length(local.cluster_gcp_nodes[cluster_name].control_planes) > 0 || length(local.cluster_gcp_nodes[cluster_name].workers) > 0 ? module.gcp[cluster_name].install_complete : []
    )
  }

  all_control_plane_ips = merge(values(local.cluster_control_plane_ips)...)
  all_worker_ips        = merge(values(local.cluster_worker_ips)...)
}

resource "talos_machine_bootstrap" "this" {
  for_each = { for k, v in var.clusters : k => v if length(v.control_planes) > 0 }

  client_configuration = module.talos[each.key].client_configuration
  node                 = values(local.cluster_control_plane_ips[each.key])[0]
  endpoint             = values(local.cluster_control_plane_ips[each.key])[0]

  depends_on = [module.hetzner, module.gcp]
}

resource "talos_machine_configuration_apply" "control_plane" {
  for_each = merge([
    for cluster_name, cluster in var.clusters : {
      for cp in cluster.control_planes : "${cluster_name}-${cp.name}" => {
        cluster_name = cluster_name
        node_name    = cp.name
      }
    }
  ]...)

  client_configuration        = module.talos[each.value.cluster_name].client_configuration
  machine_configuration_input = module.talos[each.value.cluster_name].control_plane_configs[each.value.node_name]
  node                        = local.cluster_control_plane_ips[each.value.cluster_name][each.value.node_name]
  endpoint                    = local.cluster_control_plane_ips[each.value.cluster_name][each.value.node_name]

  depends_on = [talos_machine_bootstrap.this]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = merge([
    for cluster_name, cluster in var.clusters : {
      for w in cluster.workers : "${cluster_name}-${w.name}" => {
        cluster_name = cluster_name
        node_name    = w.name
      }
    }
  ]...)

  client_configuration        = module.talos[each.value.cluster_name].client_configuration
  machine_configuration_input = module.talos[each.value.cluster_name].worker_configs[each.value.node_name]
  node                        = local.cluster_worker_ips[each.value.cluster_name][each.value.node_name]
  endpoint                    = local.cluster_worker_ips[each.value.cluster_name][each.value.node_name]

  depends_on = [talos_machine_configuration_apply.control_plane]
}

resource "talos_cluster_kubeconfig" "this" {
  for_each = { for k, v in var.clusters : k => v if length(v.control_planes) > 0 }

  client_configuration = module.talos[each.key].client_configuration
  node                 = values(local.cluster_control_plane_ips[each.key])[0]
  endpoint             = values(local.cluster_control_plane_ips[each.key])[0]

  depends_on = [talos_machine_configuration_apply.control_plane]
}

data "talos_client_configuration" "this" {
  for_each = var.clusters

  cluster_name         = each.key
  client_configuration = module.talos[each.key].client_configuration
  endpoints            = var.tailscale.enabled ? values(module.tailscale_devices[0].cluster_node_ips[each.key]) : values(local.cluster_control_plane_ips[each.key])
  nodes                = var.tailscale.enabled ? values(module.tailscale_devices[0].cluster_node_ips[each.key]) : concat(values(local.cluster_control_plane_ips[each.key]), values(local.cluster_worker_ips[each.key]))
}

module "k8s_cleanup" {
  source   = "./modules/k8s"
  for_each = var.clusters

  cluster_name   = each.key
  workers        = each.value.workers
  control_planes = each.value.control_planes
  kubeconfig     = length(each.value.control_planes) > 0 ? talos_cluster_kubeconfig.this[each.key].kubeconfig_raw : ""
}

module "tailscale_devices" {
  source = "./modules/tailscale"
  count  = var.tailscale.enabled ? 1 : 0

  clusters            = { for k, v in var.clusters : k => { control_planes = v.control_planes, workers = v.workers } }
  cluster_install_complete = local.cluster_install_complete
  tag                 = var.tailscale.tag
  tailnet             = var.tailscale.tailnet
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_secret
  manage_acl          = var.tailscale.manage_acl
  acl_policy          = var.tailscale.acl_policy
}

module "dns" {
  source = "./modules/dns"
  count  = var.dns.enabled ? 1 : 0

  domain                  = var.dns.domain
  internal_domain         = var.dns.internal_domain
  cluster_names           = keys(var.clusters)
  cluster_control_plane_ips = local.cluster_control_plane_ips
  cluster_worker_ips      = local.cluster_worker_ips
  tailscale_ips           = var.tailscale.enabled ? module.tailscale_devices[0].all_node_ips : {}

  depends_on = [talos_machine_bootstrap.this]
}

module "clustermesh" {
  source = "./modules/clustermesh"
  count  = var.cilium.clustermesh && length(var.clusters) > 1 ? 1 : 0

  cluster_names       = keys(var.clusters)
  cluster_ids         = { for k, v in var.clusters : k => v.cluster_id }
  kubeconfigs         = { for k, v in var.clusters : k => talos_cluster_kubeconfig.this[k].kubeconfig_raw }
  control_plane_ips   = local.cluster_control_plane_ips

  depends_on = [talos_cluster_kubeconfig.this, talos_machine_configuration_apply.control_plane]
}
