terraform {
  source = "/Users/kreato/Sources/bouquet2.1/modules/clustermesh"
}

dependencies {
  paths = ["../../.terragrunt-stack/infra_gcp_central1", "../../.terragrunt-stack/infra_hetzner_hel1"]
}
