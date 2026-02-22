data "cloudflare_zone" "this" {
  name = var.domain
}

resource "cloudflare_record" "control_plane_api" {
  for_each = { for cp in var.control_planes : cp.name => cp }

  zone_id = data.cloudflare_zone.this.id
  name    = "control-planes.internal"
  type    = "A"
  content = lookup(var.tailscale_ips, "${var.cluster_name}-${each.value.name}", var.control_plane_ips[each.value.name])
  ttl     = 300
  proxied = false
}

resource "cloudflare_record" "control_plane_internal" {
  for_each = { for cp in var.control_planes : cp.name => cp }

  zone_id = data.cloudflare_zone.this.id
  name    = "${each.value.name}.control-planes.internal"
  type    = "A"
  content = lookup(var.tailscale_ips, "${var.cluster_name}-${each.value.name}", var.control_plane_ips[each.value.name])
  ttl     = 300
  proxied = false
}

resource "cloudflare_record" "worker_internal" {
  for_each = { for w in var.workers : w.name => w }

  zone_id = data.cloudflare_zone.this.id
  name    = "${each.value.name}.workers.internal"
  type    = "A"
  content = lookup(var.tailscale_ips, "${var.cluster_name}-${each.value.name}", var.worker_ips[each.value.name])
  ttl     = 300
  proxied = false
}
