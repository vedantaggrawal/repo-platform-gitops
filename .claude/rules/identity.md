---
paths:
  - "platform-apps/authentik/**"
  - "manifests/authentik/**"
  - "platform-apps/keycloak*/**"
  - "manifests/keycloak*/**"
  - "platform-apps/{grafana,kargo,harbor,minio,headlamp,openbao}/**"
---
# Identity and SSO

- **Every UI goes behind Authentik (OIDC).** Apps get OIDC clients, not local users.
- **Clients are declared in Authentik blueprints** (`manifests/authentik/local/blueprints/`), mounted from a ConfigMap. Public clients use PKCE. Confidential client secrets are delivered by ESO.
- **Blueprints apply only when a file changes.** Render credentials into the blueprint with an ESO template, so a credential change re-applies it.
- **Keycloak is legacy** and being migrated off. Add no new Keycloak clients.
