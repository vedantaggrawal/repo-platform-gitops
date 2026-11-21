---
paths:
  - "manifests/cluster-dns/**"
  - "network-policies/**"
  - "platform-apps/{cilium,traefik}/**"
---
# Networking (local env)

- **Hostnames are `local.<name>.internal`.** The ingress is on host port `:30443`.
  - CoreDNS (`manifests/cluster-dns`) answers these names with the host IP, so pods use the same URLs as the browser.
  - No in-cluster aliases and no extra Services or Endpoints for this.
- **Pods reach the host over IPv4 only.** AAAA lookups return an empty NOERROR.
- **TLS** comes from the platform CA via cert-manager annotations on the Ingress.
