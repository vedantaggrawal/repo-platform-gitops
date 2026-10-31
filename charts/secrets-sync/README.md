# secrets-sync

External Secrets Operator resources from values. Four independent lists, combine as needed; nothing secret is ever in values or Git.

| List | Renders | Use it for |
|---|---|---|
| `externalSecrets` | `ExternalSecret` (v1) | store → Secret: single properties (`data`), whole keys / regexp finds / generators (`dataFrom`), typed or templated Secrets |
| `clusterExternalSecrets` | `ClusterExternalSecret` (v1) | the same Secret in many namespaces (list or label selector) |
| `pushSecrets` | `PushSecret` (v1alpha1) | Secret or generator → store: whole Secret under one remote key, or key → property; `Replace` or `IfNotExists` |
| `seeds` | generator + seed `ExternalSecret` + `PushSecret` + consumer `ExternalSecret`s | generate once, keep in the store, never overwrite, consume anywhere (DB roles, admin passwords, tokens) |
| `generators` | `Password`, `UUID`, … | standalone generators referenced by `generatorRef` |

## Combination matrix

| Need | Keys |
|---|---|
| Different store for one item | `store: {kind, name}` (ExternalSecret, seed) / `stores: [...]` (PushSecret) |
| Generator-only ExternalSecret (no store) | `store: false` |
| Generate once, never rotate | `refreshPolicy: CreatedOnce` (seeds set it) |
| Re-pull on store change only | `refreshPolicy: OnChange` |
| Typed Secret (basic-auth, dockerconfigjson, tls) | `target.template.type` + `template.data` with `{{ .key }}` |
| Rename / filter keys | `dataFrom[].rewrite` (`regexp`, `transform`) |
| Merge into an existing Secret | `target.creationPolicy: Merge` |
| Keep the Secret after deletion | `target.deletionPolicy: Retain` (ESO default) |
| Push whole Secret as properties | `data: [{remoteKey}]` |
| Push one key to one property | `data: [{secretKey, remoteKey, property}]` |
| Push without a Secret in between | `generatorRef` + `template` |
| Push to several stores | `stores: [..., ...]` |
| Never overwrite a stored value | `updatePolicy: IfNotExists` (seeds default) |
| Remove from the store when the Secret goes | `deletionPolicy: Delete` |
| Provider-specific push options | `data[].metadata` |
| Anything not modelled | `extraSpec` (deep-merged last) on ExternalSecret and PushSecret items |
| Argo CD ordering | per-class `global.argocd.syncWaves`, per-item `syncWave` |

## Seeds

```yaml
seeds:
  - name: demo-db-roles
    remoteKey: platform/demo-db/roles
    keys: [owner_password, app_password]        # one generator call per key
    consumers:
      - name: demo-db-owner
        keys: [owner_password]
        type: kubernetes.io/basic-auth
        labels: { cnpg.io/reload: "true" }
        data: { username: demo_owner, password: "{{ .owner_password }}" }
```

Produces `demo-db-roles-generator` (Password), `demo-db-roles-seed` (ExternalSecret, CreatedOnce), `demo-db-roles` (PushSecret, IfNotExists/None) and `demo-db-owner` (ExternalSecret from the store). Waves: −2, −2, −1, 0. Use `generatorRef` to share a generator, `generator.outputKey` for generators that do not emit `password` (UUID → `uuid`), `seedTemplate` to add fixed fields (a username) next to the generated ones, `push` to change the push policy.

## Examples and checks

`examples/*.yaml` is one file per pattern; all render and validate against the ESO v2.13 CRD schemas:

```sh
for f in examples/*.yaml; do helm template t . -f "$f" | kubeconform -strict -schema-location '<crd-schemas>/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json'; done
```

`values.schema.json` rejects contradictory combinations (`secret` with `generatorRef`, ExternalSecret without `data`/`dataFrom`, unknown keys).
