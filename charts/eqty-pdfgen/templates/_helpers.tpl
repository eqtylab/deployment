{{/*
Expand the name of the chart.
*/}}
{{- define "eqty-pdfgen.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "eqty-pdfgen.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "eqty-pdfgen.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "eqty-pdfgen.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "eqty-pdfgen.labels" -}}
helm.sh/chart: {{ include "eqty-pdfgen.chart" . }}
{{ include "eqty-pdfgen.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels.
*/}}
{{- define "eqty-pdfgen.selectorLabels" -}}
app.kubernetes.io/name: {{ include "eqty-pdfgen.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Resolve the image repository, honoring customer registry mirror overrides.
*/}}
{{- define "eqty-pdfgen.imageRepository" -}}
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
{{- define "eqty-pdfgen.image" -}}
{{- printf "%s:%s" (include "eqty-pdfgen.imageRepository" .) (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}

{{/*
Resolve the render tmp mount path from config.tmpDir.
*/}}
{{- define "eqty-pdfgen.renderTmpPath" -}}
{{- $tmpDir := .Values.config.tmpDir | default "tmp" -}}
{{- if hasPrefix "/" $tmpDir -}}
{{- $tmpDir -}}
{{- else -}}
{{- printf "/opt/app-root/src/%s" $tmpDir -}}
{{- end -}}
{{- end -}}

{{/*
Default signing URL for platform installs.
*/}}
{{- define "eqty-pdfgen.signingUrl" -}}
{{- .Values.config.signingUrl | default (printf "http://%s-auth-service:8080/api/v1/protected/sign-pdf" .Release.Name) -}}
{{- end -}}
