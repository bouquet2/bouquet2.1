# This file is meant to be copied to stack-generated directories
# Only exclude when NOT in a .terragrunt-stack directory (i.e., when discovered directly)
exclude {
  if      = !contains(split("/", get_terragrunt_dir()), ".terragrunt-stack")
  actions = ["all"]
}

inputs = read_terragrunt_config("${get_terragrunt_dir()}/terragrunt.values.hcl")

remote_state {
  backend = "local"
  generate = {
    path = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_env("TF_STATE_DIR", "${get_repo_root()}/.terraform")}/${basename(get_terragrunt_dir())}/terraform.tfstate"
  }
}

terraform {
  source = "."
  extra_arguments "force_copy" {
    commands = ["init"]
    arguments = ["-force-copy"]
  }
}