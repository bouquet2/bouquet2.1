terraform {
  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.16"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}
