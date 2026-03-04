data "google_client_config" "default" {}

locals {
  cluster_endpoint = "https://${google_container_cluster.this.endpoint}"
  
  kubeconfig = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    preferences = {}
    clusters = [{
      name = var.cluster_name
      cluster = {
        server = local.cluster_endpoint
        certificate-authority-data = google_container_cluster.this.master_auth[0].cluster_ca_certificate
      }
    }]
    contexts = [{
      name = var.cluster_name
      context = {
        cluster = var.cluster_name
        user    = var.cluster_name
      }
    }]
    current-context = var.cluster_name
    users = [{
      name = var.cluster_name
      user = {
        token = data.google_client_config.default.access_token
      }
    }]
  })

  cilium_version = var.cilium_version

  cilium_clustermesh_flags = var.cilium.clustermesh ? "--set clustermesh.useAPIServer=true --set clustermesh.config.enabled=true --set clustermesh.apiserver.service.type=LoadBalancer" : ""
  cilium_gateway_api_flags    = var.cilium.gateway_api ? "--set gatewayAPI.enabled=true" : ""
  gateway_api_crds_url_prefix = "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.5.0/config/crd/standard"
  gateway_api_crds = var.cilium.gateway_api ? [
    "${local.gateway_api_crds_url_prefix}/gateway.networking.k8s.io_gatewayclasses.yaml",
    "${local.gateway_api_crds_url_prefix}/gateway.networking.k8s.io_gateways.yaml",
    "${local.gateway_api_crds_url_prefix}/gateway.networking.k8s.io_httproutes.yaml",
    "${local.gateway_api_crds_url_prefix}/gateway.networking.k8s.io_referencegrants.yaml",
    "${local.gateway_api_crds_url_prefix}/gateway.networking.k8s.io_grpcroutes.yaml",
  ] : []
  cilium_encryption_flags = var.cilium.encryption_enabled ? join(" ", [
    "--set encryption.enabled=true",
    "--set encryption.type=${var.cilium.encryption_type}",
  ]) : ""

  cilium_manifest = templatefile("${path.module}/templates/cilium.yaml", {
    cluster_id          = var.cluster_id
    cluster_name        = var.cluster_name
    native_cidr         = google_container_cluster.this.cluster_ipv4_cidr
    clustermesh_enabled = local.cilium_clustermesh_flags
    gateway_api_enabled = local.cilium_gateway_api_flags
    encryption_flags    = local.cilium_encryption_flags
    cilium_ver          = var.cilium_version
  })
}

resource "google_compute_network" "this" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "this" {
  name                     = "${var.cluster_name}-subnet"
  ip_cidr_range            = "10.0.0.0/20"
  region                   = var.region
  project                  = var.project_id
  network                  = google_compute_network.this.id
  stack_type               = "IPV4_IPV6"
  ipv6_access_type         = "EXTERNAL"
  private_ip_google_access = true
}

resource "google_compute_firewall" "wireguard" {
  count    = var.cilium.encryption_enabled ? 1 : 0
  name     = "${var.cluster_name}-wireguard"
  network  = google_compute_network.this.name
  project  = var.project_id

  allow {
    protocol = "udp"
    ports    = ["51871"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.cluster_name}"]
}

resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.zone

  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.this.id
  subnetwork      = google_compute_subnetwork.this.name

  ip_allocation_policy {
    # Default is IPV4 only - IPV4_IPV6 requires ADVANCED_DATAPATH which prevents custom Cilium
  }

  private_cluster_config {
    enable_private_nodes    = var.enable_private_cluster
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.enable_private_cluster ? var.master_ipv4_cidr_block : null
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  remove_default_node_pool = true
  initial_node_count       = 1

  datapath_provider = "LEGACY_DATAPATH"

  network_policy {
    enabled = var.network_policy_enabled
  }

  monitoring_config {
    enable_components = []
  }

  logging_config {
    enable_components = []
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = !var.network_policy_enabled
    }
  }

  timeouts {
    create = "30m"
    update = "40m"
    delete = "30m"
  }

  deletion_protection = var.deletion_protection
}

resource "google_compute_router" "this" {
  count   = var.enable_private_cluster ? 1 : 0
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.this.id
  project = var.project_id
}

resource "google_compute_router_nat" "this" {
  count                              = var.enable_private_cluster ? 1 : 0
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.this[0].name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_container_node_pool" "this" {
  for_each = { for np in var.node_pools : np.name => np }

  name       = each.key
  cluster    = google_container_cluster.this.name
  location   = var.zone
  node_count = each.value.min_count

  autoscaling {
    min_node_count = each.value.min_count
    max_node_count = each.value.max_count
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    
    preemptible = each.value.preemptible

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = merge(
      each.value.node_labels,
      {}
    )

    dynamic "taint" {
      for_each = concat(
        each.value.node_taints,
        [{ key = "node.cilium.io/agent-not-ready", value = "true", effect = "NO_EXECUTE" }]
      )
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }

  depends_on = [google_container_cluster.this]
}

resource "local_file" "cilium_manifest" {
  count    = var.cilium.enabled ? 1 : 0
  content  = local.cilium_manifest
  filename = "${path.module}/generated/cilium-${var.cluster_name}.yaml"
}

resource "null_resource" "cilium_install" {
  count = var.cilium.enabled ? 1 : 0

  triggers = {
    cluster_id   = var.cluster_id
    cluster_name = var.cluster_name
    cilium_ver   = local.cilium_version
    clustermesh  = var.cilium.clustermesh ? "true" : "false"
    gateway_api  = var.cilium.gateway_api ? "true" : "false"
    manifest_sha = local_file.cilium_manifest[0].content_sha256
    gateway_api_crds = join(",", local.gateway_api_crds)
  }

  provisioner "local-exec" {
    environment = {
      KUBECONFIG    = base64encode(local.kubeconfig)
      MANIFEST_PATH = local_file.cilium_manifest[0].filename
      PATH          = "/opt/homebrew/bin:/etc/profiles/per-user/kreato/bin:/usr/local/bin:/usr/bin:/bin"
    }
    command = <<-EOT
      set -e
      
      KUBECONFIG_FILE=$(mktemp)
      echo "$${KUBECONFIG}" | base64 -d > "$${KUBECONFIG_FILE}"
      export KUBECONFIG="$${KUBECONFIG_FILE}"
      
      %{for url in local.gateway_api_crds~}
      echo "Applying Gateway API CRD: ${url}..."
      kubectl apply -f "${url}"
      %{endfor~}

      echo "Applying Cilium installation manifest..."
      kubectl apply -f "$${MANIFEST_PATH}"
      
      echo "Waiting for Cilium install Job to complete..."
      kubectl wait --for=condition=complete job/helm-install-cilium -n kube-system --timeout=600s || true
      
      echo "Waiting for Cilium to be ready..."
      kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s || true
      
      rm -f "$${KUBECONFIG_FILE}"
    EOT
  }

  depends_on = [google_container_node_pool.this, local_file.cilium_manifest]
}

