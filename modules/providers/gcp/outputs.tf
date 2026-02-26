output "control_plane_ips" {
  value = {
    for cp in google_compute_instance.control_plane :
    cp.labels["node-name"] => cp.network_interface[0].access_config[0].nat_ip
  }
}

output "worker_ips" {
  value = {
    for w in google_compute_instance.worker :
    w.labels["node-name"] => w.network_interface[0].access_config[0].nat_ip
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
