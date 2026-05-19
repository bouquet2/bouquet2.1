# This module is run separately via main.py after infra apply
# Exclude from stack discovery
exclude {
  if      = true
  actions = ["all"]
}

remote_state {
  backend = "local"
  generate = {
    path = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_env("TF_STATE_DIR", "${get_repo_root()}/.terraform")}/rook-ceph/${get_env("TF_VAR_cluster_name", "default")}/terraform.tfstate"
  }
}

terraform {
  source = "."
  extra_arguments "force_copy" {
    commands = ["init"]
    arguments = ["-force-copy"]
  }
}