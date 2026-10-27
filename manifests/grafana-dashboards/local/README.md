# Platform dashboards

Dashboards now live in `platform-apps/grafana/local/dashboards/` (Grafana Git Sync).
This directory stays so the `grafana-dashboards` Application keeps ownership of any
ConfigMap dashboards and prunes the ones no longer in git.
