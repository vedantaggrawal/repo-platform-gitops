---
paths:
  - "platform-apps/authentik/**"
  - "manifests/authentik/**"
  - "platform-apps/keycloak*/**"
  - "manifests/keycloak*/**"
  - "platform-apps/{grafana,kargo,harbor,minio,headlamp,openbao}/**"
---
# Identity and SSO

- **Every UI goes behind Authentik (OIDC), and Authentik federates GitHub.** Authentik has one standard sign-in page: a username field (password login, e.g. `akadmin`) and a **GitHub** button. Nothing auto-redirects to GitHub, so sign-out really signs you out. Grafana auto-redirects to Authentik.
  - App sign-out is local: each app (Grafana, Argo CD, Kargo) returns to its own login page, because Kargo can't redirect to the IdP on logout, so this is the only consistent behaviour. Signing out of everything is done in Authentik and lands on that same sign-in page.
  - Break-glass: password login on that page (`akadmin`), plus each app's local admin.
  - **Identity is federated from GitHub.** The first login of an allowlisted GitHub account creates the user (no hand-made users). Access (`ALLOWED`) and admins (`ADMINS`, giving `platform-admins`) are lists of GitHub numeric user ids (immutable; never logins) in `blueprints/federation.yaml`. Both GitHub flows require the allowlist (`policy_engine_mode: all`), and groups re-sync on every login.
- **Apps get OIDC clients, not local users.**
- **Clients are declared in Authentik blueprints** (`manifests/authentik/local/blueprints/`), mounted from a ConfigMap. Public clients use PKCE. Confidential client secrets are delivered by ESO.
- **Blueprints apply only when a file changes.** Render credentials into the blueprint with an ESO template, so a credential change re-applies it.
- **Keycloak is legacy** and being migrated off. Add no new Keycloak clients.
