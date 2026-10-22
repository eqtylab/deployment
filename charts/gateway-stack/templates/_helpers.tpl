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
The EQTY Lab prefix override must not redirect upstream database helper images.
*/}}
{{- define "gateway-stack.imageRepository" -}}
{{- $root := .root -}}
{{- $repository := .image.repository -}}
{{- $registryOverride := default "" (($root.Values.global).imageRegistryOverride) -}}
{{- $prefixOverride := default "" (($root.Values.global).imageRepositoryPrefixOverride) -}}
{{- if and $prefixOverride (hasPrefix "ghcr.io/eqtylab/" $repository) -}}
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
{{- if .image.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" .image.digest) -}}
{{- fail "image.digest must be a sha256 digest" -}}
{{- end -}}
{{- printf "%s@%s" (include "gateway-stack.imageRepository" .) .image.digest -}}
{{- else -}}
{{- printf "%s:%s" (include "gateway-stack.imageRepository" .) $tag -}}
{{- end -}}
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

{{/*
Plugin artifact storage beyond the inline gcs and s3 settings: GCS credentials, Azure, and file
Context: (dict "storage" <artifactStorage> "path" <values path> "envPrefix" <env prefix> "readOnly" <bool>)
*/}}
{{- define "gateway-stack.artifactStorage.validate" -}}
{{- $s := .storage -}}
{{- if and $s.provider (not (has $s.provider (list "gcs" "s3" "azure" "file"))) -}}
{{- fail (printf "%s.provider must be one of gcs, s3, azure, file" .path) -}}
{{- end -}}
{{- if eq $s.provider "azure" -}}
{{- $az := $s.azure -}}
{{- $modes := 0 -}}
{{- range (list $az.connectionString $az.accountKey $az.existingSecret $az.useManagedIdentity) -}}
{{- if . }}{{ $modes = add1 $modes }}{{ end -}}
{{- end -}}
{{- if ne (int $modes) 1 -}}
{{- fail (printf "%s.azure requires exactly one of connectionString, accountKey, existingSecret, or useManagedIdentity" .path) -}}
{{- end -}}
{{- if and (or $az.accountKey $az.useManagedIdentity) (not $az.accountName) -}}
{{- fail (printf "%s.azure.accountName is required with accountKey or useManagedIdentity" .path) -}}
{{- end -}}
{{- if and $az.connectionString $az.endpoint -}}
{{- fail (printf "%s.azure.endpoint cannot be combined with connectionString" .path) -}}
{{- end -}}
{{- end -}}
{{- if eq $s.provider "file" -}}
{{- if not $s.file.existingClaim -}}
{{- fail (printf "%s.file.existingClaim is required when provider=file" .path) -}}
{{- end -}}
{{- if not (hasPrefix "/" (default "" $s.bucket)) -}}
{{- fail (printf "%s.bucket must be an absolute path when provider=file" .path) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "gateway-stack.artifactStorage.args" -}}
{{- $s := .storage -}}
{{- if and (eq $s.provider "gcs") $s.gcs.existingSecret }}
- {{ printf "-plugin-artifact-storage-gcs-credentials-file=%s/%s" (trimSuffix "/" ($s.gcs.mountPath | default "/run/secrets/guardian-plugin-artifact-gcs")) ($s.gcs.secretKey | default "serviceAccountJson") | quote }}
{{- end }}
{{- if eq $s.provider "azure" }}
{{- if $s.azure.accountName }}
- {{ printf "-plugin-artifact-storage-azure-account-name=%s" $s.azure.accountName | quote }}
{{- end }}
{{- if $s.azure.endpoint }}
- {{ printf "-plugin-artifact-storage-azure-endpoint=%s" $s.azure.endpoint | quote }}
{{- end }}
{{- if $s.azure.useManagedIdentity }}
- -plugin-artifact-storage-azure-use-managed-identity=true
{{- end }}
{{- end }}
{{- end -}}

{{- define "gateway-stack.artifactStorage.env" -}}
{{- $s := .storage -}}
{{- if eq $s.provider "azure" }}
{{- $az := $s.azure }}
{{- if $az.existingSecret }}
- name: {{ .envPrefix }}_PLUGIN_ARTIFACT_STORAGE_AZURE_ACCOUNT_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $az.existingSecret }}
      key: {{ $az.secretKeys.accountKey | default "accountKey" }}
      optional: true
- name: {{ .envPrefix }}_PLUGIN_ARTIFACT_STORAGE_AZURE_CONNECTION_STRING
  valueFrom:
    secretKeyRef:
      name: {{ $az.existingSecret }}
      key: {{ $az.secretKeys.connectionString | default "connectionString" }}
      optional: true
{{- else if $az.accountKey }}
- name: {{ .envPrefix }}_PLUGIN_ARTIFACT_STORAGE_AZURE_ACCOUNT_KEY
  value: {{ $az.accountKey | quote }}
{{- else if $az.connectionString }}
- name: {{ .envPrefix }}_PLUGIN_ARTIFACT_STORAGE_AZURE_CONNECTION_STRING
  value: {{ $az.connectionString | quote }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "gateway-stack.artifactStorage.volumeMounts" -}}
{{- $s := .storage -}}
{{- if and (eq $s.provider "gcs") $s.gcs.existingSecret }}
- name: plugin-artifact-gcs-credentials
  mountPath: {{ $s.gcs.mountPath | default "/run/secrets/guardian-plugin-artifact-gcs" | quote }}
  readOnly: true
{{- end }}
{{- if eq $s.provider "file" }}
- name: plugin-artifact-storage
  mountPath: {{ $s.bucket | quote }}
  {{- if .readOnly }}
  readOnly: true
  {{- end }}
{{- end }}
{{- end -}}

{{- define "gateway-stack.artifactStorage.volumes" -}}
{{- $s := .storage -}}
{{- if and (eq $s.provider "gcs") $s.gcs.existingSecret }}
- name: plugin-artifact-gcs-credentials
  secret:
    secretName: {{ $s.gcs.existingSecret | quote }}
    items:
      - key: {{ $s.gcs.secretKey | default "serviceAccountJson" | quote }}
        path: {{ $s.gcs.secretKey | default "serviceAccountJson" | quote }}
{{- end }}
{{- if eq $s.provider "file" }}
- name: plugin-artifact-storage
  persistentVolumeClaim:
    claimName: {{ $s.file.existingClaim | quote }}
{{- end }}
{{- end -}}
