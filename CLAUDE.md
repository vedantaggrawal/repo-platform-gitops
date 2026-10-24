# repo-platform-gitops

Argo CD GitOps state for the platform. The cluster itself (kind, Argo CD bootstrap) lives in `repo-platform`. Design history: `DECISIONS.md`. Read the relevant decision before proposing a design change. `README.md` is partly outdated.

## Layout (put config only where it belongs)
- `bootstrap/<env>.yaml`: root app per env; it renders `argocd-apps/`.
- `argocd-apps/`: Helm chart for the app-of-apps.
  - `appset-platform.yaml` turns every `platform-apps/<app>/<env>/` into an app.
  - `app-*.yaml` are the raw-manifest apps, rendered only for `rawManifestEnvs`.
  - `appset-apps.yaml` deploys app workloads from the separate app-gitops repo.
- `platform-apps/<app>/<env>/`: one upstream Helm chart per app.
  - `config.yaml`: chart, repoURL, targetRevision, namespace, syncWave, enabled.
  - `values.yaml`: chart values.
  - No raw manifests here.
- `manifests/<name>/<env>/`: raw manifests (CRs, ESO, CNPG, glue), each dir deployed by one `argocd-apps/templates/app-*.yaml` (check its `path:`).
- `network-policies/<env>/`: CiliumNetworkPolicies.

## Rules
- **Small PRs.** One concern per PR, about 200 changed lines or fewer. Each PR must deploy and revert on its own. Split into steps (secrets, then app, then cutover, then cleanup) rather than bundling.
- **Declarative over one-time Jobs.** Prefer an operator CR, the software's own declarative config, or a reconciling controller. A Job or Argo/Helm hook needs a stated reason in the PR, plus the follow-up that would replace it.
- **Do not repeat yourself.** Reuse existing patterns and templates. Don't add new directories or copy-paste near-identical manifests.
- **Secrets go through ESO, from OpenBao.**
  - Generate with an ESO `Password` generator, seed once (`CreatedOnce`), then `PushSecret` to OpenBao (`IfNotExists`, `deletionPolicy: None`). Apps read an `ExternalSecret` from the `openbao` ClusterSecretStore.
  - Never commit secret values.
- **SSO:** every UI goes behind Authentik (OIDC). Keycloak is legacy and being migrated off; don't add new Keycloak clients. Clients are declared in Authentik blueprints. Confidential client secrets are delivered by ESO.
- No internal tracker or task IDs in files, commits or PR text. This repo is public.

## Known traps
- Argo CD 2.10: the platform ApplicationSet forces ServerSideApply. ESO, ESO-generator and CNPG CRs in an SSA app make the diff panic. Put them in a `manifests/` app *without* `ServerSideApply=true` (e.g. `app-authentik-config`, `app-minio-init`, `app-secret-stores`); some `app-*.yaml` do use SSA.
- Observed: the root app's sync waves did not hold ApplicationSet children back. Make dependents tolerate a missing dependency (e.g. `SkipDryRunOnMissingResource`, optional mounts) instead of relying on cross-app waves.
- Authentik blueprints apply only when a file changes. Render credentials into the blueprint (ESO template) so a credential change re-applies it.
- Local DNS: CoreDNS answers `local.<name>.internal` with the host IP (ingress on `:30443`). Pods reach the host over IPv4 only.

