locals {
  bucket_name = var.gcs_bucket != "" ? var.gcs_bucket : google_storage_bucket.talos_images[0].name
}

resource "google_storage_bucket" "talos_images" {
  count = var.gcs_bucket != "" ? 0 : 1

  name          = "${var.project_id}-talos-images"
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
  name = "talos-${replace(var.talos_version, ".", "-")}"

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

resource "google_compute_firewall" "cluster" {
  name    = "${var.cluster_name}-firewall"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["50000-50001"]
  }

  allow {
    protocol = "udp"
    ports    = ["41641"]
  }

  allow {
    protocol = "udp"
    ports    = ["51871"]
  }

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]

  target_tags = [var.cluster_name]
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
    network    = var.network
    subnetwork = var.subnetwork != "" ? var.subnetwork : null

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
    network    = var.network
    subnetwork = var.subnetwork != "" ? var.subnetwork : null

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

  allow_stopping_for_update = true
}
