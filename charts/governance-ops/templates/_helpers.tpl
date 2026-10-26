{{/*
Expand the name of the chart.
*/}}
{{- define "governance-ops.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "governance-ops.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "governance-ops.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "governance-ops.labels" -}}
helm.sh/chart: {{ include "governance-ops.chart" . }}
{{ include "governance-ops.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "governance-ops.selectorLabels" -}}
app.kubernetes.io/name: {{ include "governance-ops.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Target release fullname - the Guardian Platform release to monitor
*/}}
{{- define "governance-ops.targetRelease" -}}
{{- .Values.targetRelease | default "guardian-platform" }}
{{- end }}

{{/*
Check if blackbox-exporter is available for probes and alerts
Returns non-empty string if the Probe CRD exists (prometheus-operator installed)
AND the Service named by probes.proberUrl (<service>.<namespace>[.svc...]:<port>) exists;
a proberUrl that is not a Service DNS name only requires the Probe CRD
Returns empty string otherwise
*/}}
{{- define "governance-ops.blackboxAvailable" -}}
{{- $probeCRD := (lookup "apiextensions.k8s.io/v1" "CustomResourceDefinition" "" "probes.monitoring.coreos.com") }}
{{- $host := first (splitList ":" (.Values.probes.proberUrl | default "")) }}
{{- $parts := splitList "." $host }}
{{- $blackboxExists := true }}
{{- if or (eq (len $parts) 2) (and (gt (len $parts) 2) (eq (index $parts 2) "svc")) }}
  {{- $blackboxExists = not (empty (lookup "v1" "Service" (index $parts 1) (index $parts 0))) }}
{{- end }}
{{- if and $probeCRD $blackboxExists }}true{{ end }}
{{- end }}
