locals {
  latest_ubuntu = "ubuntu-24.04"

  control_plane_private_ips = {
    for i, cp in var.control_planes : cp.name => cidrhost(var.hetzner_network_cidr, 256 + i + 1)
  }

  worker_private_ips = {
    for i, w in var.workers : w.name => cidrhost(var.hetzner_network_cidr, 512 + i + 1)
  }

  private_ips = merge(local.control_plane_private_ips, local.worker_private_ips)

  ceph_enabled   = try(var.ceph_disk.enabled, false)
  ceph_all_nodes = try(var.ceph_disk.include_control_planes, false)
  ceph_nodes     = local.ceph_all_nodes ? merge({ for cp in var.control_planes : cp.name => cp }, { for w in var.workers : w.name => w }) : { for w in var.workers : w.name => w }
}

resource "hcloud_volume" "ceph_osd" {
  for_each = local.ceph_enabled ? local.ceph_nodes : {}

  name      = "${var.cluster_name}-${each.key}-ceph-osd"
  size      = coalesce(try(var.ceph_disk.size, null), 50)
  location  = var.control_planes[0].location
  automount = false

  labels = {
    cluster    = var.cluster_name
    managed-by = var.cluster_name
    ceph-osd   = "true"
  }
}

resource "hcloud_volume_attachment" "ceph_osd" {
  for_each = local.ceph_enabled ? local.ceph_nodes : {}

  volume_id = hcloud_volume.ceph_osd[each.key].id
  server_id = lookup(
    merge(
      { for cp in hcloud_server.control_plane : cp.labels["node-name"] => cp.id },
      { for w in hcloud_server.worker : w.labels["node-name"] => w.id }
    ),
    each.key,
    0
  )

  depends_on = [hcloud_volume.ceph_osd]
}



resource "hcloud_ssh_key" "cluster" {
  name       = "${var.cluster_name}-ssh-key"
  public_key = var.ssh_public_key
  labels = {
    cluster    = var.cluster_name
    managed-by = var.cluster_name
  }
}

resource "hcloud_firewall" "cluster" {
  name = "${var.cluster_name}-firewall"
  labels = {
    cluster    = var.cluster_name
    managed-by = var.cluster_name
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "50000-50001"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "udp"
    port      = "41641"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "udp"
    port      = "51871"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

}

resource "hcloud_server" "control_plane" {
  for_each = { for cp in var.control_planes : cp.name => cp }

  name        = "${var.cluster_name}-${each.value.name}"
  server_type = each.value.server_type
  location    = each.value.location
  image       = local.latest_ubuntu
  rescue      = "linux64"
  user_data   = var.control_plane_configs[each.key]

  ssh_keys     = [hcloud_ssh_key.cluster.id]
  firewall_ids = [hcloud_firewall.cluster.id]

  labels = {
    cluster    = var.cluster_name
    managed-by = var.cluster_name
    node-role  = "control-plane"
    node-name  = each.value.name
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = var.network_id
    ip         = local.private_ips[each.key]
  }

  lifecycle {
    ignore_changes = [user_data, image]
  }
}

resource "hcloud_server" "worker" {
  for_each = { for w in var.workers : w.name => w }

  name        = "${var.cluster_name}-${each.value.name}"
  server_type = each.value.server_type
  location    = each.value.location
  image       = local.latest_ubuntu
  rescue      = "linux64"
  user_data   = var.worker_configs[each.key]

  ssh_keys     = [hcloud_ssh_key.cluster.id]
  firewall_ids = [hcloud_firewall.cluster.id]

  labels = {
    cluster    = var.cluster_name
    managed-by = var.cluster_name
    node-role  = "worker"
    node-name  = each.value.name
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = var.network_id
    ip         = local.private_ips[each.key]
  }

  lifecycle {
    ignore_changes = [user_data, image]
  }
}

resource "null_resource" "install" {
  for_each = merge(
    { for cp in var.control_planes : cp.name => cp },
    { for w in var.workers : w.name => w }
  )

  triggers = {
    server_id     = lookup(merge({ for cp in hcloud_server.control_plane : cp.labels["node-name"] => cp.id }, { for w in hcloud_server.worker : w.labels["node-name"] => w.id }), each.value.name)
    talos_version = var.talos_version
    schematic_id  = var.schematic_id
    install_disk  = coalesce(each.value.install_disk, "/dev/sda")
  }

  connection {
    type        = "ssh"
    host        = lookup(merge({ for cp in hcloud_server.control_plane : cp.labels["node-name"] => cp.ipv4_address }, { for w in hcloud_server.worker : w.labels["node-name"] => w.ipv4_address }), each.value.name)
    user        = "root"
    private_key = var.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')",
      "curl -L https://factory.talos.dev/image/${var.schematic_id}/${var.talos_version}/hcloud-$ARCH.raw.xz | xz -d | dd of=${coalesce(each.value.install_disk, "/dev/sda")} bs=4M conv=fsync",
      "sync"
    ]
  }

  depends_on = [hcloud_server.control_plane, hcloud_server.worker, hcloud_ssh_key.cluster]
}

resource "null_resource" "reboot" {
  for_each = merge(
    { for cp in var.control_planes : cp.name => cp },
    { for w in var.workers : w.name => w }
  )

  triggers = {
    install_id = null_resource.install[each.key].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      curl -s -X POST "https://api.hetzner.cloud/v1/servers/${lookup(merge({ for cp in hcloud_server.control_plane : cp.labels["node-name"] => cp.id }, { for w in hcloud_server.worker : w.labels["node-name"] => w.id }), each.value.name)}/actions/reset" \
        -H "Authorization: Bearer ${var.hcloud_token}" \
        -H "Content-Type: application/json" \
        -d '{}'
    EOT
  }

  depends_on = [null_resource.install]
}
