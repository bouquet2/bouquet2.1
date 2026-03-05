# GKE Provider Module

> [!WARNING]
> This module has several limitations due to GKE's architecture. Please read carefully before using.

Google Kubernetes Engine (GKE) provider for bouquet2.1. Provisions a GKE cluster with Cilium CNI and ClusterMesh support.

## Features

- Custom VPC network (not default)
- Private cluster with Cloud NAT
- Cilium CNI with WireGuard encryption
- ClusterMesh support (LoadBalancer type)
- Automatic kubeconfig generation

## Limitations

### IPv6 Not Supported

GKE dual-stack IPv6 requires **Dataplane V2** (ADVANCED_DATAPATH), which uses a managed Cilium installation (`anetd`). Custom Cilium cannot be installed alongside it.

This module uses **LEGACY_DATAPATH** to support custom Cilium, which only supports IPv4 for pods.

### No Tailscale Support

GKE does not support Tailscale integration:
- GKE nodes run a managed OS without the ability to install custom system services
- Tailscale requires kernel-level access that GKE's managed nodes don't provide
- Consider using Cloud VPN or Cloud Interconnect for hybrid connectivity instead

### Cilium WireGuard Limitations with Private Clusters

When `enable_private_cluster: true` (default):

- **GKE nodes have no public IPs** — they're behind Cloud NAT
- **WireGuard mesh incomplete** — Hetzner cannot initiate WireGuard connections to GKE nodes
- **ClusterMesh still works** — uses mTLS on the clustermesh-apiserver (port 2379)
- **Cross-cluster traffic is encrypted** — via clustermesh-apiserver's mTLS tunnel

To get full WireGuard mesh connectivity:
1. Set `enable_private_cluster: false` to give nodes public IPs
2. Ensure firewall allows UDP 51871 between clusters

### Mixed Encryption Not Supported

Cilium requires all clusters in a ClusterMesh to have WireGuard encryption enabled (or all disabled). Mixed mode is not supported.

## Configuration

The Google provider is inherited from the root module — no explicit `providers` pass-through is needed. Set your GCP cluster config in `config.json`:

```json
{
  "clusters": {
    "my-gke": {
      "type": "gke",
      "cluster_id": 2,
      "control_planes": [],
      "workers": [],
      "gcp": {
        "project_id":             "my-project-id",
        "region":                 "us-central1",
        "zone":                   "us-central1-a",
        "network":                "default",
        "subnetwork":             "",
        "enable_private_cluster": true,
        "master_ipv4_cidr_block": "172.16.0.0/28",
        "node_pools": [
          {
            "name":         "default-pool",
            "machine_type": "e2-standard-2",
            "min_count":    1,
            "max_count":    3,
            "disk_size_gb": 50
          }
        ]
      }
    }
  }
}
```

## IAM Requirements

Service account with these roles:
- `roles/container.admin` — Manage GKE clusters
- `roles/compute.networkAdmin` — Manage VPC networks and firewalls
- `roles/iam.serviceAccountUser` — Required for node pools

## Security

| Component | Encryption |
|-----------|------------|
| Intra-cluster pod traffic | WireGuard (UDP 51871) |
| Cross-cluster control plane | mTLS (clustermesh-apiserver) |
| Cross-cluster pod traffic | mTLS tunnel via clustermesh-apiserver |
| API server | GKE managed TLS |

## Troubleshooting

### Cilium not installing

The Cilium install job runs via a Helm install inside the cluster. If it fails:
1. Check node pool has enough resources
2. Verify the cluster is fully provisioned
3. Check `kubectl logs -n kube-system job/helm-install-cilium`

### ClusterMesh connectivity issues

With private clusters:
- GKE → Hetzner: Works (GKE can reach Hetzner's public LoadBalancer)
- Hetzner → GKE: Limited (GKE nodes are private)

This is expected behavior. Cross-cluster operations still work via mTLS.

### WireGuard not working across clusters

If you need full WireGuard mesh:
1. Disable private cluster: `"enable_private_cluster": false`
2. Add firewall rule for UDP 51871
3. Re-apply
