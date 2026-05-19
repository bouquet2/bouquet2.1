locals {
  has_hetzner = length([for cp in var.cluster_config.control_planes : cp if cp.provider == "hetzner"]) > 0 || length([for w in var.cluster_config.workers : w if w.provider == "hetzner"]) > 0
  has_gcp     = length([for cp in var.cluster_config.control_planes : cp if cp.provider == "gcp"]) > 0 || length([for w in var.cluster_config.workers : w if w.provider == "gcp"]) > 0
}

# Auto-fetch latest versions from GitHub if not explicitly provided
data "http" "talos_release" {
  count           = var.talos_version == null || var.talos_version == "" ? 1 : 0
  url             = "https://api.github.com/repos/siderolabs/talos/releases/latest"
  request_headers = { Accept = "application/vnd.github.v3+json" }
}

data "http" "kubelet_release" {
  count           = var.kubernetes_version == null || var.kubernetes_version == "" ? 1 : 0
  url             = "https://api.github.com/repos/siderolabs/kubelet/releases/latest"
  request_headers = { Accept = "application/vnd.github.v3+json" }
}

data "http" "cilium_release" {
  count           = var.cilium_version == null || var.cilium_version == "" ? 1 : 0
  url             = "https://api.github.com/repos/cilium/cilium/releases/latest"
  request_headers = { Accept = "application/vnd.github.v3+json" }
}

locals {
  talos_version      = var.talos_version != null && var.talos_version != "" ? var.talos_version : jsondecode(data.http.talos_release[0].response_body).tag_name
  kubernetes_version = var.kubernetes_version != null && var.kubernetes_version != "" ? var.kubernetes_version : jsondecode(data.http.kubelet_release[0].response_body).tag_name
  cilium_version     = var.cilium_version != null && var.cilium_version != "" ? var.cilium_version : jsondecode(data.http.cilium_release[0].response_body).tag_name
}

resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "hcloud_network" "cluster" {
  count    = local.has_hetzner ? 1 : 0
  name     = "${var.cluster_name}-network"
  ip_range = var.hetzner_network_cidr
  labels = {
    cluster    = var.cluster_name
    managed-by = var.cluster_name
  }
}

resource "hcloud_network_subnet" "cluster" {
  count        = local.has_hetzner ? 1 : 0
  network_id   = hcloud_network.cluster[0].id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = var.hetzner_network_cidr
}

module "tailscale_key" {
  source = "./tailscale"
  count  = var.tailscale.enabled ? 1 : 0

  create_key_only = true
  tag             = var.tailscale.tag
}

module "talos" {
  source = "./talos"

  cluster_name        = var.cluster_name
  cluster_id          = var.cluster_config.cluster_id
  talos_version       = local.talos_version
  kubernetes_version  = local.kubernetes_version
  control_planes      = var.cluster_config.control_planes
  workers             = var.cluster_config.workers
  network             = var.network
  cilium              = var.cilium
  cilium_version      = local.cilium_version
  gateway_api_version = var.gateway_api_version

  tailscale_enabled  = var.tailscale.enabled
  tailscale_auth_key = var.tailscale.enabled ? module.tailscale_key[0].auth_key : ""
  tailscale_routes   = var.tailscale.enabled ? var.tailscale.routes : []

  dns_enabled = var.dns.enabled
  dns_domain  = var.dns.domain

  clustermesh_service_type = var.tailscale.enabled ? "NodePort" : "LoadBalancer"

  hcloud_token      = local.has_hetzner ? var.hcloud_token : ""
  hcloud_network_id = local.has_hetzner ? hcloud_network.cluster[0].id : null

  hetzner_network_cidr         = local.has_hetzner ? var.hetzner_network_cidr : ""
  hetzner_loadbalancer_enabled = try(var.hetzner.loadbalancer_enabled, false)

  node_ip_subnets               = var.node_ip_subnets
  approved_underlay_ula_subnets = var.approved_underlay_ula_subnets
  node_providers = merge(
    { for cp in var.cluster_config.control_planes : cp.name => cp.provider },
    { for w in var.cluster_config.workers : w.name => w.provider }
  )
}

module "hetzner" {
  source = "./providers/hetzner"
  count  = local.has_hetzner ? 1 : 0

  cluster_name          = var.cluster_name
  network_id            = hcloud_network.cluster[0].id
  hetzner_network_cidr  = var.hetzner_network_cidr
  control_planes        = [for cp in var.cluster_config.control_planes : cp if cp.provider == "hetzner"]
  workers               = [for w in var.cluster_config.workers : w if w.provider == "hetzner"]
  ssh_public_key        = trimspace(tls_private_key.ssh.public_key_openssh)
  ssh_private_key       = tls_private_key.ssh.private_key_openssh
  talos_version         = local.talos_version
  hcloud_token          = var.hcloud_token
  ceph_disk             = { enabled = try(var.ceph.enabled, false), size = try(var.ceph.osd_disk_size, 50), include_control_planes = try(var.ceph.osd_on_control_planes, false) }
  control_plane_configs = { for cp in var.cluster_config.control_planes : cp.name => module.talos.control_plane_configs[cp.name] if cp.provider == "hetzner" }
  worker_configs        = { for w in var.cluster_config.workers : w.name => module.talos.worker_configs[w.name] if w.provider == "hetzner" }

  depends_on = [hcloud_network_subnet.cluster]
}

module "gcp" {
  source = "./providers/gcp"
  count  = local.has_gcp ? 1 : 0

  project_id            = var.cluster_config.gcp.project_id
  region                = var.cluster_config.gcp.region
  zone                  = var.cluster_config.gcp.zone
  network               = try(var.cluster_config.gcp.network, "default")
  subnetwork            = try(var.cluster_config.gcp.subnetwork, "")
  gcs_bucket            = try(var.cluster_config.gcp.gcs_bucket, "")
  cluster_name          = var.cluster_name
  control_planes        = [for cp in var.cluster_config.control_planes : cp if cp.provider == "gcp"]
  workers               = [for w in var.cluster_config.workers : w if w.provider == "gcp"]
  talos_version         = local.talos_version
  ssh_public_key        = tls_private_key.ssh.public_key_openssh
  control_plane_configs = { for cp in var.cluster_config.control_planes : cp.name => module.talos.control_plane_configs[cp.name] if cp.provider == "gcp" }
  worker_configs        = { for w in var.cluster_config.workers : w.name => module.talos.worker_configs[w.name] if w.provider == "gcp" }

  ceph_disk = try(var.ceph.enabled, false) ? {
    enabled                = true
    size                   = try(var.ceph.osd_disk_size, 50)
    type                   = "pd-ssd"
    include_control_planes = try(var.ceph.osd_on_control_planes, false)
  } : {}

  vpc_peering = var.vpc_peering
  subnet_cidr = var.subnet_cidr
}

locals {
  hetzner_cp_public_ips = local.has_hetzner ? module.hetzner[0].control_plane_ips : {}
  gcp_cp_public_ips     = local.has_gcp ? module.gcp[0].control_plane_ips : {}
  hetzner_w_public_ips  = local.has_hetzner ? module.hetzner[0].worker_ips : {}
  gcp_w_public_ips      = local.has_gcp ? module.gcp[0].worker_ips : {}

  hetzner_cp_internal_ips = local.has_hetzner ? module.hetzner[0].control_plane_internal_ips : {}
  gcp_cp_internal_ips     = local.has_gcp ? module.gcp[0].control_plane_internal_ips : {}
  hetzner_w_internal_ips  = local.has_hetzner ? module.hetzner[0].worker_internal_ips : {}
  gcp_w_internal_ips      = local.has_gcp ? module.gcp[0].worker_internal_ips : {}

  cp_public_ips   = merge(local.hetzner_cp_public_ips, local.gcp_cp_public_ips)
  cp_internal_ips = merge(local.hetzner_cp_internal_ips, local.gcp_cp_internal_ips)
  w_public_ips    = merge(local.hetzner_w_public_ips, local.gcp_w_public_ips)
  w_internal_ips  = merge(local.hetzner_w_internal_ips, local.gcp_w_internal_ips)

  tailscale_cp_ips = var.tailscale.enabled && length(module.tailscale_devices) > 0 ? {
    for k, v in module.tailscale_devices[0].cluster_node_ips[var.cluster_name] :
    replace(k, "${var.cluster_name}-", "") => v
    if contains([for cp in var.cluster_config.control_planes : cp.name], replace(k, "${var.cluster_name}-", ""))
  } : {}

  tailscale_w_ips = var.tailscale.enabled && length(module.tailscale_devices) > 0 ? {
    for k, v in module.tailscale_devices[0].cluster_node_ips[var.cluster_name] :
    replace(k, "${var.cluster_name}-", "") => v
    if contains([for w in var.cluster_config.workers : w.name], replace(k, "${var.cluster_name}-", ""))
  } : {}

  selected_cp_ips = var.tailscale.enabled ? local.tailscale_cp_ips : local.cp_public_ips

  selected_w_ips = var.tailscale.enabled ? local.tailscale_w_ips : local.w_public_ips

  cp_provider_key_count = length(keys(local.hetzner_cp_public_ips)) + length(keys(local.gcp_cp_public_ips))
  cp_merged_key_count   = length(keys(local.cp_public_ips))
  cp_keys_unique        = local.cp_provider_key_count == local.cp_merged_key_count

  w_provider_key_count = length(keys(local.hetzner_w_public_ips)) + length(keys(local.gcp_w_public_ips))
  w_merged_key_count   = length(keys(local.w_public_ips))
  w_keys_unique        = local.w_provider_key_count == local.w_merged_key_count

  cp_selected_complete = alltrue([
    for cp in var.cluster_config.control_planes :
    try(local.selected_cp_ips[cp.name] != null && local.selected_cp_ips[cp.name] != "", false)
  ])

  w_selected_complete = alltrue([
    for w in var.cluster_config.workers :
    try(local.selected_w_ips[w.name] != null && local.selected_w_ips[w.name] != "", false)
  ])

  control_plane_ips   = local.selected_cp_ips
  worker_ips          = local.selected_w_ips
  bootstrap_endpoint  = try([for v in values(local.selected_cp_ips) : v if v != null && v != ""][0], "")
  expected_node_count = length(var.cluster_config.control_planes) + length(var.cluster_config.workers)

  all_nodes = merge(
    { for cp in var.cluster_config.control_planes : cp.name => merge(cp, { role = "controlplane" }) },
    { for w in var.cluster_config.workers : w.name => merge(w, { role = "worker" }) }
  )
}

resource "talos_machine_configuration_apply" "nodes" {
  for_each = local.all_nodes

  client_configuration        = module.talos.client_configuration
  machine_configuration_input = each.value.role == "controlplane" ? module.talos.control_plane_configs[each.key] : module.talos.worker_configs[each.key]
  node                        = each.value.role == "controlplane" ? coalesce(local.selected_cp_ips[each.key], "pending") : coalesce(local.selected_w_ips[each.key], "pending")
  endpoint                    = each.value.role == "controlplane" ? coalesce(local.selected_cp_ips[each.key], "pending") : coalesce(local.selected_w_ips[each.key], "pending")

  config_patches = each.value.provider == "hetzner" ? [
    jsonencode({
      machine = {
        kubelet = {
          extraArgs = {
            provider-id = each.value.role == "controlplane" ? module.hetzner[0].control_plane_provider_ids[each.key] : module.hetzner[0].worker_provider_ids[each.key]
          }
        }
      }
    })
  ] : []

  lifecycle {
    precondition {
      condition     = each.value.role == "controlplane" ? try(local.selected_cp_ips[each.key] != null && local.selected_cp_ips[each.key] != "", false) : try(local.selected_w_ips[each.key] != null && local.selected_w_ips[each.key] != "", false)
      error_message = "No endpoint IP for node ${each.key} - Tailscale device not registered."
    }
  }
}

resource "talos_machine_bootstrap" "this" {
  count                = length(var.cluster_config.control_planes) > 0 ? 1 : 0
  client_configuration = module.talos.client_configuration
  node                 = local.bootstrap_endpoint
  endpoint             = local.bootstrap_endpoint

  depends_on = [talos_machine_configuration_apply.nodes]

  lifecycle {
    precondition {
      condition     = local.cp_keys_unique
      error_message = "Duplicate control-plane node names across providers cause merged IP map collisions."
    }
    precondition {
      condition     = local.w_keys_unique
      error_message = "Duplicate worker node names across providers cause merged IP map collisions."
    }
    precondition {
      condition     = local.bootstrap_endpoint != ""
      error_message = "Bootstrap endpoint not available - Tailscale devices not yet registered."
    }
  }
}

resource "talos_cluster_kubeconfig" "this" {
  count                = length(var.cluster_config.control_planes) > 0 ? 1 : 0
  client_configuration = module.talos.client_configuration
  node                 = local.bootstrap_endpoint
  endpoint             = local.bootstrap_endpoint

  depends_on = [talos_machine_configuration_apply.nodes, talos_machine_bootstrap.this]
}

resource "local_file" "kubeconfig" {
  count    = length(var.cluster_config.control_planes) > 0 ? 1 : 0
  filename = "${abspath(path.root)}/../../../../../.kubeconfigs/${var.cluster_name}"
  content  = talos_cluster_kubeconfig.this[0].kubeconfig_raw
}

resource "null_resource" "kubernetes_ready" {
  count = length(var.cluster_config.control_planes) > 0 ? 1 : 0

  triggers = {
    kubeconfig_hash = sha256(talos_cluster_kubeconfig.this[0].kubeconfig_raw)
    expected_nodes  = tostring(local.expected_node_count)
    cilium_enabled  = tostring(try(var.cilium.enabled, false))
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -eu

      KUBECONFIG_PATH="${local_file.kubeconfig[0].filename}"
      EXPECTED_NODES="${local.expected_node_count}"
      CILIUM_ENABLED="${try(var.cilium.enabled, false)}"
      DEADLINE=$(($(date +%s) + 900))

      while true; do
        API_READY=false
        NODES_READY=false
        CILIUM_READY=false
        COREDNS_READY=false

        SERVER=$(grep server "$${KUBECONFIG_PATH}" | head -1 | sed -E 's/.*server: (https?:\/\/[^:]+):.*/\1/')
        SERVER_HOST=$(echo "$${SERVER}" | sed -E 's|https?://||')
        RESOLVED_IPS=$(host "$${SERVER_HOST}" 2>/dev/null | awk '/address/{print $NF}' || true)
        for endpoint in $${RESOLVED_IPS} $${SERVER_HOST}; do
          if kubectl --kubeconfig "$${KUBECONFIG_PATH}" --server="https://$${endpoint}:6443" get --raw=/readyz --request-timeout=5s >/dev/null 2>&1; then
            API_READY=true
            break
          fi
        done

        READY_NODES=$(kubectl --kubeconfig "$${KUBECONFIG_PATH}" get nodes --no-headers 2>/dev/null | while read -r _ STATUS _; do
          if [ "$${STATUS}" = "Ready" ]; then
            printf 'ready\n'
          fi
        done | wc -l | tr -d ' ')

        if [ "$${READY_NODES}" -ge "$${EXPECTED_NODES}" ]; then
          NODES_READY=true
        fi

        if [ "$${CILIUM_ENABLED}" != "true" ]; then
          CILIUM_READY=true
        elif kubectl --kubeconfig "$${KUBECONFIG_PATH}" -n kube-system rollout status ds/cilium --timeout=10s >/dev/null 2>&1; then
          CILIUM_READY=true
        fi

        if ! kubectl --kubeconfig "$${KUBECONFIG_PATH}" -n kube-system get deploy/coredns >/dev/null 2>&1; then
          COREDNS_READY=true
        elif kubectl --kubeconfig "$${KUBECONFIG_PATH}" -n kube-system rollout status deploy/coredns --timeout=10s >/dev/null 2>&1; then
          COREDNS_READY=true
        fi

        if [ "$${API_READY}" = "true" ] && [ "$${NODES_READY}" = "true" ] && [ "$${CILIUM_READY}" = "true" ] && [ "$${COREDNS_READY}" = "true" ]; then
          exit 0
        fi

        if [ "$(date +%s)" -ge "$${DEADLINE}" ]; then
          echo "Kubernetes did not become ready in time"
          echo "api_ready=$${API_READY} nodes_ready=$${NODES_READY} ready_nodes=$${READY_NODES}/$${EXPECTED_NODES} cilium_ready=$${CILIUM_READY} coredns_ready=$${COREDNS_READY}"
          kubectl --kubeconfig "$${KUBECONFIG_PATH}" get nodes -o wide || true
          kubectl --kubeconfig "$${KUBECONFIG_PATH}" -n kube-system get pods -o wide || true
          exit 1
        fi

        sleep 10
      done
    EOT
  }

  depends_on = [local_file.kubeconfig, talos_machine_configuration_apply.nodes]
}

data "talos_client_configuration" "this" {
  count = length(var.cluster_config.control_planes) > 0 ? 1 : 0

  cluster_name         = var.cluster_name
  client_configuration = module.talos.client_configuration
  nodes                = var.tailscale.enabled ? [for k, v in module.tailscale_devices[0].cluster_node_ips[var.cluster_name] : v] : values(merge(local.control_plane_ips, local.worker_ips))
  endpoints            = var.tailscale.enabled ? [for cp in var.cluster_config.control_planes : module.tailscale_devices[0].cluster_node_ips[var.cluster_name]["${var.cluster_name}-${cp.name}"]] : values(local.control_plane_ips)
}

module "tailscale_devices" {
  source = "./tailscale"
  count  = var.tailscale.enabled ? 1 : 0

  clusters = { (var.cluster_name) = { control_planes = var.cluster_config.control_planes, workers = var.cluster_config.workers } }
  cluster_install_complete = {
    (var.cluster_name) = concat(
      local.has_hetzner ? module.hetzner[0].install_complete : [],
      local.has_gcp ? module.gcp[0].install_complete : []
    )
  }
  tag                 = var.tailscale.tag
  tailnet             = var.tailscale.tailnet
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_secret
  manage_acl          = try(var.tailscale.manage_acl, false)
  acl_policy          = try(var.tailscale.acl_policy, "")
}

module "dns" {
  source = "./dns"
  count  = var.dns.enabled && (local.has_hetzner || local.has_gcp) ? 1 : 0

  domain          = var.dns.domain
  internal_domain = var.dns.internal_domain
  cluster_names   = [var.cluster_name]
  cluster_control_plane_ips = { (var.cluster_name) = merge(
    local.has_hetzner ? module.hetzner[0].control_plane_ips : {},
    local.has_gcp ? module.gcp[0].control_plane_ips : {}
  ) }
  cluster_worker_ips = { (var.cluster_name) = merge(
    local.has_hetzner ? module.hetzner[0].worker_ips : {},
    local.has_gcp ? module.gcp[0].worker_ips : {}
  ) }
  tailscale_ips   = var.tailscale.enabled && length(module.tailscale_devices) > 0 ? module.tailscale_devices[0].cluster_node_ips[var.cluster_name] : {}
  lb_subdomain    = "lb"
  primary_cluster = var.primary_cluster
}

locals {
  ceph_all_nodes = try(var.ceph.osd_on_control_planes, false)
  ceph_node_names = [
    for node in concat(
      local.ceph_all_nodes ? var.cluster_config.control_planes : [],
      var.cluster_config.workers
    ) : "${var.cluster_name}-${node.name}"
  ]

  ceph_gcp_devices = { for name in local.ceph_node_names : name => "/dev/disk/by-id/scsi-0Google_PersistentDisk_${name}-ceph-osd" if anytrue([for cp in var.cluster_config.control_planes : "${var.cluster_name}-${cp.name}" == name && cp.provider == "gcp"]) || anytrue([for w in var.cluster_config.workers : "${var.cluster_name}-${w.name}" == name && w.provider == "gcp"]) }

  ceph_hetzner_devices = {} # Hetzner uses device_filter, not explicit device paths (volume IDs are runtime-generated)

  ceph_osd_nodes     = local.ceph_node_names
  ceph_osd_devices   = merge(local.ceph_gcp_devices, local.ceph_hetzner_devices)
  ceph_device_filter = local.has_gcp && !local.has_hetzner ? "^/dev/disk/by-id/scsi-0Google_PersistentDisk" : local.has_hetzner && !local.has_gcp ? "^/dev/disk/by-id/scsi-0HC_Volume" : ""
}

module "rook_ceph" {
  source = "./rook"
  count  = try(var.ceph.enabled, false) ? 1 : 0

  cluster_name                  = var.cluster_name
  kubeconfig_path               = local_file.kubeconfig[0].filename
  namespace                     = "rook-ceph"
  data_dir                      = try(var.ceph.data_dir, "/var/lib/rook")
  mon_count                     = try(var.ceph.mon.count, 1)
  mon_allow_multiple_per_node   = try(var.ceph.mon.allow_multiple_per_node, true)
  mgr_count                     = try(var.ceph.mgr.count, 1)
  dashboard_enabled             = try(var.ceph.dashboard.enabled, true)
  dashboard_ssl                 = try(var.ceph.dashboard.ssl, false)
  cephfs_enabled                = try(var.ceph.cephfs.enabled, true)
  cephfs_name                   = try(var.ceph.cephfs.name, "cephfs")
  cephfs_metadata_pool_replicas = try(var.ceph.cephfs.metadata_pool_replicas, 2)
  cephfs_data_pool_replicas     = try(var.ceph.cephfs.data_pool_replicas, 2)
  storageclass_block            = try(var.ceph.storage_classes.block, true)
  storageclass_fs               = try(var.ceph.storage_classes.fs, true)
  storageclass_default          = try(var.ceph.storage_classes.default, "fs")

  osd_nodes     = local.ceph_osd_nodes
  osd_devices   = local.ceph_osd_devices
  device_filter = local.ceph_device_filter
  csi           = try(var.ceph.csi, {})
  resources     = try(var.ceph.resources, {})

  depends_on = [null_resource.kubernetes_ready, module.dns]
}
