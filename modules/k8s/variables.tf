variable "cluster_name" {
  type = string
}

variable "workers" {
  type = list(object({
    name         = string
    server_type  = optional(string)
    location     = optional(string)
    install_disk = optional(string)
  }))
  default = []
}

variable "control_planes" {
  type = list(object({
    name         = string
    server_type  = optional(string)
    location     = optional(string)
    install_disk = optional(string)
  }))
  default = []
}

variable "kubeconfig" {
  type      = string
  sensitive = true
}
