---
paths:
  - "argocd-apps/templates/appset-apps.yaml"
  - "bootstrap/**"
---
# Repos and ownership

- **Each repo has one owner:**
  - `repo-app`: source and CI.
  - `repo-helm-chart`: the generic app chart.
  - `repo-app-gitops`: per-app, per-env `values.yaml` only.
  - this repo: all Argo CD config.
  - `repo-platform`: cluster provisioning (Terraform).
  - *Why:* each repo has one owner, one rate of change and a contained blast radius. App teams never touch platform config.
- **This repo owns every Argo CD object, including the app AppSet.** `repo-app-gitops` holds no Argo YAML.
  - *Why:* a cluster rebuilds from Terraform plus one `bootstrap/<env>.yaml`.
- **Apps share the generic chart and supply only values.** Unique infra (StatefulSet, CronJob) gets its own chart, as the exception. *Not* per-app charts: they drift.
- **Terraform owns the layers below Argo CD:**
  - kind, Cilium, cert-manager, Argo CD, and the org-wide `repo-creds`.
  - The `cilium` and `cert-manager` entries in `platform-apps/` stay `enabled: "false"`. Argo CD and kind have no entry.
