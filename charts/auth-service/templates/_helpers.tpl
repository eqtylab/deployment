{{/*
Expand the name of the chart.
*/}}
{{- define "auth-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "auth-service.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "auth-service.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "auth-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

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
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "auth-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "auth-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Resolve the image repository, honoring customer registry mirror overrides.
*/}}
{{- define "auth-service.imageRepository" -}}
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
{{- define "auth-service.image" -}}
{{- if .Values.image.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" .Values.image.digest) -}}
{{- fail "image.digest must be a sha256 digest" -}}
{{- end -}}
{{- printf "%s@%s" (include "auth-service.imageRepository" .) .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" (include "auth-service.imageRepository" .) (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}
{{- end -}}

{{/*
Resolve the key management provider (chart value first, then the umbrella global).
*/}}
{{- define "auth-service.keyManagementProvider" -}}
{{- .Values.config.keyManagement.provider | default (((.Values.global).secrets).keyManagement).provider | default "" -}}
{{- end -}}

{{/*
Resolve the OpenBao token Secret name (token_file auth only).
*/}}
{{- define "auth-service.openbaoTokenSecretName" -}}
{{- .Values.secrets.keyManagement.openbao.name | default ((((.Values.global).secrets).keyManagement).openbao).secretName | default "" -}}
{{- end -}}

{{/*
Validate the OpenBao profile at render time so a misconfigured release fails in
helm, not in a crash-looping pod. Mirrors the Auth image's own startup checks.
*/}}
{{- define "auth-service.openbaoValidate" -}}
{{- $bao := .Values.config.keyManagement.openbao -}}
{{- if not $bao.address -}}
{{- fail "config.keyManagement.openbao.address is required when key management provider is openbao" -}}
{{- end -}}
{{- /* Parse the origin before checking transport. urlParse alone accepts userinfo,
paths and empty hosts. A root slash is supported by the Auth runtime. */ -}}
{{- if not (regexMatch `^https?://(\[[0-9a-fA-F:.]+\]|[^/:@?#[:space:]\[\]\\%]+)(:[0-9]*)?/?$` $bao.address) -}}
{{- fail "config.keyManagement.openbao.address must be an HTTP(S) origin without credentials, path, query or fragment (an optional trailing / is allowed)" -}}
{{- end -}}
{{- $origin := urlParse $bao.address -}}
{{- $host := regexReplaceAll `:[0-9]*$` $origin.host "" -}}
{{- $octet := `(0|[1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])` -}}
{{- $ipv4 := printf `127\.%s\.%s\.%s` $octet $octet $octet -}}
{{- $loopback := regexMatch (printf `^%s$` $ipv4) $host -}}
{{- /* net.IP.IsLoopback also accepts expanded IPv6 and IPv4-mapped IPv6. */ -}}
{{- $v6 := list `(0{1,4}:){7}0{0,3}1` (printf `(0{1,4}:){5}[fF]{4}:%s` $ipv4) `(0{1,4}:){5}[fF]{4}:7[fF][0-9a-fA-F]{2}:[0-9a-fA-F]{1,4}` -}}
{{- range $i := until 7 -}}
{{- $left := trimSuffix ":" (repeat $i "0{1,4}:") -}}
{{- range $j := until (int (sub 7 $i)) -}}
{{- $v6 = append $v6 (printf `%s::%s0{0,3}1` $left (repeat $j "0{1,4}:")) -}}
{{- end -}}
{{- end -}}
{{- range $i := until 5 -}}
{{- $left := trimSuffix ":" (repeat $i "0{1,4}:") -}}
{{- range $j := until (int (sub 5 $i)) -}}
{{- $prefix := printf `%s::%s[fF]{4}:` $left (repeat $j "0{1,4}:") -}}
{{- $v6 = append $v6 (printf `%s%s` $prefix $ipv4) -}}
{{- $v6 = append $v6 (printf `%s7[fF][0-9a-fA-F]{2}:[0-9a-fA-F]{1,4}` $prefix) -}}
{{- end -}}
{{- end -}}
{{- $loopback = or $loopback (regexMatch (printf `^\[(%s)\]$` (join "|" $v6)) $host) -}}
{{- /* The Auth image accepts a loopback HTTP origin only when ENVIRONMENT is development. */ -}}
{{- $environment := .Values.config.server.environment | default ((.Values.global).environmentType) | default "production" -}}
{{- if and (ne $origin.scheme "https") (or (not $loopback) (ne $environment "development")) -}}
{{- fail (printf "config.keyManagement.openbao.address requires HTTPS except on an explicit loopback IP in a development environment (localhost is not accepted; ENVIRONMENT resolves to %q)" $environment) -}}
{{- end -}}
{{- $algorithm := .Values.config.keyManagement.algorithm | default "p256" -}}
{{- if ne $algorithm "p256" -}}
{{- fail (printf "config.keyManagement.algorithm must be p256 for the openbao provider, got %q" $algorithm) -}}
{{- end -}}
{{- if and $bao.ca.secretName $bao.ca.configMapName -}}
{{- fail "set only one of config.keyManagement.openbao.ca.secretName and config.keyManagement.openbao.ca.configMapName" -}}
{{- end -}}
{{- if eq $bao.auth.method "kubernetes" -}}
{{- if not $bao.auth.role -}}
{{- fail "config.keyManagement.openbao.auth.role is required when auth method is kubernetes" -}}
{{- end -}}
{{- if not $bao.auth.audience -}}
{{- fail "config.keyManagement.openbao.auth.audience is required when auth method is kubernetes" -}}
{{- end -}}
{{- else if eq $bao.auth.method "token_file" -}}
{{- if not (include "auth-service.openbaoTokenSecretName" .) -}}
{{- fail "secrets.keyManagement.openbao.name (or global.secrets.keyManagement.openbao.secretName) is required when auth method is token_file" -}}
{{- end -}}
{{- else -}}
{{- fail (printf "config.keyManagement.openbao.auth.method must be kubernetes or token_file, got %q" $bao.auth.method) -}}
{{- end -}}
{{- end -}}
