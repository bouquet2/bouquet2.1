#!/usr/bin/env python3
"""Thin wrapper around Terragrunt — generates stack HCL, delegates to terragrunt."""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_CONFIG = "config.json"
STACK_FILE = "terragrunt.stack.hcl"
REPO_ROOT = Path(__file__).parent.resolve()


def load_config(config_path: str) -> dict:
    with open(config_path) as f:
        return json.load(f)


def sanitize_name(name: str) -> str:
    return name.replace("-", "_").replace(".", "_")


# -- HCL unit template --

_UNIT = """\
unit "{unit}" {{
  source = "./modules/infra"
  path   = "{unit}"
  values = merge(
    {{
      cluster_name       = "{cluster}"
      talos_version      = local.talos_version
      kubernetes_version = local.kubernetes_version
      cilium_version     = local.cilium_version
      cluster_config     = local.clusters["{cluster}"]
      primary_cluster    = local.primary_cluster
      cilium             = local.cilium_config
      network            = local.cluster_cidrs["{cluster}"]
      tailscale          = local.tailscale_config
      dns                = local.dns_config
      ceph               = local.ceph_config
      hetzner            = local.hetzner_config
      hcloud_token              = local.hcloud_token
      cloudflare_api_token      = local.cloudflare_api_token
      tailscale_oauth_secret    = local.tailscale_oauth_secret
      tailscale_oauth_client_id = local.tailscale_oauth_client_id
    }}
{extras}
  )
}}
""".rstrip()


def _build_extras(cluster: str, cluster_data: dict) -> str:
    parts = []
    if cluster_data.get("gcp"):
        parts.append(f""",    lookup(local.clusters["{cluster}"], "gcp", null) != null ? {{
      subnet_cidr = local.gcp_clusters["{cluster}"].subnet_cidr
    }} : {{}}""")
    cps = cluster_data.get("control_planes", [])
    wks = cluster_data.get("workers", [])
    if any(p.get("provider") == "hetzner" for p in cps + wks):
        parts.append(f""",    anytrue([for cp in lookup(local.clusters["{cluster}"], "control_planes", []) : cp.provider == "hetzner"]) || anytrue([for w in lookup(local.clusters["{cluster}"], "workers", []) : w.provider == "hetzner"]) ? {{
      hetzner_network_cidr = local.hetzner_clusters["{cluster}"]
    }} : {{}}""")
    return "".join(parts)


def generate_units(config: dict) -> str:
    clusters = config.get("clusters", {})
    if not clusters:
        return ""
    blocks = []
    for cn, cd in clusters.items():
        un = f"infra_{sanitize_name(cn)}"
        extras = _build_extras(cn, cd)
        blocks.append(_UNIT.format(unit=un, cluster=cn, extras=extras))
    return "\n".join(blocks)


# -- HCL clustermesh template --

_MESH_HEADER = """\
terraform {{
  source = "{source}"
}}

dependencies {{
  paths = {dep_paths}
}}
"""


def generate_clustermesh_terragrunt(config: dict) -> str:
    clusters = config.get("clusters", {})
    if len(clusters) <= 1:
        return ""
    source = str(REPO_ROOT / "modules" / "clustermesh")
    dep_paths = [f'"../../.terragrunt-stack/infra_{sanitize_name(cn)}"' for cn in clusters]
    return _MESH_HEADER.format(source=source, dep_paths=f"[{', '.join(dep_paths)}]")


def _run_terragrunt_output(unit_dir: Path, env: dict) -> dict | None:
    try:
        p = subprocess.run(
            ["terragrunt", "output", "--json", "-show-sensitive"],
            cwd=str(unit_dir), capture_output=True, text=True, check=True, env=env,
        )
        return json.loads(p.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
        print(f"Warning: terragrunt output failed for {unit_dir.name}: {e}")
        return None


def _existing_units(config: dict) -> list[tuple[str, Path]]:
    stack_dir = REPO_ROOT / ".terragrunt-stack"
    results = []
    for cn in config.get("clusters", {}):
        unit_dir = stack_dir / f"infra_{sanitize_name(cn)}"
        if unit_dir.exists():
            results.append((cn, unit_dir))
    return results


def write_clustermesh_tfvars(config: dict, env: dict):
    clusters = config.get("clusters", {})
    if len(clusters) <= 1 or not config.get("cilium", {}).get("clustermesh", False):
        return

    kubeconfigs_dir = REPO_ROOT / ".kubeconfigs"
    kubeconfigs_dir.mkdir(parents=True, exist_ok=True)
    kubeconfig_paths = {cn: str(kubeconfigs_dir / cn) for cn in clusters}
    tailscale_ips = {}

    for cn, unit_dir in _existing_units(config):
        outputs = _run_terragrunt_output(unit_dir, env)
        if outputs is None:
            continue
        ips = outputs.get("tailscale_control_plane_ips", {}).get("value", {})
        if ips:
            tailscale_ips[cn] = list(ips.values())[0]

    tfvars_path = REPO_ROOT / "modules" / "clustermesh" / "terraform.tfvars.json"
    tfvars_path.parent.mkdir(parents=True, exist_ok=True)
    with open(tfvars_path, "w") as f:
        json.dump({
            "cluster_names": list(clusters.keys()),
            "kubeconfig_paths": kubeconfig_paths,
            "control_plane_tailscale_ips": tailscale_ips,
        }, f, indent=2)
    print("Updated: modules/clustermesh/terraform.tfvars.json")


def update_stack(config: dict) -> bool:
    stack_path = REPO_ROOT / STACK_FILE
    if not stack_path.exists():
        print(f"Error: {STACK_FILE} not found")
        return False
    content = stack_path.read_text()
    marker = "# Generated units will be appended below by Python script"
    units = generate_units(config)
    if not units:
        print("No clusters found in config")
        return False
    stack_path.write_text(content.split(marker)[0] + marker + "\n\n" + units)
    print(f"Updated: {STACK_FILE}")
    return True


def write_kubeconfig_files(config: dict, env: dict):
    kubeconfigs_dir = REPO_ROOT / ".kubeconfigs"
    kubeconfigs_dir.mkdir(parents=True, exist_ok=True)

    for cn, unit_dir in _existing_units(config):
        outputs = _run_terragrunt_output(unit_dir, env)
        if outputs is None:
            continue
        kubeconfig_raw = outputs.get("kubeconfig_raw", {}).get("value", "")
        if kubeconfig_raw:
            (kubeconfigs_dir / cn).write_text(kubeconfig_raw)


def setup_clustermesh(config: dict, env: dict):
    clusters = config.get("clusters", {})
    mesh_dir = REPO_ROOT / "modules" / "clustermesh"
    if len(clusters) <= 1 or not config.get("cilium", {}).get("clustermesh", False):
        for f in ("terragrunt.hcl", "terraform.tfvars.json"):
            (mesh_dir / f).unlink(missing_ok=True)
        return
    hcl = generate_clustermesh_terragrunt(config)
    if not hcl:
        return
    (mesh_dir / "terragrunt.hcl").write_text(hcl)
    print("Generated: modules/clustermesh/terragrunt.hcl")
    write_clustermesh_tfvars(config, env)
    cache = mesh_dir / ".terragrunt-cache"
    if cache.exists():
        shutil.rmtree(cache)
        print("Cleaned modules/clustermesh/.terragrunt-cache")


def _resolve_unit_dir(module: str) -> Path | None:
    path = REPO_ROOT / ".terragrunt-stack" / module
    if path.exists():
        return path
    path = REPO_ROOT / module
    if path.exists():
        return path
    return None


def _run_saves(save_specs: list, env: dict):
    for spec in save_specs:
        if "=" not in spec:
            print(f"Warning: invalid --save format '{spec}', expected path=module:output")
            continue
        file_path, rest = spec.split("=", 1)
        if ":" not in rest:
            print(f"Warning: invalid --save format '{spec}', expected path=module:output")
            continue
        module, output_name = rest.split(":", 1)

        unit_dir = _resolve_unit_dir(module)
        if unit_dir is None:
            print(f"Warning: unit directory not found for module '{module}'")
            continue

        outputs = _run_terragrunt_output(unit_dir, env)
        if outputs is None:
            continue

        value = outputs.get(output_name, {}).get("value")
        if value is None:
            print(f"Warning: output '{output_name}' not found in module '{module}'")
            continue

        expanded = os.path.expanduser(file_path)
        Path(expanded).parent.mkdir(parents=True, exist_ok=True)
        Path(expanded).write_text(str(value))
        print(f"Saved: {file_path} = {module}:{output_name}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Terragrunt stack runner")
    parser.add_argument("command", nargs="?", default="plan",
                        choices=["plan", "apply", "destroy", "output"])
    parser.add_argument("-c", "--config", default=None,
                        help=f"Config file (default: {DEFAULT_CONFIG}, or B_CFG env var)")
    parser.add_argument("--save", action="append", default=[],
                        help="Save output to file (format: path=module:output)")
    args, unknown = parser.parse_known_args()

    config_path = args.config or os.environ.get("B_CFG", DEFAULT_CONFIG)
    if not os.path.exists(config_path):
        print(f"Error: Config file not found: {config_path}")
        return 1

    config = load_config(config_path)
    env = {**os.environ, "B_CFG": config_path}

    try:
        subprocess.run(["terragrunt", "stack", "clean"], capture_output=True, env=env, check=True)
    except subprocess.CalledProcessError:
        print("Warning: terragrunt stack clean failed (non-fatal)")

    if not update_stack(config):
        return 1

    try:
        subprocess.run(["terragrunt", "stack", "generate"], capture_output=True, env=env, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error: terragrunt stack generate failed: {e}")
        return 1

    write_kubeconfig_files(config, env)
    if args.save and args.command == "destroy":
        _run_saves(args.save, env)
    setup_clustermesh(config, env)

    result = subprocess.run(
        ["terragrunt", "run", "--all", args.command, *unknown], env=env
    )

    write_clustermesh_tfvars(config, env)

    if args.save and args.command != "destroy":
        _run_saves(args.save, env)

    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
