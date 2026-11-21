# OpenBao content (vault-config-operator)

Policies, auth roles, mounts, PKI and quotas inside OpenBao, reconciled by vault-config-operator
(`platform-apps/vault-config-operator`). OpenBao's own `initialize` stanza keeps only the bootstrap:
the Kubernetes auth mount and the `bao-config` policy/role these resources authenticate with.

Conventions
- One file per consumer or tenant (`eso.yaml`, later `tenant-<name>.yaml` rendered by the tenant chart).
- Every resource carries `authentication: {path: kubernetes, role: bao-config, serviceAccount: {name: bao-config}}`
  and lives in the `openbao` namespace (the ServiceAccount's namespace).
- Resource name = object name in OpenBao (`Policy/eso` → `sys/policy/eso`).
- Never declare a mount that already exists (`secret`): the operator would try to create it.
- No secret values here; generated values use ESO generators or `RandomSecret`.
