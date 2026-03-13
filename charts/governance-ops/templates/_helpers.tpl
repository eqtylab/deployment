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
Target release fullname - the governance-platform release to monitor
*/}}
{{- define "governance-ops.targetRelease" -}}
{{- .Values.targetRelease | default "governance-platform" }}
{{- end }}

{{/*
Check if blackbox-exporter is available for probes and alerts
Returns non-empty string if both Probe CRD exists (prometheus-operator installed)
AND blackbox-exporter Service exists in any namespace
Returns empty string otherwise
*/}}
{{- define "governance-ops.blackboxAvailable" -}}
{{- $probeCRD := (lookup "apiextensions.k8s.io/v1" "CustomResourceDefinition" "" "probes.monitoring.coreos.com") }}
{{- $blackboxServices := (lookup "v1" "Service" "" "").items }}
{{- $blackboxExists := false }}
{{- range $blackboxServices }}
  {{- if hasPrefix "prometheus-blackbox-exporter" .metadata.name }}
    {{- $blackboxExists = true }}
  {{- end }}
{{- end }}
{{- if and $probeCRD $blackboxExists }}true{{ end }}
{{- end }}

{{/*
Get Grafana host URL for dashboard links
Automatically discovers the Grafana ingress host from kube-prometheus-stack
Falls back to .Values.alerts.grafanaHost if explicitly provided
Returns empty string if no Grafana host can be found
*/}}
{{- define "governance-ops.grafanaHost" -}}
{{- if .Values.alerts.grafanaHost }}
  {{- .Values.alerts.grafanaHost }}
{{- else }}
  {{- $grafanaHost := "" }}
  {{- $ingresses := (lookup "networking.k8s.io/v1" "Ingress" "" "").items }}
  {{- range $ingresses }}
    {{- if and (hasPrefix "kube-prometheus-stack-grafana" .metadata.name) (gt (len .spec.rules) 0) }}
      {{- $grafanaHost = (index .spec.rules 0).host }}
    {{- end }}
  {{- end }}
  {{- $grafanaHost }}
{{- end }}
{{- end }}
