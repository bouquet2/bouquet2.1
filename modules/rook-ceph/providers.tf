provider "kubernetes" {
  config_path    = local.kubeconfig_path
  config_context = var.cluster_name
}

provider "helm" {
  kubernetes = {
    config_path    = local.kubeconfig_path
    config_context = var.cluster_name
  }
}