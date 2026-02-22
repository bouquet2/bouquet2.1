variable "domain" {
  type = string
}

variable "internal_domain" {
  type    = string
  default = ""
}

variable "cluster_name" {
  type = string
}

variable "control_planes" {
  type = list(object({
    name = string
  }))
}

variable "workers" {
  type = list(object({
    name = string
  }))
}

variable "control_plane_ips" {
  type = map(string)
}

variable "worker_ips" {
  type = map(string)
}

variable "tailscale_ips" {
  type    = map(string)
  default = {}
}
