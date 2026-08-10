{{/*
Expand the name of the chart.
*/}}
{{- define "gateway-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "gateway-stack.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "gateway-stack.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "gateway-stack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "gateway-stack.labels" -}}
helm.sh/chart: {{ include "gateway-stack.chart" . }}
{{ include "gateway-stack.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "gateway-stack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gateway-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Resolve the image repository, honoring customer registry mirror overrides.
This chart deploys several images, so callers pass a dict of the root context
and the image block to resolve: (dict "root" . "image" .Values.<workload>.image)
*/}}
{{- define "gateway-stack.imageRepository" -}}
{{- $root := .root -}}
{{- $repository := .image.repository -}}
{{- $registryOverride := default "" (($root.Values.global).imageRegistryOverride) -}}
{{- $prefixOverride := default "" (($root.Values.global).imageRepositoryPrefixOverride) -}}
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
{{- define "gateway-stack.image" -}}
{{- $tag := .image.tag | default .root.Chart.AppVersion | toString -}}
{{- printf "%s:%s" (include "gateway-stack.imageRepository" .) $tag -}}
{{- end -}}

{{/*
Resolve the image pull policy, honoring the umbrella chart default.
*/}}
{{- define "gateway-stack.imagePullPolicy" -}}
{{- .image.pullPolicy | default ((.root.Values.global).imagePullPolicy) | default "IfNotPresent" -}}
{{- end -}}

{{/*
PostgreSQL host used by app deployments
*/}}
{{- define "gateway-stack.dbHost" -}}
{{- if .Values.database.host -}}
{{- .Values.database.host -}}
{{- else -}}
{{- printf "%s-postgresql" .Release.Name -}}
{{- end -}}
{{- end -}}

{{/*
Secret name for app DB connection
*/}}
{{- define "gateway-stack.dbSecretName" -}}
{{- if .Values.database.existingSecret -}}
{{- .Values.database.existingSecret -}}
{{- else -}}
{{- printf "%s-db" (include "gateway-stack.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Secret name for control-plane auth
*/}}
{{- define "gateway-stack.controlPlaneAuthSecretName" -}}
{{- if .Values.controlPlane.auth.existingSecret -}}
{{- .Values.controlPlane.auth.existingSecret -}}
{{- else -}}
{{- printf "%s-control-plane-auth" (include "gateway-stack.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Secret name for llm-gateway registration credential signer
*/}}
{{- define "gateway-stack.llmGatewayCredentialSignerSecretName" -}}
{{- if .Values.llmGateway.registration.credentialSigner.existingSecret -}}
{{- .Values.llmGateway.registration.credentialSigner.existingSecret -}}
{{- else -}}
{{- printf "%s-llm-gateway-credential-signer" (include "gateway-stack.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
TLS secret names
*/}}
{{- define "gateway-stack.llmGatewayTLSSecretName" -}}
{{- if .Values.ingress.tls.llmGatewaySecretName -}}
{{- .Values.ingress.tls.llmGatewaySecretName -}}
{{- else -}}
{{- printf "%s-llm-gateway-tls" (include "gateway-stack.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "gateway-stack.controlPlaneTLSSecretName" -}}
{{- if .Values.ingress.tls.controlPlaneSecretName -}}
{{- .Values.ingress.tls.controlPlaneSecretName -}}
{{- else -}}
{{- printf "%s-control-plane-tls" (include "gateway-stack.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Guardian console resource name
*/}}
{{- define "gateway-stack.uiServiceName" -}}
{{- printf "%s-ui" (include "gateway-stack.fullname" .) -}}
{{- end -}}

{{/*
Checksums of the chart-managed Secrets each workload consumes, so a credential
change rolls the pods that read it. Secrets supplied through existingSecret are
rendered empty here and are not tracked; rotate those with your own rollout.
*/}}
{{- define "gateway-stack.llmGatewaySecretsChecksum" -}}
{{- $db := include (print $.Template.BasePath "/database-secret.yaml") . -}}
{{- $auth := include (print $.Template.BasePath "/control-plane-auth-secret.yaml") . -}}
{{- $signer := include (print $.Template.BasePath "/llm-gateway-credential-signer-secret.yaml") . -}}
{{- printf "%s%s%s" $db $auth $signer | sha256sum -}}
{{- end -}}

{{- define "gateway-stack.controlPlaneSecretsChecksum" -}}
{{- $db := include (print $.Template.BasePath "/database-secret.yaml") . -}}
{{- $auth := include (print $.Template.BasePath "/control-plane-auth-secret.yaml") . -}}
{{- printf "%s%s" $db $auth | sha256sum -}}
{{- end -}}

{{/*
Service account names
*/}}
{{- define "gateway-stack.llmGatewayServiceAccountName" -}}
{{- if .Values.llmGateway.serviceAccount.name -}}
{{- .Values.llmGateway.serviceAccount.name -}}
{{- else if .Values.llmGateway.serviceAccount.create -}}
{{- printf "%s-llm-gateway" (include "gateway-stack.fullname" .) -}}
{{- else -}}
default
{{- end -}}
{{- end -}}

{{- define "gateway-stack.controlPlaneServiceAccountName" -}}
{{- if .Values.controlPlane.serviceAccount.name -}}
{{- .Values.controlPlane.serviceAccount.name -}}
{{- else if .Values.controlPlane.serviceAccount.create -}}
{{- printf "%s-control-plane" (include "gateway-stack.fullname" .) -}}
{{- else -}}
default
{{- end -}}
{{- end -}}

{{- define "gateway-stack.guardianUIServiceAccountName" -}}
{{- if .Values.guardianUI.serviceAccount.name -}}
{{- .Values.guardianUI.serviceAccount.name -}}
{{- else if .Values.guardianUI.serviceAccount.create -}}
{{- include "gateway-stack.uiServiceName" . -}}
{{- else -}}
default
{{- end -}}
{{- end -}}
