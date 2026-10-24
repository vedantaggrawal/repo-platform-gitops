---
paths:
  - "platform-apps/authentik/**"
  - "manifests/authentik/**"
  - "platform-apps/keycloak*/**"
  - "manifests/keycloak*/**"
  - "platform-apps/{grafana,kargo,harbor,minio,headlamp,openbao}/**"
---
# Identity and SSO

- **Every UI goes behind Authentik (OIDC), and Authentik federates GitHub.** Sign-in redirects straight to GitHub. Apps auto-redirect to Authentik where they can (e.g. Grafana `oauth_auto_login`).
  - Break-glass password login: `/if/flow/break-glass/` (Authentik) plus each app's local admin.
  - **Identity is federated from GitHub.** The first login of an allowlisted GitHub account creates the user (no hand-made users). Access (`ALLOWED`) and admins (`ADMINS`, giving `platform-admins`) are lists of GitHub numeric user ids (immutable; never logins) in `blueprints/federation.yaml`. Both GitHub flows require the allowlist (`policy_engine_mode: all`), and groups re-sync on every login.
- **Apps get OIDC clients, not local users.**
- **Clients are declared in Authentik blueprints** (`manifests/authentik/local/blueprints/`), mounted from a ConfigMap. Public clients use PKCE. Confidential client secrets are delivered by ESO.
- **Blueprints apply only when a file changes.** Render credentials into the blueprint with an ESO template, so a credential change re-applies it.
- **Keycloak is legacy** and being migrated off. Add no new Keycloak clients.
