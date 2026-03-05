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

# Generate the optional providers (google + onepassword) and the secrets
# module into separate files so that OpenTofu only initialises them when
# they are actually needed.
generate "providers_optional" {
  path      = "providers_optional.tf"
  if_exists = "overwrite"

  contents = <<-EOF
%{if local.has_gcp}
provider "google" {
  project = "${local.gcp_project}"
  region  = "${local.gcp_region}"
  zone    = "${local.gcp_zone}"
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
