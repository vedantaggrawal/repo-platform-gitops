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

- **Canonical name = `<app>.<cluster>.evelab.space`**, one DNS subtree per cluster; apps only ever know their own
  cluster's name (`root_url`, issuers, callbacks), so moving the front door never touches app config.
  - `*.local.evelab.space` (this laptop): `A *.local -> 127.0.0.1`, private by construction; CoreDNS
    (`manifests/cluster-dns`) answers the same names with the host IP so pods use the browser's URLs.
    TLS: Let's Encrypt wildcard via Cloudflare DNS-01 (`manifests/gateway/certificate-public.yaml`).
  - `*.prod.evelab.space`, `*.stg...`: future clusters, each with its own tunnel CNAME and Authentik
    (`authentik.prod` becomes the IdP of record once prod exists; `authentik.local` stays the dev IdP).
  - Bare `<app>.evelab.space` = the front door, whichever cluster is current (today: the laptop through the
    Cloudflare Tunnel, `manifests/cloudflared`; later: prod). An app is public only if its HTTPRoute lists the name.
    Never for video (Jellyfin) or anything without an Authentik/JWT gate.
  - `local.<app>.internal`: legacy private CA names, being retired. Do not add new ones.
- **Host port `:30443` is temporary.** Cloudflare proxies standard ports only; the next kind rebuild maps host 443 to
  the gateway and every URL drops the port. Do not bake `:30443` into new config that could wait for that.
- **Tunnel origin trick.** The dashboard has ONE rule `*.evelab.space -> https://<gateway svc>:443` with
  Origin Server Name `tunnel.local.evelab.space`: cloudflared validates the gateway's existing wildcard cert by that SNI,
  Envoy routes by the Host header. No `*.evelab.space` certificate exists or is needed in the cluster; browsers get
  Cloudflare's Universal SSL. Change the trick only by adding the SAN and dropping the server-name override, never by
  switching on "No TLS Verify".
- **Pods reach the host over IPv4 only.** AAAA lookups return an empty NOERROR.
- **No inbound ports, no public IP, Cloudflare proxy off for `*.local`.** Exposure is opt-in per route, never per DNS.
- **The cloudflared pods are the only tunnel connectors.** Never `cloudflared service install` on a laptop with the
  tunnel token: every connector gets a share of all public requests, and one off-cluster returns edge 502s.
- **L7 visibility never covers the IdP.** Cilium's proxy rewrites `X-Forwarded-Proto`; Authentik would advertise http:// OIDC
  endpoints and issuer-validating clients break. Opt namespaces into `network-policies/platform-l7-visibility.yaml` one by one.
