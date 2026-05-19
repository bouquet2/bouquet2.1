locals {
  kubeconfig_path = var.kubeconfig_path != "" ? var.kubeconfig_path : "${path.module}/.kubeconfig"
}

resource "null_resource" "ceph_namespace" {
  triggers = {
    namespace = var.namespace
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl --kubeconfig ${var.kubeconfig_path} get ns ${var.namespace} 2>/dev/null || \
        kubectl --kubeconfig ${var.kubeconfig_path} create ns ${var.namespace}
      kubectl --kubeconfig ${var.kubeconfig_path} label ns ${var.namespace} \
        pod-security.kubernetes.io/enforce=privileged \
        pod-security.kubernetes.io/enforce-version=latest \
        --overwrite
    EOT
  }
}

resource "helm_release" "rook_operator" {
  name             = "rook-ceph"
  repository       = "https://charts.rook.io/release"
  chart            = "rook-ceph"
  namespace        = var.namespace
  create_namespace = false
  version          = var.rook_version != null ? var.rook_version : "v1.19.2"

  set = [
    {
      name  = "enableDiscoveryDaemon"
      value = "false"
    },
    {
      name  = "csi.pluginTolerations[0].key"
      value = "node-role.kubernetes.io/control-plane"
    },
    {
      name  = "csi.pluginTolerations[0].operator"
      value = "Exists"
    },
    {
      name  = "csi.pluginTolerations[0].effect"
      value = "NoSchedule"
    },
    {
      name  = "csi.provisionerTolerations[0].key"
      value = "node-role.kubernetes.io/control-plane"
    },
    {
      name  = "csi.provisionerTolerations[0].operator"
      value = "Exists"
    },
    {
      name  = "csi.provisionerTolerations[0].effect"
      value = "NoSchedule"
    },
    {
      name  = "csi.cephfs.provisioner.replicas"
      value = tostring(local.csi.cephfs_provisioner_replicas)
    },
    {
      name  = "csi.rbd.provisioner.replicas"
      value = tostring(local.csi.rbd_provisioner_replicas)
    }
  ]

  # Set CSI resource blocks as YAML strings for full control over all containers
  set_sensitive = [
    {
      name  = "csi.csiRBDPluginResource"
      value = local.csi_rbd_plugin_resources
    },
    {
      name  = "csi.csiCephFSPluginResource"
      value = local.csi_cephfs_plugin_resources
    },
    {
      name  = "csi.csiRBDProvisionerResource"
      value = local.csi_rbd_provisioner_resources
    },
    {
      name  = "csi.csiCephFSProvisionerResource"
      value = local.csi_cephfs_provisioner_resources
    }
  ]

  timeout = 600
  wait    = false

  lifecycle {
    ignore_changes = all
  }
}

locals {
  # Helper to safely get CSI resource config - converts list to YAML or uses string
  csi_rbd_plugin_resources = try(
    trimspace(yamlencode(var.csi.rbd_plugin_resources)),
    local.default_rbd_plugin_resources
  )
  csi_cephfs_plugin_resources = try(
    trimspace(yamlencode(var.csi.cephfs_plugin_resources)),
    local.default_cephfs_plugin_resources
  )
  csi_rbd_provisioner_resources = try(
    trimspace(yamlencode(var.csi.rbd_provisioner_resources)),
    local.default_rbd_provisioner_resources
  )
  csi_cephfs_provisioner_resources = try(
    trimspace(yamlencode(var.csi.cephfs_provisioner_resources)),
    local.default_cephfs_provisioner_resources
  )

  # Default CSI resource configurations (used if not provided in var.csi)
  default_rbd_plugin_resources = <<-EOT
- name : driver-registrar
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
- name : csi-rbdplugin
  resource:
    requests:
      memory: 256Mi
      cpu: 50m
    limits:
      memory: 512Mi
- name : liveness-prometheus
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
EOT

  default_cephfs_plugin_resources = <<-EOT
- name : driver-registrar
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
- name : csi-cephfsplugin
  resource:
    requests:
      memory: 256Mi
      cpu: 50m
    limits:
      memory: 512Mi
- name : liveness-prometheus
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
EOT

  default_rbd_provisioner_resources = <<-EOT
- name : csi-provisioner
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
- name : csi-resizer
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
- name : csi-attacher
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
- name : csi-snapshotter
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
- name : csi-rbdplugin
  resource:
    requests:
      memory: 256Mi
    limits:
      memory: 512Mi
- name : liveness-prometheus
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
EOT

  default_cephfs_provisioner_resources = <<-EOT
- name : csi-provisioner
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
- name : csi-resizer
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
- name : csi-attacher
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
- name : csi-snapshotter
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
- name : csi-cephfsplugin
  resource:
    requests:
      memory: 256Mi
      cpu: 50m
    limits:
      memory: 512Mi
- name : liveness-prometheus
  resource:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
EOT

  # Merge CSI config with defaults for simple values (exclude resource arrays)
  csi = merge({
    rbd_provisioner_replicas    = 1
    cephfs_provisioner_replicas = 1
    rbd_node_plugin_cpu         = "50m"
    cephfs_node_plugin_cpu      = "50m"
  }, var.csi)

  mon_resources = {
    cpu    = lookup(lookup(var.resources, "mon", {}), "cpu", "200m")
    memory = lookup(lookup(var.resources, "mon", {}), "memory", "512Mi")
  }
  mgr_resources = {
    cpu    = lookup(lookup(var.resources, "mgr", {}), "cpu", "200m")
    memory = lookup(lookup(var.resources, "mgr", {}), "memory", "512Mi")
  }
  osd_resources = {
    cpu    = lookup(lookup(var.resources, "osd", {}), "cpu", "200m")
    memory = lookup(lookup(var.resources, "osd", {}), "memory", "1Gi")
  }
  mds_resources = {
    cpu    = lookup(lookup(var.resources, "mds", {}), "cpu", "200m")
    memory = lookup(lookup(var.resources, "mds", {}), "memory", "512Mi")
  }

  sc_block_default = var.storageclass_default == "block"
  sc_fs_default    = var.storageclass_default == "fs"

  objectstore_config = var.objectstore_enabled ? [
    {
      name = var.objectstore_name
      spec = {
        metadataPool = {
          failureDomain = "host"
          replicated = {
            size = var.objectstore_pool_replicas
          }
        }
        dataPool = {
          failureDomain = "host"
          erasureCoded = {
            dataChunks   = 2
            codingChunks = 1
          }
          parameters = {
            bulk = "true"
          }
        }
        preservePoolsOnDelete = false
        gateway = {
          port      = 80
          instances = 1
        }
      }
      storageClass = {
        enabled       = true
        name          = "ceph-bucket"
        reclaimPolicy = "Delete"
      }
    }
  ] : []

  storage_config = length(var.osd_devices) > 0 ? {
    useAllNodes      = false
    useAllDevices    = false
    devicePathFilter = ""
    nodes = [
      for node_name, device_path in var.osd_devices : {
        name    = node_name
        devices = [{ name = device_path }]
      }
    ]
    } : length(var.osd_nodes) > 0 ? {
    useAllNodes      = false
    useAllDevices    = false
    devicePathFilter = var.device_filter
    nodes            = [for name in var.osd_nodes : { name = name, devices = [] }]
    } : {
    useAllNodes      = true
    useAllDevices    = false
    devicePathFilter = var.device_filter
    nodes            = []
  }
}

resource "helm_release" "rook_ceph_cluster" {
  name             = "rook-ceph-cluster"
  repository       = "https://charts.rook.io/release"
  chart            = "rook-ceph-cluster"
  namespace        = var.namespace
  create_namespace = false
  version          = var.rook_version != null ? var.rook_version : "v1.19.2"

  wait    = false
  timeout = 60

  lifecycle {
    ignore_changes = all
  }

  values = [yamlencode({
    cephClusterSpec = {
      dataDirHostPath                            = var.data_dir
      skipUpgradeChecks                          = true
      continueUpgradeAfterChecksEvenIfNotHealthy = true

      mon = {
        count                = var.mon_count
        allowMultiplePerNode = var.mon_allow_multiple_per_node
      }
      mgr = {
        count                = var.mgr_count
        allowMultiplePerNode = true
      }
      dashboard = {
        enabled = var.dashboard_enabled
        ssl     = var.dashboard_ssl
      }
      network = {
        connections = {
          encryption  = { enabled = false }
          compression = { enabled = false }
        }
      }
      crashCollector = { disable = false }
      logCollector = {
        enabled     = true
        periodicity = "daily"
        maxLogSize  = "500M"
      }
      resources = {
        mon = {
          requests = local.mon_resources
        }
        mgr = {
          requests = local.mgr_resources
        }
        osd = {
          requests = local.osd_resources
        }
        mds = {
          requests = local.mds_resources
        }
      }
      storage = local.storage_config
    }
    cephBlockPools = var.storageclass_block ? [
      {
        name = "ceph-blockpool"
        spec = {
          failureDomain = "host"
          replicated = {
            size = var.mon_count
          }
        }
        storageClass = {
          enabled              = true
          isDefault            = var.storageclass_default == "block"
          name                 = "ceph-block"
          reclaimPolicy        = "Delete"
          allowVolumeExpansion = true
          parameters = {
            "csi.storage.k8s.io/fstype"                       = "ext4"
            "csi.storage.k8s.io/provisioner-secret-name"      = "rook-csi-rbd-provisioner"
            "csi.storage.k8s.io/provisioner-secret-namespace" = "rook-ceph"
            "csi.storage.k8s.io/node-stage-secret-name"       = "rook-csi-rbd-node"
            "csi.storage.k8s.io/node-stage-secret-namespace"  = "rook-ceph"
            "mounter"                                         = "rbd-nbd"
          }
        }
      }
    ] : []
    cephFileSystems = var.cephfs_enabled ? [
      {
        name = var.cephfs_name
        spec = {
          metadataPool = {
            failureDomain = "host"
            replicated = {
              size = var.cephfs_metadata_pool_replicas
            }
          }
          dataPools = [{
            failureDomain = "host"
            replicated = {
              size = var.cephfs_data_pool_replicas
            }
          }]
          metadataServer = {
            activeCount   = 1
            activeStandby = false
          }
        }
        storageClass = {
          enabled              = true
          isDefault            = var.storageclass_default == "fs"
          name                 = "ceph-filesystem"
          reclaimPolicy        = "Delete"
          allowVolumeExpansion = true
          parameters = {
            "csi.storage.k8s.io/provisioner-secret-name"      = "rook-csi-cephfs-provisioner"
            "csi.storage.k8s.io/provisioner-secret-namespace" = "rook-ceph"
            "csi.storage.k8s.io/node-stage-secret-name"       = "rook-csi-cephfs-node"
            "csi.storage.k8s.io/node-stage-secret-namespace"  = "rook-ceph"
          }
        }
      }
    ] : []
  })]

  depends_on = [null_resource.ceph_namespace, helm_release.rook_operator]
}
