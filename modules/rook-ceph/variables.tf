variable "cluster_name" {
  type        = string
  description = "Kubernetes cluster name (used for context selection)"
}

variable "kubeconfig_path" {
  type        = string
  default     = ""
  description = "Absolute path to kubeconfig file (set by main.py)"
}

variable "namespace" {
  type        = string
  default     = "rook-ceph"
  description = "Kubernetes namespace to deploy Rook and Ceph into"
}

variable "rook_version" {
  type        = string
  default     = null
  description = "Rook Helm chart version (null = v1.19.2)"
}

# ---------------------------------------------------------------------------
# Storage backend (device mode only — directory mode removed in v1.15+)
# ---------------------------------------------------------------------------

variable "data_dir" {
  type        = string
  default     = "/var/lib/rook"
  description = "dataDirHostPath for Ceph metadata"
}

# ---------------------------------------------------------------------------
# MON / MGR
# ---------------------------------------------------------------------------

variable "mon_count" {
  type        = number
  default     = 1
  description = "Number of Ceph monitor daemons. Use 3 for production HA."
}

variable "mon_allow_multiple_per_node" {
  type        = bool
  default     = true
  description = "Allow multiple MON daemons on the same node. Set false for production."
}

variable "mgr_count" {
  type        = number
  default     = 1
  description = "Number of Ceph manager daemons."
}

# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------

variable "dashboard_enabled" {
  type    = bool
  default = true
}

variable "dashboard_ssl" {
  type    = bool
  default = false
}

# ---------------------------------------------------------------------------
# CephFS
# ---------------------------------------------------------------------------

variable "cephfs_enabled" {
  type    = bool
  default = true
}

variable "cephfs_name" {
  type    = string
  default = "cephfs"
}

variable "cephfs_metadata_pool_replicas" {
  type    = number
  default = 1
}

variable "cephfs_data_pool_replicas" {
  type    = number
  default = 1
}

# ---------------------------------------------------------------------------
# StorageClasses
# ---------------------------------------------------------------------------

variable "storageclass_block" {
  type        = bool
  default     = true
  description = "Create a StorageClass for Ceph RBD block storage"
}

variable "storageclass_fs" {
  type        = bool
  default     = true
  description = "Create a StorageClass for CephFS shared filesystem"
}

variable "storageclass_default" {
  type        = string
  default     = "fs"
  description = "Which StorageClass to mark as default: \"block\", \"fs\", or \"\" (none)"

  validation {
    condition     = contains(["block", "fs", ""], var.storageclass_default)
    error_message = "storageclass_default must be \"block\", \"fs\", or \"\"."
  }
}

variable "objectstore_enabled" {
  type        = bool
  default     = false
  description = "Enable Ceph object store (RGW) for S3-compatible storage"
}

variable "objectstore_name" {
  type        = string
  default     = "ceph-objectstore"
  description = "Name of the Ceph object store"
}

variable "objectstore_pool_replicas" {
  type        = number
  default     = 3
  description = "Replica size for object store pools (metadata and data)"
}

variable "osd_nodes" {
  type        = list(string)
  default     = []
  description = "List of node names that have OSD disks. When empty, useAllNodes=true. When specified, useAllNodes=false with explicit node list."
}

variable "csi" {
  type        = any
  default     = {}
  description = "CSI driver configuration: rbd_provisioner_replicas, cephfs_provisioner_replicas, rbd_node_plugin_cpu, cephfs_node_plugin_cpu, rbd_plugin_resources, cephfs_plugin_resources, rbd_provisioner_resources, cephfs_provisioner_resources"
}

variable "resources" {
  type        = any
  default     = {}
  description = "Resource requests for Ceph daemons. Keys: mon, mgr, osd, mds. Each has cpu and memory."
}
