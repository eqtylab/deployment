{{/*
Expand the name of the chart.
*/}}
{{- define "llm-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "llm-gateway.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "llm-gateway.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "llm-gateway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "llm-gateway.labels" -}}
helm.sh/chart: {{ include "llm-gateway.chart" . }}
{{ include "llm-gateway.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "llm-gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "llm-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Resolve the image repository, honoring customer registry mirror overrides.
*/}}
{{- define "llm-gateway.imageRepository" -}}
{{- $repository := .Values.image.repository -}}
{{- $registryOverride := default "" ((.Values.global).imageRegistryOverride) -}}
{{- $prefixOverride := default "" ((.Values.global).imageRepositoryPrefixOverride) -}}
{{- if $prefixOverride -}}
{{- printf "%s/%s" (trimSuffix "/" $prefixOverride) (base $repository) -}}
{{- else if $registryOverride -}}
{{- $parts := splitList "/" $repository -}}
{{- printf "%s/%s" (trimSuffix "/" $registryOverride) (join "/" (slice $parts 1)) -}}
{{- else -}}
{{- $repository -}}
{{- end -}}
{{- end -}}

{{/*
Resolve the full image reference.
*/}}
{{- define "llm-gateway.image" -}}
{{- if .Values.image.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" .Values.image.digest) -}}
{{- fail "image.digest must be a sha256 digest" -}}
{{- end -}}
{{- printf "%s@%s" (include "llm-gateway.imageRepository" .) .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" (include "llm-gateway.imageRepository" .) (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}
{{- end -}}
