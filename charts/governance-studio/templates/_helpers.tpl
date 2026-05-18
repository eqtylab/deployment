{{/*
Expand the name of the chart.
*/}}
{{- define "governance-studio.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "governance-studio.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "governance-studio.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "governance-studio.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "governance-studio.labels" -}}
helm.sh/chart: {{ include "governance-studio.chart" . }}
{{ include "governance-studio.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "governance-studio.selectorLabels" -}}
app.kubernetes.io/name: {{ include "governance-studio.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Resolve the image repository, honoring customer registry mirror overrides.
*/}}
{{- define "governance-studio.imageRepository" -}}
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
{{- define "governance-studio.image" -}}
{{- printf "%s:%s" (include "governance-studio.imageRepository" .) (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}
