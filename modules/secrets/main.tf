data "onepassword_vault" "this" {
  name = var.vault_name
}

data "onepassword_item" "hcloud_token" {
  count = var.fetch_hcloud_token ? 1 : 0
  vault = data.onepassword_vault.this.uuid
  title = "bouquet-hcloud-token"
}

data "onepassword_item" "cloudflare_api_token" {
  count = var.fetch_cloudflare_token ? 1 : 0
  vault = data.onepassword_vault.this.uuid
  title = "bouquet-cloudflare-api-token"
}

data "onepassword_item" "tailscale_oauth_secret" {
  count = var.fetch_tailscale_oauth_secret ? 1 : 0
  vault = data.onepassword_vault.this.uuid
  title = "bouquet-tailscale-oauth-secret"
}

data "onepassword_item" "tailscale_oauth_client_id" {
  count = var.fetch_tailscale_oauth_client_id ? 1 : 0
  vault = data.onepassword_vault.this.uuid
  title = "bouquet-tailscale-oauth-client-id"
}

data "onepassword_item" "gcp_credentials" {
  count = var.fetch_gcp_credentials ? 1 : 0
  vault = data.onepassword_vault.this.uuid
  title = "bouquet-gcp-credentials"
}
