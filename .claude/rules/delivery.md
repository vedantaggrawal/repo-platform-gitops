---
paths:
  - "argocd-apps/envs/*/apps.yaml"
  - "platform-apps/kargo/**"
---
# Delivery and versions

- **Kargo promotes images and charts between stages.**
  - Not argocd-image-updater: it was removed, so don't add image-updater annotations.
  - *Why:* one promotion path, with explicit and auditable stage gates.
- **Pin exact chart versions in every env** (`targetRevision: "1.11.2"`, never `1.11.*`). A bump is its own PR.
  - *Why:* a render must be reproducible, and an upgrade must be a reviewed change, not a surprise on resync.
