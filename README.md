# repo-platform-gitops

Argo CD GitOps state for the platform: one root app per env (`bootstrap/<env>.yaml`) renders `argocd-apps/`. That chart turns `platform-apps/<app>/<env>/` (upstream Helm charts) and `manifests/<name>/<env>/` (raw manifests) into Argo CD Applications.

- **Layout:** [`CLAUDE.md`](CLAUDE.md).
- **How we do things and why:** [`.claude/rules/`](.claude/rules/), the current opinions by topic. They are edited in place when a decision changes, and git history is the record.
- **Cluster provisioning** (kind, Argo CD bootstrap): `repo-platform`.
