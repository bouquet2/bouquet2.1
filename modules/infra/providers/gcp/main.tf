locals {
  bucket_name       = var.gcs_bucket != "" ? var.gcs_bucket : google_storage_bucket.talos_images[0].name
  use_custom_network = var.network != "default"

  ceph_enabled   = try(var.ceph_disk.enabled, false)
  ceph_all_nodes = try(var.ceph_disk.include_control_planes, false)
  ceph_nodes     = local.ceph_all_nodes ? merge({ for cp in var.control_planes : cp.name => cp }, { for w in var.workers : w.name => w }) : { for w in var.workers : w.name => w }
}

resource "google_compute_network" "vpc" {
  count = local.use_custom_network ? 0 : 1

  name                      = "${var.cluster_name}-vpc"
  auto_create_subnetworks   = false
  enable_ula_internal_ipv6  = true
}

resource "google_compute_subnetwork" "subnet" {
  count = local.use_custom_network ? 0 : 1

  name          = "${var.cluster_name}-subnet"
  network       = google_compute_network.vpc[0].id
  region        = var.region
  ip_cidr_range = var.subnet_cidr

  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "INTERNAL"
}

resource "google_storage_bucket" "talos_images" {
  count = var.gcs_bucket != "" ? 0 : 1

  name          = "${var.project_id}-${var.cluster_name}-talos-images"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true
}

resource "null_resource" "upload_talos_image" {
  triggers = {
    talos_version = var.talos_version
    schematic_id  = var.schematic_id
    bucket_name   = local.bucket_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      ARCH="amd64"
      URL="https://factory.talos.dev/image/${var.schematic_id}/${var.talos_version}/gcp-$ARCH.raw.tar.gz"
      curl -fL "$URL" -o /tmp/talos-gcp-${var.talos_version}.tar.gz
      gcloud storage cp /tmp/talos-gcp-${var.talos_version}.tar.gz gs://${local.bucket_name}/talos-${var.talos_version}.tar.gz
    EOT
  }

  depends_on = [google_storage_bucket.talos_images]
}

resource "google_compute_image" "talos" {
  name = "${var.cluster_name}-talos-${replace(var.talos_version, ".", "-")}"

  raw_disk {
    source = "https://storage.googleapis.com/${local.bucket_name}/talos-${var.talos_version}.tar.gz"
  }

  guest_os_features {
    type = "VIRTIO_SCSI_MULTIQUEUE"
  }

  labels = {
    cluster    = var.cluster_name
    managed-by = var.cluster_name
  }

  depends_on = [null_resource.upload_talos_image]
}

resource "null_resource" "cleanup_talos_image" {
  triggers = {
    talos_version = var.talos_version
    image_id      = google_compute_image.talos.id
  }

  provisioner "local-exec" {
    command = "gcloud storage rm gs://${local.bucket_name}/talos-${var.talos_version}.tar.gz"
  }

  depends_on = [google_compute_image.talos]
}

resource "google_compute_instance" "control_plane" {
  for_each = { for cp in var.control_planes : cp.name => cp }

  name         = "${var.cluster_name}-${each.value.name}"
  machine_type = coalesce(each.value.machine_type, "e2-standard-2")
  zone         = var.zone

  tags = [var.cluster_name, "control-plane"]

  boot_disk {
    initialize_params {
      image = google_compute_image.talos.self_link
      size  = coalesce(each.value.disk_size, 50)
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = local.use_custom_network ? var.network : google_compute_network.vpc[0].id
    subnetwork = local.use_custom_network ? (var.subnetwork != "" ? var.subnetwork : null) : google_compute_subnetwork.subnet[0].id

    stack_type    = "IPV4_IPV6"
    access_config {}
  }

  metadata = {
    ssh-keys  = "root:${var.ssh_public_key}"
    user-data = var.control_plane_configs[each.key]
  }

  labels = {
    cluster    = var.cluster_name
    managed-by = var.cluster_name
    node-role  = "control-plane"
    node-name  = each.value.name
  }

  dynamic "attached_disk" {
    for_each = local.ceph_enabled && contains(keys(local.ceph_nodes), each.key) ? { 1 = true } : {}

    content {
      source      = google_compute_disk.ceph_osd[each.key].self_link
      device_name = "${var.cluster_name}-${each.key}-ceph-osd"
    }
  }

  allow_stopping_for_update = true
}

resource "google_compute_instance" "worker" {
  for_each = { for w in var.workers : w.name => w }

  name         = "${var.cluster_name}-${each.value.name}"
  machine_type = coalesce(each.value.machine_type, "e2-standard-2")
  zone         = var.zone

  tags = [var.cluster_name, "worker"]

  boot_disk {
    initialize_params {
      image = google_compute_image.talos.self_link
      size  = coalesce(each.value.disk_size, 50)
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = local.use_custom_network ? var.network : google_compute_network.vpc[0].id
    subnetwork = local.use_custom_network ? (var.subnetwork != "" ? var.subnetwork : null) : google_compute_subnetwork.subnet[0].id

    stack_type    = "IPV4_IPV6"
    access_config {}
  }

  metadata = {
    ssh-keys  = "root:${var.ssh_public_key}"
    user-data = var.worker_configs[each.key]
  }

  labels = {
    cluster    = var.cluster_name
    managed-by = var.cluster_name
    node-role  = "worker"
    node-name  = each.value.name
  }

  dynamic "attached_disk" {
    for_each = local.ceph_enabled && contains(keys(local.ceph_nodes), each.key) ? { 1 = true } : {}

    content {
      source      = google_compute_disk.ceph_osd[each.key].self_link
      device_name = "${var.cluster_name}-${each.key}-ceph-osd"
    }
  }

  allow_stopping_for_update = true
}

resource "google_compute_firewall" "wireguard" {
  name    = "${var.cluster_name}-wireguard"
  network = local.use_custom_network ? var.network : google_compute_network.vpc[0].name

  allow {
    protocol = "udp"
    ports    = ["51871"]
  }

  source_ranges = ["10.0.0.0/8", "100.64.0.0/10"]

  target_tags = [var.cluster_name]
}

resource "google_compute_firewall" "internal_ipv4" {
  name    = "${var.cluster_name}-internal-ipv4"
  network = local.use_custom_network ? var.network : google_compute_network.vpc[0].name

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/8"]

  target_tags = [var.cluster_name]
}

resource "google_compute_firewall" "internal_ipv6" {
  name    = "${var.cluster_name}-internal-ipv6"
  network = local.use_custom_network ? var.network : google_compute_network.vpc[0].name

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "58"
  }

  allow {
    protocol = "41"
  }

  source_ranges = ["fd00::/8"]

  target_tags = [var.cluster_name]
}

resource "google_compute_network_peering" "this" {
  for_each = { for p in var.vpc_peering : p.name => p }

  name         = "${var.cluster_name}-peer-${each.key}"
  network      = local.use_custom_network ? var.network : google_compute_network.vpc[0].self_link
  peer_network = each.value.vpc_link

  stack_type = "IPV4_IPV6"

  export_custom_routes                = true
  import_custom_routes                = true
  export_subnet_routes_with_public_ip = true
  import_subnet_routes_with_public_ip = true
}

resource "google_compute_firewall" "public_https" {
  name    = "${var.cluster_name}-public-https"
  network = local.use_custom_network ? var.network : google_compute_network.vpc[0].name

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]

  target_tags = [var.cluster_name]
}

resource "google_compute_firewall" "public_tailscale" {
  name    = "${var.cluster_name}-public-tailscale"
  network = local.use_custom_network ? var.network : google_compute_network.vpc[0].name

  allow {
    protocol = "udp"
    ports    = ["41641"]
  }

  source_ranges = ["0.0.0.0/0"]

  target_tags = [var.cluster_name]
}

resource "google_compute_disk" "ceph_osd" {
  for_each = local.ceph_enabled ? local.ceph_nodes : {}

  name  = "${var.cluster_name}-${each.key}-ceph-osd"
  type  = coalesce(try(var.ceph_disk.type, null), "pd-ssd")
  size  = coalesce(try(var.ceph_disk.size, null), 50)
  zone  = var.zone

  labels = {
    cluster    = var.cluster_name
    managed-by = var.cluster_name
    ceph-osd   = "true"
  }
}
