{{- define "tenant.name" -}}{{ required "name is required" .Values.name }}{{- end -}}
{{- define "tenant.ns" -}}tenant-{{ include "tenant.name" .root }}-{{ .workload }}{{- end -}}
{{- define "tenant.tier" -}}
{{- $t := index .Values.tiers .Values.tier -}}
{{- if not $t }}{{ fail (printf "unknown tier %q" .Values.tier) }}{{ end -}}
{{- toYaml $t -}}
{{- end -}}
{{- define "tenant.apiClientId" -}}{{ .Values.authentik.api.clientId | default (printf "eve-%s-api" .Values.name) }}{{- end -}}
{{- define "tenant.apiDisplayName" -}}{{ .Values.authentik.api.displayName | default (printf "Eve %s API" .Values.name) }}{{- end -}}
