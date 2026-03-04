output "control_plane_ips" {
  value = { for cp in hcloud_server.control_plane : cp.labels["node-name"] => cp.ipv4_address }
}

output "control_plane_ipv6s" {
  value = { for cp in hcloud_server.control_plane : cp.labels["node-name"] => cp.ipv6_address }
}

output "worker_ips" {
  value = { for w in hcloud_server.worker : w.labels["node-name"] => w.ipv4_address }
}

output "worker_ipv6s" {
  value = { for w in hcloud_server.worker : w.labels["node-name"] => w.ipv6_address }
}

output "server_ids" {
  value = concat(
    [for cp in hcloud_server.control_plane : cp.id],
    [for w in hcloud_server.worker : w.id]
  )
}

output "control_plane_provider_ids" {
  value = { for cp in hcloud_server.control_plane : cp.labels["node-name"] => "hcloud://${cp.id}" }
}

output "worker_provider_ids" {
  value = { for w in hcloud_server.worker : w.labels["node-name"] => "hcloud://${w.id}" }
}

output "install_complete" {
  value = values(null_resource.reboot)[*].id
}

output "server_public_ips" {
  value = {
    ipv4 = concat(
      [for cp in hcloud_server.control_plane : cp.ipv4_address],
      [for w in hcloud_server.worker : w.ipv4_address]
    )
    ipv6 = concat(
      [for cp in hcloud_server.control_plane : cp.ipv6_address],
      [for w in hcloud_server.worker : w.ipv6_address]
    )
  }
}
