{{/* Use the actual subchart context so names, truncation and overrides match upstream. */}}
{{- define "openbao-custody.fullname" -}}
{{- include "openbao.fullname" .Subcharts.openbao -}}
{{- end -}}

{{- define "openbao-custody.namespace" -}}
{{- include "openbao.namespace" .Subcharts.openbao -}}
{{- end -}}

{{- define "openbao-custody.endpoint" -}}
{{- printf "%s://%s-active.%s.svc.cluster.local:8200" (include "openbao.scheme" .Subcharts.openbao) (include "openbao-custody.fullname" .) (include "openbao-custody.namespace" .) -}}
{{- end -}}
