# Platform / Infra Repository (Repo 3)

This repository constitutes the primary GitOps state engine for the OpenShift cluster.

## Architecture

We use the "App of Apps" pattern combined with ArgoCD Multi-Source ApplicationSets to achieve 12-factor configuration separation cleanly.
- `repo-helm-chart` contains our logical Kubernetes templates.
- `repo-platform` contains the environment-specific values. 

The `ApplicationSet` seamlessly merges these two sources together.

## Directory Structure

- `bootstrap/root-app.yaml`: This is the sole manual object you must `kubectl apply -f` to a cluster that has ArgoCD installed. It automatically syncs everything in `argocd-apps/`.
- `argocd-apps/`: Defines the community Helm charts for our infrastructure (Argo CD itself, Prometheus Stack, Metrics Server). Additionally configures our `ApplicationSet` for onboarding apps.
- `apps/`: Directory dictating all deployed applications. Simply by adding a folder (e.g. `apps/new-app/dev/values.yaml`), the Git Generator dynamically provisions a new application into the cluster.

## App Configuration Details

Inside `apps/devops-test-webserver/`:
- `dev/`, `stg/`, `prod/`: Values files defining environment specifics. Observe how `prod/` turns on canary features and sets explicit resource limits, whereas `dev/` remains lightweight!
