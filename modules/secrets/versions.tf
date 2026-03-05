terraform {
  required_version = ">= 1.6.0"

  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.2"
      configuration_aliases = [onepassword]
    }
  }
}
