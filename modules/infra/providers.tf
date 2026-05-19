# Google provider - skip authentication for Hetzner-only clusters
provider "google" {
  project = coalesce(try(var.cluster_config.gcp.project_id, null), "placeholder-not-used-for-hetzner-clusters")
  region  = coalesce(try(var.cluster_config.gcp.region, null), "us-central1")

  # Dummy credentials for Hetzner-only clusters
  credentials = try(var.cluster_config.gcp.project_id, null) != null ? null : jsonencode({
    type                        = "service_account"
    project_id                  = "placeholder"
    private_key_id              = "placeholder"
    private_key                 = "placeholder"
    client_email                = "placeholder@placeholder.iam.gserviceaccount.com"
    client_id                   = "placeholder"
    auth_uri                    = "https://accounts.google.com/o/oauth2/auth"
    token_uri                   = "https://oauth2.googleapis.com/token"
    auth_provider_x509_cert_url = "https://www.googleapis.com/oauth2/v1/certs"
  })
}

# Hetzner provider - placeholder for GCP-only clusters (64 char placeholder for validation)
provider "hcloud" {
  token = coalesce(var.hcloud_token, "0000000000000000000000000000000000000000000000000000000000000000")
}

provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_secret
}

# Cloudflare provider - required for DNS
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "kubernetes" {
  config_path = "${abspath(path.root)}/../../../../../.kubeconfigs/${var.cluster_name}"
}

provider "helm" {
  kubernetes = {
    config_path = "${abspath(path.root)}/../../../../../.kubeconfigs/${var.cluster_name}"
  }
}