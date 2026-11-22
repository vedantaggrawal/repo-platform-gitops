---
paths:
  - "manifests/cluster-dns/**"
  - "manifests/cloudflared/**"
  - "manifests/routes/**"
  - "manifests/gateway/**"
  - "network-policies/**"
  - "platform-apps/foundation/cilium/**"
  - "platform-apps/networking/**"
---
# Networking (local env)

- **Three name families, one gateway (`:30443` on the host).**
  - `<app>.local.evelab.space`: canonical. Public DNS `A *.local -> 127.0.0.1` (laptop only, nothing exposed);
    CoreDNS (`manifests/cluster-dns`) answers the same names with the host IP so pods use the browser's URLs.
    TLS: Let's Encrypt wildcard `*.local.evelab.space` via Cloudflare DNS-01 (`manifests/gateway/certificate-public.yaml`).
  - `<app>.evelab.space`: public, via Cloudflare Tunnel only (`manifests/cloudflared`). An app is public only if its
    HTTPRoute lists this name. Never for video (Jellyfin) or anything without an Authentik/JWT gate.
  - `local.<app>.internal`: legacy private CA names, being retired. Do not add new ones.
- **Tunnel origin trick.** The dashboard has ONE rule `*.evelab.space -> https://<gateway svc>:443` with
  Origin Server Name `tunnel.local.evelab.space`: cloudflared validates the gateway's existing wildcard cert by that SNI,
  Envoy routes by the Host header. No `*.evelab.space` certificate exists or is needed in the cluster; browsers get
  Cloudflare's Universal SSL. Change the trick only by adding the SAN and dropping the server-name override, never by
  switching on "No TLS Verify".
- **Pods reach the host over IPv4 only.** AAAA lookups return an empty NOERROR.
- **No inbound ports, no public IP, Cloudflare proxy off for `*.local`.** Exposure is opt-in per route, never per DNS.
