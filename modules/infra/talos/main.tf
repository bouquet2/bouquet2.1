resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

locals {
  gateway_api_version = try(coalesce(data.external.gateway_api_version[0].result.version, var.gateway_api_version), var.gateway_api_version)

  endpoint = var.dns_enabled ? "https://control-planes.${var.cluster_name}.internal.${var.dns_domain}:6443" : "https://placeholder:6443"

  tailscale_node_ip_subnets = ["100.64.0.0/10", "fd7a:115c:a1e0::/48"]

  node_ip_subnets_by_node = {
    for name, provider in var.node_providers : name => (
      provider == "hetzner" || (var.tailscale_enabled && try(var.cilium.clustermesh, false)) ? local.tailscale_node_ip_subnets : var.node_ip_subnets
    )
  }

  node_ip_config_default = {
    machine = {
      kubelet = {
        nodeIP = {
          validSubnets = var.node_ip_subnets
        }
      }
    }
  }

  node_ip_config_by_node = {
    for name, subnets in local.node_ip_subnets_by_node : name => {
      machine = {
        kubelet = {
          nodeIP = {
            validSubnets = subnets
          }
        }
      }
    }
  }

  base_config = {
    machine = {
      install = {
        disk = "/dev/sda"
      }
      kernel = {
        modules = [
          {
            name = "nbd"
          },
          {
            name = "rbd"
          }
        ]
      }
      sysctls = {
        "net.ipv6.ip_nonlocal_bind"       = "1"
        "net.ipv6.conf.all.forwarding"    = "1"
        "net.ipv6.conf.all.disable_ipv6"  = "0"
        "net.ipv4.ip_forward"             = "1"
        "net.ipv4.conf.all.rp_filter"     = "0"
        "net.ipv4.conf.default.rp_filter" = "0"
      }
      kubelet = {
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
      apiServer = {
        certSANs = concat([
          "control-planes.${var.cluster_name}.internal.${var.dns_domain}"
        ], var.dns_enabled ? [] : ["placeholder"])
      }
      allowSchedulingOnControlPlanes = true
      extraManifests = concat(
        [
          "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml",
          "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
        ],
        var.cilium.enabled && var.cilium.gateway_api ? [
          "https://github.com/kubernetes-sigs/gateway-api/releases/download/${local.gateway_api_version}/experimental-install.yaml"
        ] : []
      )
    }
  }

  cilium_routing_flags_by_node = {
    for name, provider in var.node_providers : name => (
      provider == "hetzner" ? "" : (
        var.cilium.routing_mode == "native" ? join(" ", [
          "--set routingMode=native",
          "--set autoDirectNodeRoutes=true",
          "--set ipv4NativeRoutingCIDR=10.0.0.0/8",
          "--set ipv6NativeRoutingCIDR=fd00::/48",
          ]) : join(" ", [
          "--set routingMode=tunnel",
          "--set tunnelProtocol=vxlan",
          "--set MTU=1400",
        ])
      )
    )
  }

  cilium_config_default = var.cilium.enabled ? {
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
            name = "cilium-install"
            contents = templatefile("${path.module}/templates/cilium.yaml", {
              cluster_id     = var.cluster_id
              cluster_name   = var.cluster_name
              cilium_version = var.cilium_version
              routing_mode   = var.cilium.routing_mode
              routing_flags = var.cilium.routing_mode == "native" ? join(" ", [
                "--set routingMode=native",
                "--set autoDirectNodeRoutes=true",
                "--set ipv4NativeRoutingCIDR=10.0.0.0/8",
                "--set ipv6NativeRoutingCIDR=fd00::/48",
                ]) : join(" ", [
                "--set routingMode=tunnel",
                "--set tunnelProtocol=vxlan",
                "--set MTU=1400",
              ])
              clustermesh_enabled = var.cilium.clustermesh ? "--set clustermesh.useAPIServer=true --set clustermesh.config.enabled=true --set clustermesh.apiserver.service.type=${var.clustermesh_service_type}" : ""
              gateway_api_enabled = var.cilium.gateway_api ? join(" ", [
                "--set gatewayAPI.enabled=true",
                "--set gatewayAPI.hostNetwork.enabled=true",
                "--set envoy.securityContext.capabilities.keepCapNetBindService=true",
                "--set envoy.securityContext.capabilities.envoy={NET_ADMIN,SYS_ADMIN,NET_BIND_SERVICE}",
              ]) : ""
              encryption_flags = var.cilium.encryption_enabled ? join(" ", [
                "--set encryption.enabled=true",
                "--set encryption.type=${var.cilium.encryption_type}",
                "--set encryption.nodeEncryption=${var.cilium.node_encryption}",
              ]) : ""
            })
          }
        ],
        var.hcloud_token != null && var.hcloud_token != "" && var.hetzner_loadbalancer_enabled ? [
          {
            name = "hcloud-ccm"
            contents = templatefile("${path.module}/templates/hcloud-ccm.yaml", {
              hcloud_token      = var.hcloud_token
              hcloud_network_id = var.hcloud_network_id != null ? tostring(var.hcloud_network_id) : ""
            })
          }
        ] : []
      )
    }
  } : {}

  cilium_config_by_node = var.cilium.enabled ? {
    for name, provider in var.node_providers : name => {
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
              name = "cilium-install"
              contents = templatefile("${path.module}/templates/cilium.yaml", {
                cluster_id          = var.cluster_id
                cluster_name        = var.cluster_name
                cilium_version      = var.cilium_version
                routing_mode        = var.cilium.routing_mode
                routing_flags       = lookup(local.cilium_routing_flags_by_node, name, "")
                clustermesh_enabled = var.cilium.clustermesh ? "--set clustermesh.useAPIServer=true --set clustermesh.config.enabled=true --set clustermesh.apiserver.service.type=${var.clustermesh_service_type}" : ""
                gateway_api_enabled = var.cilium.gateway_api ? join(" ", [
                  "--set gatewayAPI.enabled=true",
                  "--set gatewayAPI.hostNetwork.enabled=true",
                  "--set envoy.securityContext.capabilities.keepCapNetBindService=true",
                  "--set envoy.securityContext.capabilities.envoy={NET_ADMIN,SYS_ADMIN,NET_BIND_SERVICE}",
                ]) : ""
                encryption_flags = var.cilium.encryption_enabled ? join(" ", [
                  "--set encryption.enabled=true",
                  "--set encryption.type=${var.cilium.encryption_type}",
                  "--set encryption.nodeEncryption=${var.cilium.node_encryption}",
                ]) : ""
              })
            }
          ],
          var.hcloud_token != null && var.hcloud_token != "" && var.hetzner_loadbalancer_enabled ? [
            {
              name = "hcloud-ccm"
              contents = templatefile("${path.module}/templates/hcloud-ccm.yaml", {
                hcloud_token      = var.hcloud_token
                hcloud_network_id = var.hcloud_network_id != null ? tostring(var.hcloud_network_id) : ""
              })
            }
          ] : []
        )
      }
    }
  } : {}

  hetzner_etcd_subnets = concat(
    var.hetzner_network_cidr != "" ? [var.hetzner_network_cidr] : [],
    var.tailscale_enabled ? local.tailscale_node_ip_subnets : []
  )

  node_etcd_config_by_node = {
    for name, provider in var.node_providers : name => (
      provider == "hetzner" && length(local.hetzner_etcd_subnets) > 0 ? {
        cluster = {
          etcd = {
            advertisedSubnets = local.hetzner_etcd_subnets
            listenSubnets     = local.hetzner_etcd_subnets
          }
        }
      } : null
    )
  }

  node_hetzner_eth1_link_config_by_node = {
    for name, provider in var.node_providers : name => (
      provider == "hetzner" ? {
        apiVersion = "v1alpha1"
        kind       = "LinkConfig"
        name       = "eth1"
        up         = true
        mtu        = 1450
      } : null
    )
  }

  node_hetzner_eth0_dhcp_config_by_node = {
    for name, provider in var.node_providers : name => (
      provider == "hetzner" ? {
        apiVersion = "v1alpha1"
        kind       = "DHCPv4Config"
        name       = "eth0"
      } : null
    )
  }

  node_hetzner_eth1_dhcp_config_by_node = {
    for name, provider in var.node_providers : name => (
      provider == "hetzner" ? {
        apiVersion = "v1alpha1"
        kind       = "DHCPv4Config"
        name       = "eth1"
      } : null
    )
  }

  node_resolver_config_by_node = {
    for name, provider in var.node_providers : name => (
      var.tailscale_enabled ? {
        apiVersion = "v1alpha1"
        kind       = "ResolverConfig"
        nameservers = [
          { address = "100.100.100.100" },
          { address = "1.1.1.1" },
          { address = "8.8.8.8" }
        ]
      } : null
    )
  }
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
    jsonencode(lookup(local.node_ip_config_by_node, each.key, local.node_ip_config_default)),
    jsonencode(local.control_plane_config),
    local.node_etcd_config_by_node[each.key] != null ? jsonencode(local.node_etcd_config_by_node[each.key]) : null,
    local.node_hetzner_eth1_link_config_by_node[each.key] != null ? yamlencode(local.node_hetzner_eth1_link_config_by_node[each.key]) : null,
    local.node_hetzner_eth0_dhcp_config_by_node[each.key] != null ? yamlencode(local.node_hetzner_eth0_dhcp_config_by_node[each.key]) : null,
    local.node_hetzner_eth1_dhcp_config_by_node[each.key] != null ? yamlencode(local.node_hetzner_eth1_dhcp_config_by_node[each.key]) : null,
    local.node_resolver_config_by_node[each.key] != null ? yamlencode(local.node_resolver_config_by_node[each.key]) : null,
    jsonencode(lookup(local.cilium_config_by_node, each.key, local.cilium_config_default)),
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

data "external" "gateway_api_version" {
  count = var.cilium.enabled && var.cilium.gateway_api ? 1 : 0

  program = ["bash", "-c", <<-EOT
    VERSION=$(curl -sfL https://api.github.com/repos/kubernetes-sigs/gateway-api/releases/latest | jq -r '.tag_name' 2>/dev/null || echo "")
    echo "{\"version\":\"$VERSION\"}"
  EOT
  ]
}

resource "null_resource" "gateway_api_version" {
  count = var.cilium.enabled && var.cilium.gateway_api ? 1 : 0

  triggers = {
    version = data.external.gateway_api_version[0].result.version
  }
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
    jsonencode(lookup(local.node_ip_config_by_node, each.key, local.node_ip_config_default)),
    jsonencode(lookup(local.cilium_config_by_node, each.key, local.cilium_config_default)),
    local.node_hetzner_eth1_link_config_by_node[each.key] != null ? yamlencode(local.node_hetzner_eth1_link_config_by_node[each.key]) : null,
    local.node_hetzner_eth0_dhcp_config_by_node[each.key] != null ? yamlencode(local.node_hetzner_eth0_dhcp_config_by_node[each.key]) : null,
    local.node_hetzner_eth1_dhcp_config_by_node[each.key] != null ? yamlencode(local.node_hetzner_eth1_dhcp_config_by_node[each.key]) : null,
    local.node_resolver_config_by_node[each.key] != null ? yamlencode(local.node_resolver_config_by_node[each.key]) : null,
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
