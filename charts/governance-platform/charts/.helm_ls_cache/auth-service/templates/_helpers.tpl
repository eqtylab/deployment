{{/*
Expand the name of the chart.
*/}}
{{- define "auth-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "auth-service.fullname" -}}
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
{{- define "auth-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "auth-service.labels" -}}
helm.sh/chart: {{ include "auth-service.chart" . }}
{{ include "auth-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "auth-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "auth-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "auth-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "auth-service.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the database host
*/}}
{{- define "auth-service.databaseHost" -}}
{{- if .Values.postgresql.enabled }}
{{- printf "%s-postgresql" (include "auth-service.fullname" .) }}
{{- else }}
{{- .Values.config.database.host }}
{{- end }}
{{- end }}

{{/*
Create the database password secret name
*/}}
{{- define "auth-service.databaseSecretName" -}}
{{- if .Values.config.database.existingSecret }}
{{- .Values.config.database.existingSecret }}
{{- else if .Values.postgresql.enabled }}
{{- printf "%s-postgresql" (include "auth-service.fullname" .) }}
{{- else }}
{{- printf "%s-database" (include "auth-service.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Create the database password secret key
*/}}
{{- define "auth-service.databaseSecretKey" -}}
{{- if .Values.config.database.existingSecret }}
{{- .Values.config.database.existingSecretKeys.password }}
{{- else if .Values.postgresql.enabled }}
{{- "password" }}
{{- else }}
{{- "password" }}
{{- end }}
{{- end }}

{{/*
Create the IDP secret name
*/}}
{{- define "auth-service.idpSecretName" -}}
{{- if .Values.config.idp.existingSecret }}
{{- .Values.config.idp.existingSecret }}
{{- else }}
{{- printf "%s-idp" (include "auth-service.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Create the Key Vault secret name
*/}}
{{- define "auth-service.keyVaultSecretName" -}}
{{- if eq .Values.config.keyVault.provider "azure" }}
{{- if .Values.config.keyVault.azure.existingSecret }}
{{- .Values.config.keyVault.azure.existingSecret }}
{{- else }}
{{- printf "%s-keyvault" (include "auth-service.fullname" .) }}
{{- end }}
{{- else if eq .Values.config.keyVault.provider "hashicorp" }}
{{- if .Values.config.keyVault.hashicorp.existingSecret }}
{{- .Values.config.keyVault.hashicorp.existingSecret }}
{{- else }}
{{- printf "%s-keyvault" (include "auth-service.fullname" .) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create the security secret name
*/}}
{{- define "auth-service.securitySecretName" -}}
{{- if .Values.config.security.existingSecret }}
{{- .Values.config.security.existingSecret }}
{{- else }}
{{- printf "%s-security" (include "auth-service.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Create the service account secret name
*/}}
{{- define "auth-service.serviceAccountSecretName" -}}
{{- if .Values.config.serviceAccounts.existingSecret }}
{{- .Values.config.serviceAccounts.existingSecret }}
{{- else }}
{{- printf "%s-service-accounts" (include "auth-service.fullname" .) }}
{{- end }}
{{- end }}