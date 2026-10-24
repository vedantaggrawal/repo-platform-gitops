---
paths:
  - "platform-apps/*/*/config.yaml"
  - "platform-apps/{kargo,argocd-image-updater}/**"
---
# Delivery and versions

- **Kargo promotes images and charts between stages.**
  - argocd-image-updater is not used. It's disabled, to be removed, so don't add image-updater annotations.
  - *Why:* one promotion path, with explicit and auditable stage gates.
- **Pin exact chart versions in every env** (`targetRevision: "1.11.2"`, never `1.11.*`). A bump is its own PR.
  - *Why:* a render must be reproducible, and an upgrade must be a reviewed change, not a surprise on resync.
  - Every existing `*` in a `targetRevision` is to be pinned.
