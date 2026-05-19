variable "cluster_name" { type = string }
variable "cluster_config" { type = any }
variable "control_plane_ips" { type = map(string) }
variable "worker_ips" { type = map(string) }
variable "kubeconfig_raw" { type = string, sensitive = true }

variable "cilium" { type = any }
variable "network" { type = any }
variable "dns" { type = any }
variable "tailscale" { type = any }
variable "tailscale_ips" { type = map(string), default = {} }

# For Clustermesh (requires all other clusters' kubeconfigs and IPs)
variable "all_cluster_kubeconfigs" { type = map(string), sensitive = true, default = {} }
variable "all_control_plane_tailscale_ips" { type = map(string), default = {} }
