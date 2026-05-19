output "client_configuration" {
  value     = talos_machine_secrets.this.client_configuration
  sensitive = true
}

output "machine_secrets" {
  value     = talos_machine_secrets.this.machine_secrets
  sensitive = true
}

output "control_plane_configs" {
  value     = { for k, v in data.talos_machine_configuration.control_plane : k => v.machine_configuration }
  sensitive = true
}

output "worker_configs" {
  value     = { for k, v in data.talos_machine_configuration.worker : k => v.machine_configuration }
  sensitive = true
}
