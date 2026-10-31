{{/* Common labels: chart + global.labels + per-item labels. Args: dict "root" . "item" <item> */}}
{{- define "secrets-sync.labels" -}}
{{- $root := .root -}}
{{- $labels := merge (dict) (.item.labels | default dict) ($root.Values.global.labels | default dict) (dict
  "app.kubernetes.io/managed-by" $root.Release.Service
  "app.kubernetes.io/part-of" $root.Chart.Name
  "helm.sh/chart" (printf "%s-%s" $root.Chart.Name $root.Chart.Version)) -}}
{{- toYaml $labels -}}
{{- end -}}

{{/* Annotations: Argo sync wave/options + global + per-item. Args: dict "root" . "item" <item> "class" <syncWaves key> */}}
{{- define "secrets-sync.annotations" -}}
{{- $root := .root -}}
{{- $argo := dict -}}
{{- $wave := .item.syncWave | default (index $root.Values.global.argocd.syncWaves .class) -}}
{{- if $wave }}{{- $_ := set $argo "argocd.argoproj.io/sync-wave" (toString $wave) -}}{{- end -}}
{{- if $root.Values.global.argocd.skipDryRunOnMissingResource }}{{- $_ := set $argo "argocd.argoproj.io/sync-options" "SkipDryRunOnMissingResource=true" -}}{{- end -}}
{{- $ann := merge (dict) (.item.annotations | default dict) ($root.Values.global.annotations | default dict) $argo -}}
{{- toYaml $ann -}}
{{- end -}}

{{/* Namespace: item > global > release. Args: dict "root" . "item" <item> */}}
{{- define "secrets-sync.namespace" -}}
{{- .item.namespace | default .root.Values.global.namespace | default .root.Release.Namespace -}}
{{- end -}}

{{/* Store reference {kind,name}: item.store > global.store. Args: dict "root" . "item" <item> */}}
{{- define "secrets-sync.storeRef" -}}
{{- $s := .item.store | default .root.Values.global.store -}}
{{- dict "kind" ($s.kind | default "SecretStore") "name" $s.name | toYaml -}}
{{- end -}}

{{/* metadata block. Args: dict "root" . "item" <item> "class" <key> "name" <string> [ "cluster" true ] */}}
{{- define "secrets-sync.metadata" -}}
name: {{ .name }}
{{- if not .cluster }}
namespace: {{ include "secrets-sync.namespace" . }}
{{- end }}
labels:
  {{- include "secrets-sync.labels" . | nindent 2 }}
annotations:
  {{- include "secrets-sync.annotations" . | nindent 2 }}
{{- end -}}

{{/*
ExternalSecret spec from an externalSecrets[] item (also used by seeds and ClusterExternalSecret).
Args: dict "root" . "item" <item>. Returns YAML.
*/}}
{{- define "secrets-sync.externalSecretSpec" -}}
{{- $root := .root -}}{{- $it := .item -}}
{{- $spec := dict -}}
{{- if $it.refreshPolicy }}{{- $_ := set $spec "refreshPolicy" $it.refreshPolicy -}}{{- end -}}
{{- if ne ($it.refreshPolicy | default "Periodic") "CreatedOnce" }}{{- $_ := set $spec "refreshInterval" ($it.refreshInterval | default $root.Values.global.refreshInterval) -}}{{- end -}}
{{- if not (and (hasKey $it "store") (eq (toString $it.store) "false")) }}{{- $_ := set $spec "secretStoreRef" (include "secrets-sync.storeRef" (dict "root" $root "item" $it) | fromYaml) -}}{{- end -}}
{{- $t := $it.target | default dict -}}
{{- $target := dict "name" ($t.name | default $it.name) "creationPolicy" ($t.creationPolicy | default "Owner") -}}
{{- if $t.deletionPolicy }}{{- $_ := set $target "deletionPolicy" $t.deletionPolicy -}}{{- end -}}
{{- if $t.immutable }}{{- $_ := set $target "immutable" true -}}{{- end -}}
{{- if $t.template }}
{{- $tpl := deepCopy $t.template -}}
{{- if not (hasKey $tpl "engineVersion") }}{{- $_ := set $tpl "engineVersion" "v2" -}}{{- end -}}
{{- $_ := set $target "template" $tpl -}}
{{- end -}}
{{- $_ := set $spec "target" $target -}}
{{- if $it.data }}{{- $_ := set $spec "data" $it.data -}}{{- end -}}
{{- if $it.dataFrom }}{{- $_ := set $spec "dataFrom" $it.dataFrom -}}{{- end -}}
{{- if $it.extraSpec }}{{- $spec = mergeOverwrite $spec (deepCopy $it.extraSpec) -}}{{- end -}}
{{- toYaml $spec -}}
{{- end -}}

{{/*
PushSecret spec from a pushSecrets[] item. Args: dict "root" . "item" <item>. Returns YAML.
*/}}
{{- define "secrets-sync.pushSecretSpec" -}}
{{- $root := .root -}}{{- $it := .item -}}
{{- $spec := dict "refreshInterval" ($it.refreshInterval | default $root.Values.global.refreshInterval)
                  "updatePolicy" ($it.updatePolicy | default "Replace")
                  "deletionPolicy" ($it.deletionPolicy | default "None") -}}
{{- $stores := list -}}
{{- range ($it.stores | default (list $root.Values.global.store)) }}{{- $stores = append $stores (dict "kind" (.kind | default "SecretStore") "name" .name) -}}{{- end -}}
{{- $_ := set $spec "secretStoreRefs" $stores -}}
{{- if $it.generatorRef }}{{- $_ := set $spec "selector" (dict "generatorRef" $it.generatorRef) -}}
{{- else }}{{- $_ := set $spec "selector" (dict "secret" (dict "name" ($it.secret | default $it.name))) -}}{{- end -}}
{{- $data := list -}}
{{- range ($it.data | default list) }}
{{- if hasKey . "match" }}{{- $data = append $data . -}}
{{- else }}
{{- $ref := dict "remoteKey" .remoteKey -}}{{- if .property }}{{- $_ := set $ref "property" .property -}}{{- end -}}
{{- $match := dict "remoteRef" $ref -}}{{- if .secretKey }}{{- $_ := set $match "secretKey" .secretKey -}}{{- end -}}
{{- $d := dict "match" $match -}}
{{- if .metadata }}{{- $_ := set $d "metadata" .metadata -}}{{- end -}}
{{- if .conversionStrategy }}{{- $_ := set $d "conversionStrategy" .conversionStrategy -}}{{- end -}}
{{- $data = append $data $d -}}
{{- end -}}
{{- end -}}
{{- $_ := set $spec "data" $data -}}
{{- if $it.template }}{{- $_ := set $spec "template" $it.template -}}{{- end -}}
{{- if $it.extraSpec }}{{- $spec = mergeOverwrite $spec (deepCopy $it.extraSpec) -}}{{- end -}}
{{- toYaml $spec -}}
{{- end -}}
