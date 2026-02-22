output "control_plane_ips" {
  value = { for cp in hcloud_server.control_plane : cp.labels["node-name"] => cp.ipv4_address }
}

output "worker_ips" {
  value = { for w in hcloud_server.worker : w.labels["node-name"] => w.ipv4_address }
}

output "server_ids" {
  value = concat(
    [for cp in hcloud_server.control_plane : cp.id],
    [for w in hcloud_server.worker : w.id]
  )
}

output "install_complete" {
  value = values(null_resource.reboot)[*].id
}
