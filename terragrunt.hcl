terraform {
  extra_arguments "config" {
    commands = get_terraform_commands_that_need_vars()

    required_var_files = [
      "${get_terragrunt_dir()}/${local.cfg_file}",
    ]

    optional_var_files = [
      "${get_terragrunt_dir()}/secrets.tfvars",
    ]
  }
}

locals {
  # B_CFG selects which config file to read. Defaults to config.json.
  # Usage: B_CFG=config2.json terragrunt plan
  cfg_file = get_env("B_CFG", "config.json")
  tfvars   = try(jsondecode(file(local.cfg_file)), {})

  enable_onepassword = try(local.tfvars.enable_onepassword, false)
  onepassword_account = try(local.tfvars.onepassword_account, "")

  clusters = try(local.tfvars.clusters, {})

  # Detect whether any cluster has a GCP block (Talos-on-GCP or GKE)
  has_gcp = anytrue([
    for _, cluster in local.clusters :
    try(cluster.gcp.project_id, "") != ""
  ])

  # Derive GCP settings from first cluster that has them (all GCP clusters
  # share the same project/region/zone in this project layout)
  gcp_clusters = [for _, c in local.clusters : c if try(c.gcp.project_id, "") != ""]
  gcp_project  = length(local.gcp_clusters) > 0 ? local.gcp_clusters[0].gcp.project_id : ""
  gcp_region   = length(local.gcp_clusters) > 0 ? local.gcp_clusters[0].gcp.region : ""
  gcp_zone     = length(local.gcp_clusters) > 0 ? local.gcp_clusters[0].gcp.zone : ""
}

# Generate GCP provider, modules, and output-aggregating locals only when needed.
# When has_gcp = false, only empty locals are emitted — no Google provider required.
generate "required_providers" {
  path      = "required_providers_generated.tf"
  if_exists = "overwrite"

  contents = <<-EOF
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.6"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.16"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.2"
    }
%{if local.has_gcp}
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
%{endif}
  }
}
EOF
}

generate "gcp_modules" {
  path      = "gcp_modules.tf"
  if_exists = "overwrite"

  contents = <<-EOF
%{if local.has_gcp}
provider "google" {
  project = "${local.gcp_project}"
  region  = "${local.gcp_region}"
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

  ceph_disk = try(each.value.gcp_config.ceph_disk, {})
}

module "gke" {
  source   = "./modules/providers/gcp/gke"
  for_each = local.gke_clusters

  cluster_name               = each.key
  cluster_id                 = each.value.cluster_id
  project_id                 = each.value.gcp.project_id
  region                     = each.value.gcp.region
  zone                       = each.value.gcp.zone
  network                    = try(each.value.gcp.network, "default")
  subnetwork                 = try(each.value.gcp.subnetwork, "")
  node_pools                 = try(each.value.gcp.node_pools, [])
  pod_cidr                   = try(each.value.gcp.pod_cidr, "")
  services_cidr              = try(each.value.gcp.services_cidr, "")
  master_ipv4_cidr_block     = try(each.value.gcp.master_ipv4_cidr_block, "172.16.0.0/28")
  enable_private_cluster     = try(each.value.gcp.enable_private_cluster, true)
  master_authorized_networks = try(each.value.gcp.master_authorized_networks, [])

  cilium         = local.cilium_effective
  cilium_version = local.cilium_version

  deletion_protection = try(each.value.gcp.deletion_protection, false)
}

locals {
  gcp_cluster_control_plane_ips = { for k, v in module.gcp : k => v.control_plane_ips }
  gcp_cluster_worker_ips        = { for k, v in module.gcp : k => v.worker_ips }
  gcp_cluster_install_complete  = { for k, v in module.gcp : k => v.install_complete }
  gke_cluster_endpoints         = { for k, v in module.gke : k => v.cluster_endpoint }
  gke_cluster_install_complete  = { for k, v in module.gke : k => v.install_complete }
  gke_kubeconfigs               = { for k, v in module.gke : k => v.kubeconfig }
}
%{else}
locals {
  gcp_cluster_control_plane_ips = {}
  gcp_cluster_worker_ips        = {}
  gcp_cluster_install_complete  = {}
  gke_cluster_endpoints         = {}
  gke_cluster_install_complete  = {}
  gke_kubeconfigs               = {}
}
%{endif}
EOF
}

generate "secrets_optional" {
  path      = "secrets_optional.tf"
  if_exists = "overwrite"

  contents = <<-EOF
%{if local.enable_onepassword}
provider "onepassword" {
  alias   = "secrets"
  account = "${local.onepassword_account}"
}

module "secrets" {
  source = "./modules/secrets"
  count  = local.onepassword_needed ? 1 : 0

  providers = {
    onepassword = onepassword.secrets
  }

  vault_name                      = var.onepassword_vault
  fetch_hcloud_token              = var.hcloud_token == null
  fetch_cloudflare_token          = var.cloudflare_api_token == null
  fetch_tailscale_oauth_secret    = var.tailscale.enabled && var.tailscale_oauth_secret == null
  fetch_tailscale_oauth_client_id = var.tailscale.enabled && var.tailscale_oauth_client_id == null
  fetch_gcp_credentials           = false
}

locals {
  effective_hcloud_token              = coalesce(var.hcloud_token, try(module.secrets[0].hcloud_token, null))
  effective_cloudflare_api_token      = coalesce(var.cloudflare_api_token, try(module.secrets[0].cloudflare_api_token, null))
  effective_tailscale_oauth_secret    = coalesce(var.tailscale_oauth_secret, try(module.secrets[0].tailscale_oauth_secret, null))
  effective_tailscale_oauth_client_id = coalesce(var.tailscale_oauth_client_id, try(module.secrets[0].tailscale_oauth_client_id, null))
  effective_gcp_credentials           = try(coalesce(var.gcp_credentials, try(module.secrets[0].gcp_credentials, null)), "")
}
%{else}
locals {
  effective_hcloud_token              = var.hcloud_token
  effective_cloudflare_api_token      = var.cloudflare_api_token
  effective_tailscale_oauth_secret    = var.tailscale_oauth_secret
  effective_tailscale_oauth_client_id = var.tailscale_oauth_client_id
  effective_gcp_credentials           = var.gcp_credentials
}
%{endif}
EOF
}
