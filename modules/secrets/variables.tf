variable "vault_name" {
  description = "1Password vault name"
  type        = string
  default     = "Infrastructure"
}

variable "fetch_hcloud_token" {
  description = "Fetch hcloud_token from 1Password"
  type        = bool
  default     = true
}

variable "fetch_cloudflare_token" {
  description = "Fetch cloudflare_api_token from 1Password"
  type        = bool
  default     = true
}

variable "fetch_tailscale_oauth_secret" {
  description = "Fetch tailscale_oauth_secret from 1Password"
  type        = bool
  default     = true
}

variable "fetch_tailscale_oauth_client_id" {
  description = "Fetch tailscale_oauth_client_id from 1Password"
  type        = bool
  default     = true
}

variable "fetch_gcp_credentials" {
  description = "Fetch gcp_credentials from 1Password (set false to use gcloud CLI ADC)"
  type        = bool
  default     = false
}
