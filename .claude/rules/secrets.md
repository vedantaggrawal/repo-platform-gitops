---
paths:
  - "manifests/**"
  - "platform-apps/**"
---
# Secrets

- **Every credential comes from OpenBao via ESO** (credential-free config Secrets, e.g. a public repo entry, may be committed). Apps read an `ExternalSecret` from the `openbao` ClusterSecretStore.
  - *Why:* one audited source of truth that survives cluster rebuilds.
- **Generated secrets:**
  1. ESO `Password` generator;
  2. seed `ExternalSecret` (`CreatedOnce`);
  3. `PushSecret` to OpenBao (`updatePolicy: IfNotExists`, `deletionPolicy: None`);
  4. a delivering `ExternalSecret`.
  - Example: `manifests/authentik/local/secrets.yaml`.
  - *Not* a seeding Job.
- **Externally issued secrets** (e.g. OAuth app credentials) come from the human's tfvars:
  - Terraform in `repo-platform` writes them as Secrets in `platform-seed`.
  - A PushSecret in `manifests/secret-stores/` copies them into OpenBao (`updatePolicy: Replace`).
  - Apps read only from OpenBao. Rotation = change the tfvars, then apply Terraform.
- Never commit secret values, even base64-encoded.
