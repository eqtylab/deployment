{{/* vim: set filetype=mustache: */}}

{{- define "name" -}}
{{- default .Values.name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "fullname" -}}
{{- $name := default .Values.name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name  $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "labels" -}}
helm.sh/chart: {{ include "chart" . }}
{{ include "selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "selectorLabels" -}}
app.kubernetes.io/name: {{ include "name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Get compliance secret name from global or use default
*/}}
{{- define "integrity.complianceSecretName" -}}
{{- if .Values.global }}
{{- if .Values.global.secrets }}
{{- if .Values.global.secrets.complianceSecretName }}
{{- .Values.global.secrets.complianceSecretName -}}
{{- else -}}
compliance-secrets
{{- end -}}
{{- else -}}
compliance-secrets
{{- end -}}
{{- else -}}
compliance-secrets
{{- end -}}
{{- end -}}

{{/*
Get blob store secret name from global or use default
*/}}
{{- define "integrity.blobSecretName" -}}
{{- if .Values.global }}
{{- if .Values.global.secrets }}
{{- if .Values.global.secrets.blobStoreSecretName }}
{{- .Values.global.secrets.blobStoreSecretName -}}
{{- else -}}
blob-secret
{{- end -}}
{{- else -}}
blob-secret
{{- end -}}
{{- else -}}
blob-secret
{{- end -}}
{{- end -}}

{{/*
Get Azure Key Vault secret name from global or use default
*/}}
{{- define "integrity.azureKvSecretName" -}}
{{- if .Values.global }}
{{- if .Values.global.secrets }}
{{- if .Values.global.secrets.azureKVSecretName }}
{{- .Values.global.secrets.azureKVSecretName -}}
{{- else -}}
azure-kv-secret
{{- end -}}
{{- else -}}
azure-kv-secret
{{- end -}}
{{- else -}}
azure-kv-secret
{{- end -}}
{{- end -}}
