{{/*
Expand the name of the chart.
*/}}
{{- define "keycloak-bootstrap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "keycloak-bootstrap.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "keycloak-bootstrap.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "keycloak-bootstrap.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "keycloak-bootstrap.labels" -}}
helm.sh/chart: {{ include "keycloak-bootstrap.chart" . }}
{{ include "keycloak-bootstrap.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "keycloak-bootstrap.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keycloak-bootstrap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Comma-separated default client scopes for a client: its defaultScopes (openid,
profile, email, and roles when unset) followed by its customScopes names
*/}}
{{- define "keycloak-bootstrap.defaultScopes" -}}
{{- $scopes := list "openid" "profile" "email" "roles" }}
{{- if hasKey . "defaultScopes" }}
{{- $scopes = .defaultScopes | default list }}
{{- end }}
{{- range .customScopes }}
{{- $scopes = append $scopes .name }}
{{- end }}
{{- $scopes | uniq | join "," }}
{{- end -}}

{{/*
Comma-separated optional client scopes for a client (offline_access when unset)
*/}}
{{- define "keycloak-bootstrap.optionalScopes" -}}
{{- if hasKey . "optionalScopes" }}
{{- .optionalScopes | default list | join "," }}
{{- else }}offline_access
{{- end }}
{{- end -}}
