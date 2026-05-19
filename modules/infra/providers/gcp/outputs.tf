output "control_plane_ips" {
  value = {
    for cp in google_compute_instance.control_plane :
    cp.labels["node-name"] => cp.network_interface[0].access_config[0].nat_ip
  }
}

output "control_plane_internal_ips" {
  value = {
    for cp in google_compute_instance.control_plane :
    cp.labels["node-name"] => cp.network_interface[0].network_ip
  }
}

output "worker_ips" {
  value = {
    for w in google_compute_instance.worker :
    w.labels["node-name"] => w.network_interface[0].access_config[0].nat_ip
  }
}

output "worker_internal_ips" {
  value = {
    for w in google_compute_instance.worker :
    w.labels["node-name"] => w.network_interface[0].network_ip
  }
}

output "instance_ids" {
  value = concat(
    [for cp in google_compute_instance.control_plane : cp.id],
    [for w in google_compute_instance.worker : w.id]
  )
}

output "install_complete" {
  value = concat(
    [for cp in google_compute_instance.control_plane : cp.id],
    [for w in google_compute_instance.worker : w.id]
  )
}

output "vpc_self_link" {
  value = var.network != "default" ? var.network : google_compute_network.vpc[0].self_link
}

output "vpc_name" {
  value = var.network != "default" ? var.network : google_compute_network.vpc[0].name
}

output "ceph_disk_ids" {
  value = local.ceph_enabled ? [for disk in google_compute_disk.ceph_osd : disk.id] : []
}
