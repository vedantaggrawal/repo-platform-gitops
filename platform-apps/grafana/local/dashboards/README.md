# Grafana Git Sync

Grafana syncs this folder (Administration → Provisioning → platform-dashboards).
Editing a dashboard in the Grafana UI opens a pull request that adds or changes a JSON file here.
Merge the PR and Grafana picks it up within a minute. Dashboards provisioned from ConfigMaps
(`manifests/grafana-dashboards/`) stay read-only in the UI until they are moved here.
