output "control_plane_records" {
  value = cloudflare_record.control_plane_internal
}

output "worker_records" {
  value = cloudflare_record.worker_internal
}
