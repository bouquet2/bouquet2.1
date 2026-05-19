module "k8s_cleanup" {
  source = "../k8s"

  cluster_name   = var.cluster_name
  workers        = var.cluster_config.workers
  control_planes = var.cluster_config.control_planes
  kubeconfig     = var.kubeconfig_raw
}
