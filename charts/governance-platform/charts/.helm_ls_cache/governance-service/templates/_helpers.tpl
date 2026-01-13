{{/*
Expand the name of the chart.
*/}}
{{- define "governance-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "governance-service.fullname" -}}
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
{{- define "governance-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Service common labels
*/}}
{{- define "governance-service.labels" -}}
helm.sh/chart: {{ include "governance-service.chart" . }}
{{ include "governance-service.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Service selector labels
*/}}
{{- define "governance-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "governance-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "governance-service.serviceAccountName" -}}
  {{- if .Values.serviceAccount.create }}
    {{- default (include "governance-service.fullname" .) .Values.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/*
Create the name of the worker service name.
*/}}
{{- define "governance-worker.name" -}}
{{- $baseName := default .Chart.Name .Values.nameOverride }}
{{- printf "%s-worker" $baseName | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create the name of the worker service full name.
*/}}
{{- define "governance-worker.fullname" -}}
{{- if .Values.fullnameOverride }}
    {{- $override := .Values.fullnameOverride }}
    {{- if not (hasSuffix "-worker" $override) }}
        {{- printf "%s-worker" $override | trunc 63 | trimSuffix "-" }}
    {{- else }}
        {{- $override | trunc 63 | trimSuffix "-" }}
    {{- end }}
{{- else }}
    {{- $name := default .Chart.Name .Values.nameOverride }}
    {{- if contains $name .Release.Name }}
        {{- printf "%s-worker" .Release.Name | trunc 63 | trimSuffix "-" }}
    {{- else }}
        {{- printf "%s-%s-worker" .Release.Name $name | trunc 63 | trimSuffix "-" }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
Worker selector labels
*/}}
{{- define "governance-worker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "governance-worker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Worker common labels
*/}}
{{- define "governance-worker.labels" -}}
helm.sh/chart: {{ include "governance-service.chart" . }}
{{ include "governance-worker.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
