resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

locals {
  endpoint = var.dns_enabled ? "https://control-planes.${var.cluster_name}.internal.${var.dns_domain}:6443" : "https://placeholder:6443"

  base_config = {
    machine = {
      install = {
        disk = "/dev/sda"
      }
      kubelet = {
        nodeIP = {
          validSubnets = ["100.64.0.0/10", "fd7a:115c:a1e0::/48"]
        }
        extraArgs = {
          rotate-server-certificates = true
        }
      }
    }
  }

  control_plane_config = {
    cluster = {
      network = {
        podSubnets     = var.network.pod_subnets
        serviceSubnets = var.network.service_subnets
      }
      allowSchedulingOnControlPlanes = true
      extraManifests = concat(
        [
          "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml",
          "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
        ],
        var.cilium.enabled && var.cilium.gateway_api ? [
          "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.5.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml",
          "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.5.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml",
          "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.5.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml",
          "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.5.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml",
          "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.5.0/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml"
        ] : []
      )
    }
  }

  cilium_config = var.cilium.enabled ? {
    cluster = {
      network = {
        cni = {
          name = "none"
        }
      }
      proxy = {
        disabled = true
      }
      inlineManifests = concat(
        [
          {
            name     = "cilium-install"
            contents = templatefile("${path.module}/templates/cilium.yaml", {
              cluster_id             = var.cluster_id
              cluster_name           = var.cluster_name
              cilium_version         = var.cilium_version
              clustermesh_enabled    = var.cilium.clustermesh ? "--set clustermesh.useAPIServer=true --set clustermesh.config.enabled=true --set clustermesh.apiserver.service.type=${var.clustermesh_service_type}" : ""
              gateway_api_enabled    = var.cilium.gateway_api ? join(" ", [
                "--set gatewayAPI.enabled=true",
                "--set gatewayAPI.hostNetwork.enabled=true",
                "--set envoy.securityContext.capabilities.keepCapNetBindService=true",
                "--set envoy.securityContext.capabilities.envoy={NET_ADMIN,SYS_ADMIN,NET_BIND_SERVICE}",
              ]) : ""
              encryption_flags       = var.cilium.encryption_enabled ? join(" ", [
                "--set encryption.enabled=true",
                "--set encryption.type=${var.cilium.encryption_type}",
                "--set encryption.nodeEncryption=${var.cilium.node_encryption}",
              ]) : ""
            })
          }
        ],
        var.hcloud_token != "" && var.hetzner_loadbalancer_enabled ? [
          {
            name     = "hcloud-ccm"
            contents = templatefile("${path.module}/templates/hcloud-ccm.yaml", {
              hcloud_token      = var.hcloud_token
              hcloud_network_id = var.hcloud_network_id != null ? tostring(var.hcloud_network_id) : ""
            })
          }
        ] : []
      )
    }
  } : {}

  tailscale_config = var.tailscale_enabled ? {
    machine = {
      network = {
        nameservers = ["100.100.100.100", "1.1.1.1", "8.8.8.8"]
        interfaces = [
          {
            interface = "tailscale0"
            routes = [
              {
                # Route the entire Tailscale CGNAT range via tailscale0 in the main
                # routing table so that Cilium (which bypasses ip rule policy routing)
                # can forward pod traffic to Tailscale peers on other clusters.
                network = "100.64.0.0/10"
                metric  = 100
              }
            ]
          }
        ]
      }
      sysctls = {
        "net.ipv4.ip_forward"          = "1"
        "net.ipv6.conf.all.forwarding" = "1"
      }
    }
  } : {}
}

data "talos_machine_configuration" "control_plane" {
  for_each = { for cp in var.control_planes : cp.name => cp }

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = compact([
    jsonencode(local.base_config),
    jsonencode(local.control_plane_config),
    jsonencode(local.cilium_config),
    jsonencode(local.tailscale_config),
    var.tailscale_enabled ? yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "tailscale"
      environment = concat([
        "TS_AUTHKEY=${var.tailscale_auth_key}",
        "TS_HOSTNAME=${var.cluster_name}-${each.key}",
        "TS_ACCEPT_DNS=true"
      ], length(var.tailscale_routes) > 0 ? ["TS_ROUTES=${join(",", var.tailscale_routes)}"] : [])
    }) : null
  ])
}

data "talos_machine_configuration" "worker" {
  for_each = { for w in var.workers : w.name => w }

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = compact([
    jsonencode(local.base_config),
    jsonencode(local.cilium_config),
    jsonencode(local.tailscale_config),
    var.tailscale_enabled ? yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "tailscale"
      environment = concat([
        "TS_AUTHKEY=${var.tailscale_auth_key}",
        "TS_HOSTNAME=${var.cluster_name}-${each.key}",
        "TS_ACCEPT_DNS=true"
      ], length(var.tailscale_routes) > 0 ? ["TS_ROUTES=${join(",", var.tailscale_routes)}"] : [])
    }) : null
  ])
}
