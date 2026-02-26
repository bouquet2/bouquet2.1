output "control_plane_records" {
  value = cloudflare_record.control_plane_api_global
}

output "worker_records" {
  value = cloudflare_record.worker_global
}
