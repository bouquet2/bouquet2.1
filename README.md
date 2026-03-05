> [!WARNING]
> Please note that this project has not been tested in a production capacity. It has undergone extensive testing, but never ran production workloads.

<img src="https://raw.githubusercontent.com/xelab04/ServiceLogos/refs/heads/main/Kubernetes/Kubernetes%20V3.png"  height="100">

## bouquet2.1

Infinitely scalable, multi-cloud, secure and network-agnostic declarative Kubernetes configuration provisioned with OpenTofu that focuses on stability and simplicity, while not compromising on modularity.

A fresh take on [bouquet2](https://github.com/bouquet2/bouquet2) based on the mistakes learned while managing it.


## Differences compared to bouquet2
* Rewritten from ground-up with LLMs
* No Kubernetes manifests (yet)
* Use `null_resource` on OpenTofu instead of doing cleanup with `just`
* Fully Cilium-compliant (fully passes `cilium connectivity test`)
  * Also uses Cilium WireGuard for pod-to-pod communication (node-to-node is handled by Tailscale)
* Cilium is now managed by in-line manifests entirely
* Custom hooks that allow removal/addition of nodes as well as in-place machineconfig support
* Custom hook that allows removal of Tailscale nodes automatically (was a drawback on bouquet2)
* No packer required for setup
  * Uses rescue mode in Hetzner in order to install Talos Linux
  * or local-exec on GCP
* Cleaner structure that is easier to read and improve
* Supports multiple Cloud providers
  * GCP and Hetzner currently supported, AWS is coming soon(tm)
* Automatically gets the latest Kubernetes and Talos Linux version for the cluster
* Dynamic provider initialization via Terragrunt — Google and 1Password providers are only loaded when actually needed

## Setup

### Prerequisites

#### Cloud Providers
* Hetzner
  * [Hetzner Console API key](https://docs.hetzner.com/cloud/api/getting-started/generating-api-token/)
* Google Cloud Platform (GCP)
  * Authenticate using Application Default Credentials (ADC):
    ```bash
    gcloud auth application-default login
    ```
  * Service Account with the following IAM roles:
    * `roles/compute.admin` - Manage compute instances, images, and firewalls
    * `roles/storage.admin` - Manage GCS buckets for Talos images
    * `roles/iam.serviceAccountUser` - Required if using service accounts on instances

#### Software
* [OpenTofu](https://opentofu.org)
* [Terragrunt](https://terragrunt.gruntwork.io)
* [kubectl](https://kubernetes.io/docs/tasks/tools/)
* [talosctl](https://www.talos.dev/v1.9/introduction/quickstart/#talosctl)

#### Credentials
* [Tailscale OAuth Secret and ID with RW on devices:core, auth_keys, acl](https://tailscale.com/docs/features/oauth-clients)
  * If you don't enable `manage_acl` you will have to add the required role and ACL yourself.
* [Hetzner Console API key](https://docs.hetzner.com/cloud/api/getting-started/generating-api-token/)
* [GCP Application Default Credentials](https://cloud.google.com/docs/authentication/provide-credentials-adc) - Run `gcloud auth application-default login`
* [Cloudflare API key with Zone.DNS Edit permission](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
  * Currently only Cloudflare DNS is supported, Hetzner might be added at some point

### Setup

#### Config file

```bash
cp config.json.example config.json
vim config.json
```

Multiple configs are supported via the `B_CFG` environment variable:

```bash
# Default: reads config.json
terragrunt plan

# Alternate config
B_CFG=config2.json terragrunt plan
```

#### Secrets (choose one method)

**Option 1: secrets.tfvars (default)**

```bash
cp secrets.tfvars.example secrets.tfvars
vim secrets.tfvars  # add your secrets
```

**Option 2: 1Password**

Set `enable_onepassword = true` in your `config.json` and provide your account:

```json
{
  "enable_onepassword": true,
  "onepassword_account": "your-account.1password.com"
}
```

1. Enable "Integrate with other apps" in the 1Password desktop app
   (Settings > Developer > Integrate with the 1Password SDKs)
2. Create items in your vault (default: `Infrastructure`):
   - `bouquet-hcloud-token` — Hetzner Cloud API token (password field)
   - `bouquet-cloudflare-api-token` — Cloudflare API token (password field)
   - `bouquet-tailscale-oauth-secret` — Tailscale OAuth secret (if using Tailscale)
   - `bouquet-tailscale-oauth-client-id` — Tailscale OAuth client ID (if using Tailscale)

#### Deploy

```bash
# Default config (config.json) + secrets.tfvars auto-loaded
terragrunt init
terragrunt plan
terragrunt apply

# Alternate config
B_CFG=config2.json terragrunt plan
B_CFG=config2.json terragrunt apply

# Destroying the cluster
terragrunt destroy
B_CFG=config2.json terragrunt destroy
```



## Servers

> [!TIP]
> This is just the default configuration, you can configure the nodes however you want.

### Hetzner Cloud Example

* rose
    * Cloud: Hetzner Cloud
    * Region: Helsinki
    * OS: Talos Linux
    * Role: Control plane node
    * Machine: CX23 (Intel) with 2 vCPU, 4GB RAM, 40GB storage
 
* tulip
    * Cloud: Hetzner Cloud
    * Region: Helsinki
    * OS: Talos Linux
    * Role: Worker node
    * Machine: CX23 (Intel) with 2 vCPU, 4GB RAM, 40GB storage

### GCP Example

* lily
    * Cloud: Google Cloud Platform
    * Region: us-central1
    * OS: Talos Linux
    * Role: Control plane node
    * Machine: e2-standard-2 with 2 vCPU, 8GB RAM, 50GB storage

* orchid
    * Cloud: Google Cloud Platform
    * Region: us-central1
    * OS: Talos Linux
    * Role: Worker node
    * Machine: e2-standard-2 with 2 vCPU, 8GB RAM, 50GB storage

### System Architecture Overview
```mermaid
graph LR
    classDef dashed stroke-dasharray: 5 5, stroke-width:1px

    subgraph Hetzner [hetzner cluster]
        direction TB
        hetzner_rose["rose (control plane)"]
        hetzner_tulip["tulip (worker)"]
    end

    subgraph GCP [gcp cluster]
        direction TB
        gcp_lily["lily (control plane)"]
        gcp_orchid["orchid (worker)"]
    end

    core_tailscale["Tailscale<br>(node-to-node) (UDP 41641)"]:::dashed
    core_cilium_wireguard["Cilium WireGuard<br>(pod-to-pod) (UDP 51871)"]:::dashed

    core_tailscale <--> hetzner_rose
    core_tailscale <--> hetzner_tulip
    core_tailscale <--> gcp_lily
    core_tailscale <--> gcp_orchid
    core_cilium_wireguard <--> hetzner_rose
    core_cilium_wireguard <--> hetzner_tulip
    core_cilium_wireguard <--> gcp_lily
    core_cilium_wireguard <--> gcp_orchid
```

## License

bouquet2.1 is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

bouquet2.1 is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with bouquet2.1.  If not, see <https://www.gnu.org/licenses/>.

