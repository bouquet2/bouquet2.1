output "hcloud_token" {
  value     = try(data.onepassword_item.hcloud_token[0].password, null)
  sensitive = true
}

output "cloudflare_api_token" {
  value     = try(data.onepassword_item.cloudflare_api_token[0].password, null)
  sensitive = true
}

output "tailscale_oauth_secret" {
  value     = try(data.onepassword_item.tailscale_oauth_secret[0].password, null)
  sensitive = true
}

output "tailscale_oauth_client_id" {
  value     = try(data.onepassword_item.tailscale_oauth_client_id[0].password, null)
  sensitive = true
}

output "gcp_credentials" {
  value     = try(data.onepassword_item.gcp_credentials[0].password, null)
  sensitive = true
}
