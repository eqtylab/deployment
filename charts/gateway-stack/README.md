# Gateway Stack

A Helm chart for deploying the EQTY Lab Guardian gateway stack on Kubernetes.

## Description

The Gateway Stack provides a signing proxy in front of upstream model providers, a management control plane, and an operator console for the Governance Platform.

Key capabilities:

- **LLM Gateway**: RFC 9421 signed proxy for Anthropic and OpenAI upstreams, with an append-only audit trail
- **Control Plane**: Management API for agent registration, plugin publishing, and project configuration
- **Guardian Console**: Operator UI served alongside the control-plane API
- **Hook/Plugin Runtime**: Signed plugin distribution with GCS or S3 artifact storage and encrypted plugin secrets
- **Agent Registration**: Ed25519-signed verifiable credentials issued to onboarding agents

The chart also bundles PostgreSQL (Bitnami) and an optional HAProxy ingress controller.

Public routes (`ingress.enabled`), agent registration (`llmGateway.registration.enabled`), the Guardian console (`guardianUI.enabled`), and the bundled HAProxy controller all default to `false`. A default install stays cluster-internal and allocates no LoadBalancer; enable each once hostnames, TLS, and an auth policy have been chosen.

## Configuration Model

The Gateway Stack uses runtime configuration injected via container arguments and environment variables. Application configuration is provided through Helm values and applied to the container at startup.

The llm-gateway and control-plane containers also receive `LLM_GATEWAY_SERVICE_VERSION` and `CONTROL_PLANE_SERVICE_VERSION` respectively, auto-populated from `Chart.Version` and not user-configurable. These carry the service-prefixed names each service's config loader expects, rather than the bare `SERVICE_VERSION` used by the platform charts.

This allows:

- A single immutable container image across environments
- Configuration changes without rebuilding images
- Clear separation of infrastructure and application settings
- Automatic configuration inheritance from umbrella chart globals

Both backend services also support TOML runtime files with `--config`, which this chart does not use by default. See [Optional TOML Runtime Files](#optional-toml-runtime-files).

## Prerequisites

- Kubernetes 1.29+
- Helm 4.0+
- PostgreSQL database (bundled with this chart, or provided by the umbrella chart or external)
- Ingress controller (bundled HAProxy, NGINX, Traefik, etc.) when `ingress.enabled=true`
- TLS certificates (manual or via cert-manager) when `ingress.tls.enabled=true`
- Object storage (GCS or S3-compatible) when the plugin runtime is enabled

## Deployment

When deployed via the `governance-platform` umbrella chart, the Gateway Stack inherits its database and adapter configuration from global values. It is disabled by default there; enable it with `charts/governance-platform/examples/values-gateway.yaml`.

### Quick Start

```bash
helm dependency update charts/gateway-stack
helm upgrade --install guardian charts/gateway-stack \
  --namespace guardian \
  --create-namespace \
  -f charts/gateway-stack/examples/values-gke.yaml
```

### Example Values Files

All example files are sanitized and safe to copy:

| File                          | Demonstrates                                                                                                           |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `examples/values-gke.yaml`    | GKE with Workload Identity, GCS plugin artifact storage, and cert-manager DNS-01 via Cloud DNS                         |
| `examples/values-dev.yaml`    | Development install with cert-manager HTTP-01 behind a dedicated HAProxy ingress class and inline database credentials |
| `examples/values-stag.yaml`   | Staging install with Google OIDC bearer verification and PostgreSQL credentials from a pre-created Secret              |
| `examples/values-onprem.yaml` | Air-gapped install with an external database, S3-compatible plugin artifact storage, and pre-issued TLS certificates   |

### Required Configuration

Set these before a production install. Image tags are omitted deliberately: leaving
`image.tag` empty resolves to the chart `appVersion`, which the platform release
process pins to the release version. Set a tag only to pin outside a release.

- `llmGateway.image.repository`
- `llmGateway.registration.credentialSigner.existingSecret` when `llmGateway.registration.enabled=true`
- `controlPlane.image.repository`
- `controlPlane.auth.enabled=true`
- `controlPlane.auth.bearer.enabled=true` (for CLI/device onboarding flows)
- `controlPlane.auth.bearer.issuerURL`
- `controlPlane.auth.bearer.clientID`
- One of:
  - `controlPlane.auth.existingSecret` with keys for `registrationTokenSecret`, `googleClientID`, and `googleClientSecret` (plus `stateSecret` when `controlPlane.auth.google.enabled=true`)
  - inline values `controlPlane.auth.registrationTokenSecret`, `controlPlane.auth.google.clientID`, `controlPlane.auth.google.clientSecret` (plus `controlPlane.auth.stateSecret` when `controlPlane.auth.google.enabled=true`)
- `controlPlane.auth.google.redirectURL`
- `ingress.enabled=true` (plus `haproxyIngress.enabled=true` unless an existing ingress controller serves `ingress.className`)
- `ingress.hosts.llmGateway`
- `ingress.hosts.controlPlane`
- `ingress.certManager.clusterIssuer`
- `database.password` and `postgresql.auth.password` (keep these in sync when the bundled database is enabled)

To have this chart create the ACME issuer for you, also set:

- `ingress.certManager.createClusterIssuer=true`
- `ingress.certManager.acme.email`
- `ingress.certManager.acme.server`
- `ingress.certManager.acme.solver` (`dns01` or `http01`)
- `ingress.certManager.acme.dns01` (required when solver is `dns01`)

## Values

### Global Parameters (Umbrella Chart)

When deployed via the umbrella chart, these global values are automatically used:

| Key                                     | Type   | Description                                                                   |
| --------------------------------------- | ------ | ----------------------------------------------------------------------------- |
| global.imageRegistryOverride            | string | Replace only the image registry host (e.g., `registry.customer.example`)      |
| global.imageRepositoryPrefixOverride    | string | Replace the full EQTY image repository prefix (e.g., `registry.example/eqty`) |
| global.imagePullPolicy                  | string | Default image pull policy for platform installs                               |
| global.imagePullSecrets                 | list   | Image pull secrets applied to every workload in this chart                    |
| global.secrets.imageRegistry.secretName | string | Name of image pull secret                                                     |

### Chart-Specific Parameters

| Key              | Type   | Default | Description                                                         |
| ---------------- | ------ | ------- | ------------------------------------------------------------------- |
| enabled          | bool   | `true`  | Enable this subchart (umbrella chart only)                          |
| imagePullSecrets | list   | `[]`    | Additional image pull secrets (beyond global)                       |
| nameOverride     | string | `""`    | Override the chart name used for resource naming                    |
| fullnameOverride | string | `""`    | Override the full name prefix for every resource this chart creates |

### Database

| Key                          | Type   | Default              | Description                                                          |
| ---------------------------- | ------ | -------------------- | -------------------------------------------------------------------- |
| database.host                | string | `""`                 | Database host (defaults to `{Release.Name}-postgresql`)              |
| database.port                | int    | `5432`               | Database port                                                        |
| database.sslMode             | string | `"disable"`          | PostgreSQL SSL mode                                                  |
| database.existingSecret      | string | `""`                 | Pre-created Secret holding the connection DSN                        |
| database.secretKeys.dsn      | string | `"dsn"`              | Key holding the DSN                                                  |
| database.secretKeys.username | string | `"username"`         | Key holding the username                                             |
| database.secretKeys.password | string | `"password"`         | Key holding the password                                             |
| database.secretKeys.database | string | `"database"`         | Key holding the database name                                        |
| database.user                | string | `"guardian"`         | Database user                                                        |
| database.password            | string | `"change-me"`        | Database password; rejected at render time while left at `change-me` |
| database.name                | string | `"guardian_gateway"` | Database name                                                        |

### LLM Gateway

| Key                                   | Type   | Default                                  | Description                                                 |
| ------------------------------------- | ------ | ---------------------------------------- | ----------------------------------------------------------- |
| llmGateway.replicaCount               | int    | `1`                                      | Number of replicas to deploy                                |
| llmGateway.image.repository           | string | `"ghcr.io/eqtylab/guardian-llm-gateway"` | Container image repository                                  |
| llmGateway.image.tag                  | string | `""`                                     | Overrides the image tag (default is chart appVersion)       |
| llmGateway.image.pullPolicy           | string | `"IfNotPresent"`                         | Image pull policy                                           |
| llmGateway.listenAddr                 | string | `":10000"`                               | Listen address                                              |
| llmGateway.deploymentEnvironment      | string | `""`                                     | Reported on audit events and used by gateway runtime policy |
| llmGateway.service.enabled            | bool   | `true`                                   | Create a Service resource                                   |
| llmGateway.service.type               | string | `"ClusterIP"`                            | Kubernetes service type                                     |
| llmGateway.service.port               | int    | `10000`                                  | Service port                                                |
| llmGateway.upstreams.anthropicURL     | string | `"https://api.anthropic.com"`            | Anthropic upstream URL                                      |
| llmGateway.upstreams.openaiURL        | string | `"https://api.openai.com"`               | OpenAI upstream URL                                         |
| llmGateway.signature.label            | string | `"sig1"`                                 | RFC 9421 signature label                                    |
| llmGateway.signature.defaultSigMaxAge | string | `"60s"`                                  | Maximum accepted signature age                              |
| llmGateway.signature.defaultClockSkew | string | `"120s"`                                 | Allowed clock skew                                          |
| llmGateway.extraArgs                  | list   | `[]`                                     | Extra container arguments                                   |
| llmGateway.extraEnv                   | list   | `[]`                                     | Extra environment variables                                 |
| llmGateway.resources                  | object | `{}`                                     | Resource requests and limits                                |

### LLM Gateway Registration and Audit

| Key                                                     | Type   | Default                           | Description                                  |
| ------------------------------------------------------- | ------ | --------------------------------- | -------------------------------------------- |
| llmGateway.registration.enabled                         | bool   | `false`                           | Enable agent registration                    |
| llmGateway.registration.credentialSigner.seed           | string | `""`                              | Inline Ed25519 seed; prefer `existingSecret` |
| llmGateway.registration.credentialSigner.existingSecret | string | `""`                              | Pre-created Secret holding the signer seed   |
| llmGateway.registration.credentialSigner.secretKey      | string | `"seed"`                          | Key within the signer Secret                 |
| llmGateway.audit.enabled                                | bool   | `true`                            | Enable audit logging                         |
| llmGateway.audit.queueDir                               | string | `"/var/lib/guardian/audit-queue"` | Audit queue directory (emptyDir)             |
| llmGateway.audit.queueMaxBytes                          | int    | `10737418240`                     | Audit queue size cap (10 GiB)                |
| llmGateway.audit.batchSize                              | int    | `100`                             | Audit batch size                             |
| llmGateway.audit.flushInterval                          | string | `"1s"`                            | Audit flush interval                         |
| llmGateway.audit.retentionDays                          | int    | `90`                              | Audit retention in days                      |

### LLM Gateway Plugin Runtime

| Key                                                     | Type   | Default                                | Description                                                      |
| ------------------------------------------------------- | ------ | -------------------------------------- | ---------------------------------------------------------------- |
| llmGateway.plugins.enabled                              | bool   | `false`                                | Enable the plugin runtime                                        |
| llmGateway.plugins.pollInterval                         | string | `"15s"`                                | Plugin poll interval                                             |
| llmGateway.plugins.authorizerShadowEnabled              | bool   | `false`                                | Evaluate authorizer plugins without enforcing decisions          |
| llmGateway.plugins.endQueueDir                          | string | `"/var/lib/guardian/plugin-end-queue"` | Async `request.end` queue directory                              |
| llmGateway.plugins.endQueueMaxBytes                     | int    | `134217728`                            | End queue size cap (128 MiB)                                     |
| llmGateway.plugins.artifactCacheDir                     | string | `"/var/lib/guardian/plugin-artifacts"` | Plugin artifact cache directory                                  |
| llmGateway.plugins.artifactStorage.provider             | string | `""`                                   | Artifact storage provider (`gcs` or `s3`)                        |
| llmGateway.plugins.artifactStorage.bucket               | string | `""`                                   | Artifact storage bucket                                          |
| llmGateway.plugins.artifactStorage.prefix               | string | `""`                                   | Artifact storage key prefix                                      |
| llmGateway.plugins.trustedSignerKeys                    | object | `{}`                                   | Map of signer key ID to did:key public key                       |
| llmGateway.plugins.secrets.resolutionOrder              | list   | `[]`                                   | Secret resolver order; prefer `["store"]` for shared deployments |
| llmGateway.plugins.secrets.encryptionKey.existingSecret | string | `""`                                   | Secret holding the plugin secret encryption key                  |
| llmGateway.plugins.secretEnvs                           | object | `{}`                                   | Inline plugin secret env vars (local/dev fallback)               |
| llmGateway.plugins.secretEnvsSecret.name                | string | `""`                                   | Secret providing plugin secret env vars (local/dev fallback)     |

### Control Plane

| Key                                                | Type   | Default                                    | Description                                           |
| -------------------------------------------------- | ------ | ------------------------------------------ | ----------------------------------------------------- |
| controlPlane.replicaCount                          | int    | `1`                                        | Number of replicas to deploy                          |
| controlPlane.image.repository                      | string | `"ghcr.io/eqtylab/guardian-control-plane"` | Container image repository                            |
| controlPlane.image.tag                             | string | `""`                                       | Overrides the image tag (default is chart appVersion) |
| controlPlane.image.pullPolicy                      | string | `"IfNotPresent"`                           | Image pull policy                                     |
| controlPlane.listenAddr                            | string | `":10010"`                                 | Listen address                                        |
| controlPlane.apiBasePath                           | string | `""`                                       | API base path; set with `ingress.controlPlanePath`    |
| controlPlane.corsAllowAll                          | bool   | `true`                                     | Allow all CORS origins                                |
| controlPlane.service.enabled                       | bool   | `true`                                     | Create a Service resource                             |
| controlPlane.service.type                          | string | `"ClusterIP"`                              | Kubernetes service type                               |
| controlPlane.service.port                          | int    | `10010`                                    | Service port                                          |
| controlPlane.extraArgs                             | list   | `[]`                                       | Extra container arguments                             |
| controlPlane.extraEnv                              | list   | `[]`                                       | Extra environment variables                           |
| controlPlane.resources                             | object | `{}`                                       | Resource requests and limits                          |
| controlPlane.waitForRegistryViews.enabled          | bool   | `true`                                     | Wait for llm-gateway migrations before starting       |
| controlPlane.waitForRegistryViews.image.repository | string | `"docker.io/library/postgres"`             | Init container image supplying `psql`                 |
| controlPlane.waitForRegistryViews.image.tag        | string | `"17.6"`                                   | Init container image tag                              |
| controlPlane.waitForRegistryViews.image.pullPolicy | string | `"IfNotPresent"`                           | Init container image pull policy                      |
| controlPlane.waitForRegistryViews.intervalSeconds  | int    | `2`                                        | Poll interval                                         |

### Control Plane Authentication

| Key                                         | Type   | Default                         | Description                                                                  |
| ------------------------------------------- | ------ | ------------------------------- | ---------------------------------------------------------------------------- |
| controlPlane.auth.enabled                   | bool   | `false`                         | Enable authentication                                                        |
| controlPlane.auth.existingSecret            | string | `""`                            | Pre-created Secret holding auth material                                     |
| controlPlane.auth.cookieDomain              | string | `""`                            | Session cookie domain                                                        |
| controlPlane.auth.cookieSecure              | bool   | `true`                          | Secure session cookies                                                       |
| controlPlane.auth.allowedEmailDomains       | list   | `[]`                            | Email domains permitted to sign in                                           |
| controlPlane.auth.bootstrapAdminEmail       | string | `""`                            | Account granted admin on first boot                                          |
| controlPlane.auth.stateSecret               | string | `""`                            | OAuth state secret                                                           |
| controlPlane.auth.registrationTokenSecret   | string | `"change-me"`                   | Registration token secret; rejected at render time while left at `change-me` |
| controlPlane.auth.registrationTokenIssuer   | string | `"control-plane"`               | Registration token issuer                                                    |
| controlPlane.auth.sessionMaxAge             | string | `"12h"`                         | Session maximum age                                                          |
| controlPlane.auth.sessionIdleTimeout        | string | `"2h"`                          | Session idle timeout                                                         |
| controlPlane.auth.uiBaseURL                 | string | `""`                            | Console base URL                                                             |
| controlPlane.auth.localDevEnabled           | bool   | `false`                         | Route OAuth callbacks to a local dev server; never enable in production      |
| controlPlane.auth.bearer.enabled            | bool   | `false`                         | Enable bearer token verification                                             |
| controlPlane.auth.bearer.mode               | string | `""`                            | `oidc` (default) or `auth_service`                                           |
| controlPlane.auth.bearer.issuerURL          | string | `""`                            | Bearer issuer URL (`oidc` mode)                                              |
| controlPlane.auth.bearer.clientID           | string | `""`                            | Bearer client ID (`oidc` mode)                                               |
| controlPlane.auth.bearer.authServiceBaseURL | string | `""`                            | Auth service URL (`auth_service` mode); falls back to the adapter URL        |
| controlPlane.auth.bearer.scopes             | list   | `["openid","profile","email"]`  | Bearer scopes                                                                |
| controlPlane.auth.google.enabled            | bool   | `false`                         | Enable Google sign-in                                                        |
| controlPlane.auth.google.issuerURL          | string | `"https://accounts.google.com"` | Google issuer URL                                                            |
| controlPlane.auth.google.clientID           | string | `""`                            | Google OAuth client ID                                                       |
| controlPlane.auth.google.clientSecret       | string | `""`                            | Google OAuth client secret                                                   |
| controlPlane.auth.google.redirectURL        | string | `""`                            | Google OAuth redirect URL                                                    |
| controlPlane.auth.google.scopes             | list   | `["openid","profile","email"]`  | Google scopes                                                                |

### Control Plane Adapter

| Key                                                   | Type   | Default | Description                                                  |
| ----------------------------------------------------- | ------ | ------- | ------------------------------------------------------------ |
| controlPlane.adapter.enabled                          | bool   | `false` | Enable the Governance Studio adapter                         |
| controlPlane.adapter.authServiceBaseURL               | string | `""`    | Defaults to `http://{Release.Name}-auth-service:8080`        |
| controlPlane.adapter.governanceServiceBaseURL         | string | `""`    | Defaults to `http://{Release.Name}-governance-service:10001` |
| controlPlane.adapter.integrityBaseURL                 | string | `""`    | Defaults to `http://{Release.Name}-integrity-service:3050`   |
| controlPlane.adapter.httpTimeout                      | string | `"5s"`  | Adapter HTTP timeout                                         |
| controlPlane.adapter.projectRuntimeReadTimeout        | string | `"5s"`  | Project runtime read timeout                                 |
| controlPlane.adapter.integrityHTTPTimeout             | string | `"5s"`  | Integrity HTTP timeout                                       |
| controlPlane.adapter.integrityStatusCacheTTL          | string | `"5m"`  | Integrity status cache TTL                                   |
| controlPlane.adapter.trustedMembershipIssuerDIDs      | list   | `[]`    | Trusted membership credential issuers                        |
| controlPlane.adapter.trustedComplianceIssuerDIDs      | list   | `[]`    | Trusted compliance credential issuers                        |
| controlPlane.adapter.allowEmbeddedCredentialBootstrap | bool   | `false` | Allow embedded credential bootstrap                          |

### Control Plane Plugin Management

| Key                                                       | Type   | Default                                    | Description                                     |
| --------------------------------------------------------- | ------ | ------------------------------------------ | ----------------------------------------------- |
| controlPlane.plugins.publisherSigner.keyID                | string | `""`                                       | Publisher signer key ID                         |
| controlPlane.plugins.publisherSigner.existingSecret       | string | `""`                                       | Secret holding the publisher signer seed        |
| controlPlane.plugins.publisherSigner.secretKey            | string | `"seed"`                                   | Key within the signer Secret                    |
| controlPlane.plugins.publisherSigner.mountPath            | string | `"/run/secrets/guardian-plugin-publisher"` | Signer seed mount path                          |
| controlPlane.plugins.artifactStorage.provider             | string | `""`                                       | Artifact storage provider (`gcs` or `s3`)       |
| controlPlane.plugins.artifactStorage.bucket               | string | `""`                                       | Artifact storage bucket                         |
| controlPlane.plugins.artifactStorage.prefix               | string | `""`                                       | Artifact storage key prefix                     |
| controlPlane.plugins.artifactStorage.maxUploadBytes       | int    | `536870912`                                | Maximum upload size (512 MiB)                   |
| controlPlane.plugins.artifactStorage.gcs.kmsKeyName       | string | `""`                                       | GCS KMS key name                                |
| controlPlane.plugins.trustedSignerKeys                    | object | `{}`                                       | Map of signer key ID to did:key public key      |
| controlPlane.plugins.secrets.encryptionKey.existingSecret | string | `""`                                       | Secret holding the plugin secret encryption key |
| controlPlane.virusTotal.enabled                           | bool   | `false`                                    | Enable VirusTotal upload scanning               |
| controlPlane.virusTotal.existingSecret                    | string | `""`                                       | Secret holding the VirusTotal API key           |
| controlPlane.virusTotal.secretKey                         | string | `"api-key"`                                | Key within the VirusTotal Secret                |

### Guardian Console

| Key                            | Type   | Default                              | Description                                           |
| ------------------------------ | ------ | ------------------------------------ | ----------------------------------------------------- |
| guardianUI.enabled             | bool   | `false`                              | Enable the Guardian console                           |
| guardianUI.replicaCount        | int    | `1`                                  | Number of replicas to deploy                          |
| guardianUI.image.repository    | string | `"ghcr.io/eqtylab/guardian-console"` | Container image repository                            |
| guardianUI.image.tag           | string | `""`                                 | Overrides the image tag (default is chart appVersion) |
| guardianUI.image.pullPolicy    | string | `"IfNotPresent"`                     | Image pull policy                                     |
| guardianUI.containerPort       | int    | `80`                                 | Container port                                        |
| guardianUI.service.enabled     | bool   | `true`                               | Create a Service resource                             |
| guardianUI.service.type        | string | `"ClusterIP"`                        | Kubernetes service type                               |
| guardianUI.service.port        | int    | `80`                                 | Service port                                          |
| guardianUI.runtime.environment | string | `"production"`                       | Runtime environment                                   |
| guardianUI.runtime.appTitle    | string | `"Gateway Guardian"`                 | Application title                                     |
| guardianUI.runtime.appHostname | string | `""`                                 | Application hostname                                  |
| guardianUI.runtime.apiURL      | string | `""`                                 | Control-plane API URL                                 |
| guardianUI.runtime.basePath    | string | `"/"`                                | Base path                                             |
| guardianUI.extraEnv            | list   | `[]`                                 | Extra environment variables                           |
| guardianUI.resources           | object | `{}`                                 | Resource requests and limits                          |

### Plugin Artifact Storage Backends

These keys exist identically under both `llmGateway.plugins.artifactStorage` and `controlPlane.plugins.artifactStorage`. Replace `<workload>` with either `llmGateway` or `controlPlane`.

| Key                                                                | Type   | Default             | Description                                                    |
| ------------------------------------------------------------------ | ------ | ------------------- | -------------------------------------------------------------- |
| \<workload\>.plugins.artifactStorage.gcs.endpoint                  | string | `""`                | GCS endpoint override                                          |
| \<workload\>.plugins.artifactStorage.s3.endpoint                   | string | `""`                | S3 endpoint override                                           |
| \<workload\>.plugins.artifactStorage.s3.region                     | string | `""`                | S3 region; required when provider is `s3`                      |
| \<workload\>.plugins.artifactStorage.s3.forcePathStyle             | bool   | `false`             | Use path-style S3 addressing                                   |
| \<workload\>.plugins.artifactStorage.s3.accessKeyID                | string | `""`                | S3 access key ID; required when no `existingSecret` is set     |
| \<workload\>.plugins.artifactStorage.s3.secretAccessKey            | string | `""`                | S3 secret access key; required when no `existingSecret` is set |
| \<workload\>.plugins.artifactStorage.s3.existingSecret             | string | `""`                | Pre-created Secret holding the S3 credentials                  |
| \<workload\>.plugins.artifactStorage.s3.secretKeys.accessKeyID     | string | `"accessKeyID"`     | Key holding the access key ID                                  |
| \<workload\>.plugins.artifactStorage.s3.secretKeys.secretAccessKey | string | `"secretAccessKey"` | Key holding the secret access key                              |
| \<workload\>.plugins.secrets.encryptionKey.secretKey               | string | `"encryption-key"`  | Key holding the plugin secret encryption key                   |

### Ingress

| Key                                           | Type   | Default                                            | Description                                                         |
| --------------------------------------------- | ------ | -------------------------------------------------- | ------------------------------------------------------------------- |
| ingress.enabled                               | bool   | `false`                                            | Enable ingress                                                      |
| ingress.className                             | string | `"haproxy"`                                        | Ingress class name                                                  |
| ingress.annotations                           | object | `{}`                                               | Annotations applied to both Ingress resources                       |
| ingress.llmGatewayAnnotations                 | object | `{}`                                               | Annotations applied to the gateway Ingress only                     |
| ingress.controlPlaneAnnotations               | object | `{}`                                               | Annotations applied to the control-plane Ingress only               |
| ingress.controlPlanePath                      | string | `"/"`                                              | Control-plane path; the console is only routed when this is not `/` |
| ingress.hosts.llmGateway                      | string | `"gateway.example.com"`                            | LLM gateway host                                                    |
| ingress.hosts.controlPlane                    | string | `"control.example.com"`                            | Control-plane host                                                  |
| ingress.tls.enabled                           | bool   | `true`                                             | Enable TLS                                                          |
| ingress.tls.llmGatewaySecretName              | string | `""`                                               | Defaults to `{fullname}-llm-gateway-tls`                            |
| ingress.tls.controlPlaneSecretName            | string | `""`                                               | Defaults to `{fullname}-control-plane-tls`                          |
| ingress.certManager.enabled                   | bool   | `true`                                             | Add the cert-manager cluster-issuer annotation                      |
| ingress.certManager.clusterIssuer             | string | `""`                                               | ClusterIssuer name                                                  |
| ingress.certManager.createClusterIssuer       | bool   | `false`                                            | Create a cluster-scoped ClusterIssuer                               |
| ingress.certManager.acme.email                | string | `""`                                               | ACME registration email                                             |
| ingress.certManager.acme.server               | string | `"https://acme-v02.api.letsencrypt.org/directory"` | ACME directory server                                               |
| ingress.certManager.acme.privateKeySecretName | string | `""`                                               | Defaults to `{fullname}-acme-account-key`                           |
| ingress.certManager.acme.solver               | string | `"dns01"`                                          | ACME solver (`dns01` or `http01`)                                   |
| ingress.certManager.acme.http01.ingressClass  | string | `""`                                               | HTTP-01 solver ingress class                                        |
| ingress.certManager.acme.dns01                | object | `{}`                                               | DNS-01 solver configuration, passed through verbatim                |

### Service Account

Each workload owns its own service account. Replace `<workload>` with `llmGateway`, `controlPlane`, or `guardianUI`.

| Key                                     | Type   | Default | Description                                                                  |
| --------------------------------------- | ------ | ------- | ---------------------------------------------------------------------------- |
| \<workload\>.serviceAccount.create      | bool   | `true`  | Specifies whether a service account should be created                        |
| \<workload\>.serviceAccount.automount   | bool   | `true`  | Automatically mount the ServiceAccount's API credentials                     |
| \<workload\>.serviceAccount.annotations | object | `{}`    | Annotations to add to the service account; bind cloud IAM identities here    |
| \<workload\>.serviceAccount.name        | string | `""`    | The name of the service account (generated if serviceAccount.create is true) |

### Security

Applies to `llmGateway` and `controlPlane` unless noted. Replace `<workload>` with either key.

| Key                                               | Type   | Default                 | Description                                                                             |
| ------------------------------------------------- | ------ | ----------------------- | --------------------------------------------------------------------------------------- |
| \<workload\>.podAnnotations                       | object | `{}`                    | Annotations to add to pods                                                              |
| \<workload\>.podLabels                            | object | `{}`                    | Labels to add to pods                                                                   |
| \<workload\>.podSecurityContext                   | object | `{"runAsNonRoot":true}` | Security context for the pod                                                            |
| \<workload\>.securityContext                      | object | see values.yaml         | Container security context; drops all capabilities and uses a read-only root filesystem |
| controlPlane.waitForRegistryViews.securityContext | object | see values.yaml         | Init container security context, pinned to UID 999                                      |
| guardianUI.podSecurityContext                     | object | `{}`                    | Console pod security context                                                            |
| guardianUI.securityContext                        | object | see values.yaml         | Console container security context; retains `NET_BIND_SERVICE` for port 80              |

Both workloads carry a `checksum/secrets` pod annotation, so changing a chart-managed Secret rolls the pods that read it.

### Resources

These keys exist identically under `llmGateway`, `controlPlane`, and `guardianUI`. Replace `<workload>` with one of them.

| Key                                                        | Type   | Default | Description                          |
| ---------------------------------------------------------- | ------ | ------- | ------------------------------------ |
| \<workload\>.resources                                     | object | `{}`    | CPU/Memory resource requests/limits  |
| \<workload\>.autoscaling.enabled                           | bool   | `false` | Enable horizontal pod autoscaling    |
| \<workload\>.autoscaling.minReplicas                       | int    | `1`     | Minimum number of replicas           |
| \<workload\>.autoscaling.maxReplicas                       | int    | `10`    | Maximum number of replicas           |
| \<workload\>.autoscaling.targetCPUUtilizationPercentage    | int    | `80`    | Target CPU utilization percentage    |
| \<workload\>.autoscaling.targetMemoryUtilizationPercentage | int    | `80`    | Target memory utilization percentage |

> **Note:** Resources are empty by default. For production, set appropriate requests and limits on each workload.

### High Availability

| Key                                             | Type | Default | Description                                                                        |
| ----------------------------------------------- | ---- | ------- | ---------------------------------------------------------------------------------- |
| \<workload\>.podDisruptionBudget.enabled        | bool | `false` | Enable Pod Disruption Budget                                                       |
| \<workload\>.podDisruptionBudget.minAvailable   | int  | `1`     | Minimum available pods during disruptions (only rendered when replicaCount > 1)    |
| \<workload\>.podDisruptionBudget.maxUnavailable | int  | `1`     | Maximum unavailable pods during disruptions (only rendered when replicaCount <= 1) |

### Node Scheduling

| Key                       | Type   | Default | Description                       |
| ------------------------- | ------ | ------- | --------------------------------- |
| \<workload\>.nodeSelector | object | `{}`    | Node labels for pod assignment    |
| \<workload\>.tolerations  | list   | `[]`    | Tolerations for pod assignment    |
| \<workload\>.affinity     | object | `{}`    | Affinity rules for pod assignment |

### Health Checks

| Key                                               | Type | Default | Description                                                      |
| ------------------------------------------------- | ---- | ------- | ---------------------------------------------------------------- |
| llmGateway.probes.startup.failureThreshold        | int  | `180`   | Startup probe failure threshold, sized for long index migrations |
| llmGateway.probes.startup.periodSeconds           | int  | `5`     | Startup probe period                                             |
| llmGateway.probes.liveness.initialDelaySeconds    | int  | `5`     | Liveness probe initial delay                                     |
| llmGateway.probes.liveness.periodSeconds          | int  | `10`    | Liveness probe period                                            |
| llmGateway.probes.readiness.initialDelaySeconds   | int  | `3`     | Readiness probe initial delay                                    |
| llmGateway.probes.readiness.periodSeconds         | int  | `10`    | Readiness probe period                                           |
| controlPlane.probes.liveness.initialDelaySeconds  | int  | `5`     | Liveness probe initial delay                                     |
| controlPlane.probes.liveness.periodSeconds        | int  | `10`    | Liveness probe period                                            |
| controlPlane.probes.readiness.initialDelaySeconds | int  | `3`     | Readiness probe initial delay                                    |
| controlPlane.probes.readiness.periodSeconds       | int  | `10`    | Readiness probe period                                           |

### Bundled PostgreSQL

| Key                                    | Type   | Default                      | Description                                                          |
| -------------------------------------- | ------ | ---------------------------- | -------------------------------------------------------------------- |
| postgresql.enabled                     | bool   | `true`                       | Deploy the bundled Bitnami PostgreSQL                                |
| postgresql.architecture                | string | `"standalone"`               | PostgreSQL architecture                                              |
| postgresql.image.repository            | string | `"bitnamilegacy/postgresql"` | PostgreSQL image repository                                          |
| postgresql.image.tag                   | string | `"17.6.0-debian-12-r4"`      | PostgreSQL image tag                                                 |
| postgresql.auth.username               | string | `"guardian"`                 | Database username                                                    |
| postgresql.auth.password               | string | `"change-me"`                | Database password; rejected at render time while left at `change-me` |
| postgresql.auth.database               | string | `"guardian_gateway"`         | Database name                                                        |
| postgresql.primary.persistence.enabled | bool   | `true`                       | Enable persistence                                                   |
| postgresql.primary.persistence.size    | string | `"20Gi"`                     | Volume size                                                          |

### Bundled HAProxy Ingress Controller

| Key                                                 | Type   | Default             | Description                                        |
| --------------------------------------------------- | ------ | ------------------- | -------------------------------------------------- |
| haproxyIngress.enabled                              | bool   | `false`             | Deploy the bundled HAProxy controller              |
| haproxyIngress.nameOverride                         | string | `"haproxy-ingress"` | Keeps generated object names Kubernetes-compatible |
| haproxyIngress.controller.replicaCount              | int    | `1`                 | Number of controller replicas                      |
| haproxyIngress.controller.service.type              | string | `"LoadBalancer"`    | Controller service type                            |
| haproxyIngress.controller.service.enablePorts.quic  | bool   | `false`             | Enable QUIC port                                   |
| haproxyIngress.controller.service.enablePorts.stat  | bool   | `false`             | Enable stats port                                  |
| haproxyIngress.controller.service.enablePorts.admin | bool   | `false`             | Enable admin port                                  |
| haproxyIngress.controller.service.annotations       | object | `{}`                | Controller service annotations                     |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level values** - Explicitly set in `gateway-stack.*`
2. **Global values** - Set in `global.*` (umbrella chart)
3. **Chart defaults** - Default values from `values.yaml`

## Database Wiring

By default, this chart creates a Secret containing a `dsn` key used by both services.

`database.password` and `postgresql.auth.password` both ship as `change-me` and are rejected at render time, the same way `controlPlane.auth.registrationTokenSecret` is. An install must either set real passwords or supply the credentials through a Secret:

- `database.existingSecret` skips the chart-generated DSN Secret entirely
- `postgresql.auth.existingSecret` skips the bundled database's generated password

If you set `database.existingSecret`, the secret must contain:

- `dsn` (or the key name configured at `database.secretKeys.dsn`)

Example DSN:

```text
postgres://guardian:<password>@<host>:5432/guardian_gateway?sslmode=disable
```

The chart-generated DSN percent-encodes `database.user` and `database.password`, so passwords containing `@`, `/`, `?`, `#`, or `:` are safe. A DSN supplied through `database.existingSecret` is used verbatim — percent-encode its userinfo yourself before storing it.

## Control-Plane Auth Secret Wiring

When `controlPlane.auth.enabled=true` or `llmGateway.registration.enabled=true`, the chart reads security material from a single Kubernetes Secret.

- If `controlPlane.auth.existingSecret` is set, that secret is used as-is.
- If it is unset, the chart creates a Secret from inline values.

Expected secret keys:

- `stateSecret` (required when Google auth is enabled; override via `controlPlane.auth.secretKeys.stateSecret`)
- `registrationTokenSecret` (override via `controlPlane.auth.secretKeys.registrationTokenSecret`)
- `googleClientID` (required when Google auth is enabled; override via `controlPlane.auth.secretKeys.googleClientID`)
- `googleClientSecret` (required when Google auth is enabled; override via `controlPlane.auth.secretKeys.googleClientSecret`)

When `llmGateway.registration.enabled=true`, `llm-gateway` reads `registrationTokenSecret` from this secret as `LLM_GATEWAY_REGISTRATION_TOKEN_SECRET`.

## Gateway VC Issuer Signer Wiring

When `llmGateway.registration.enabled=true`, the gateway also needs an Ed25519 seed so it can issue registration and renewal verifiable credentials. Prefer a pre-created Kubernetes Secret:

```yaml
llmGateway:
  registration:
    enabled: true
    credentialSigner:
      existingSecret: guardian-dev-llm-gateway-credential-signer
      secretKey: seed
```

The chart injects that key into the `llm-gateway` container as `LLM_GATEWAY_CREDENTIAL_SIGNER_SEED`. The seed value may be base64, base64url, or hex. For local-only installs, you can set `llmGateway.registration.credentialSigner.seed` and the chart will create the Secret, but avoid inline seeds for shared environments because Helm stores rendered values in release history.

## Hook/Plugin Runtime

When `llmGateway.plugins.enabled=true`, the chart wires the gateway hook runtime, async `request.end` queue, artifact cache, and signer trust keys. See `docs/plugin-runtime-bootstrap.md` for the full bootstrap procedure.

For shared deployments, prefer `llmGateway.plugins.secrets.resolutionOrder: ["store"]` and configure both the control-plane and llm-gateway with the same generic `plugins.secrets.encryptionKey.existingSecret`. End users then set integration secret values through the control-plane plugin secret API while snapshots keep only `secret_ref` objects. `llmGateway.plugins.secretEnvs` and `secretEnvsSecret` remain available as local/dev fallback paths; when either is set and no explicit resolver order is provided, the chart enables the `env` resolver automatically.

For GCS-backed artifacts, bind both service accounts to cloud IAM identities that can read/write the shared bucket.

To let the control-plane sign uploaded plugin artifacts and project configuration manifests server-side, create a Secret containing the encoded Ed25519 seed and configure the publisher signer:

```yaml
controlPlane:
  plugins:
    publisherSigner:
      keyID: signer-dev-v1
      existingSecret: guardian-plugin-publisher-signer
      secretKey: seed
```

The chart mounts only the selected Secret key into the control-plane pod. Keep the corresponding public key trusted by every gateway that consumes artifacts or snapshots signed by this signer.

## OpenTelemetry Configuration

The gateway OTEL bootstrap reads standard `OTEL_*` environment variables. Use `llmGateway.extraEnv` to pass exporter and resource settings into the `llm-gateway` container.

```yaml
llmGateway:
  extraEnv:
    - name: OTEL_TRACES_EXPORTER
      value: otlp
    - name: OTEL_LOGS_EXPORTER
      value: otlp
    - name: OTEL_EXPORTER_OTLP_ENDPOINT
      value: http://otel-collector.observability.svc.cluster.local:4318
    - name: OTEL_EXPORTER_OTLP_PROTOCOL
      value: http/protobuf
    - name: OTEL_RESOURCE_ATTRIBUTES
      value: service.name=guardian-llm-gateway,deployment.environment=production
    - name: LLM_GATEWAY_DEPLOYMENT_ENVIRONMENT
      value: production
```

Set `deployment.environment` in `OTEL_RESOURCE_ATTRIBUTES` to match the target environment, for example `staging`.

This chart does not deploy a Collector. The `OTEL_EXPORTER_OTLP_ENDPOINT` value must point to an existing Collector service that you operate separately.

Notes:

- `LLM_GATEWAY_DEPLOYMENT_ENVIRONMENT` is used by gateway runtime policy.
- If `LLM_GATEWAY_DEPLOYMENT_ENVIRONMENT` is unset, gateway runtime falls back to `deployment.environment` from `OTEL_RESOURCE_ATTRIBUTES`.

For Splunk forwarding using `gateway OTLP logs -> Collector -> Splunk HEC`, see `docs/splunk-hec-log-forwarding.md`. For scraping the native Prometheus endpoint, see `docs/prometheus-metrics.md`.

## Ingress Behavior

This chart creates separate Ingress resources:

- `https://<llmGateway host>/` -> `llm-gateway`
- `https://<controlPlane host><ingress.controlPlanePath>` -> `control-plane`

`control-plane` is publicly exposed when ingress is enabled.

If `guardianUI.enabled=true` and `ingress.controlPlanePath` is not `/`, the chart also routes `https://<controlPlane host>/` to the Guardian console. At the default `controlPlanePath: /` the console has no ingress route, because the control-plane API already occupies the host root.

When `ingress.certManager.enabled=true`, ingresses include the `cert-manager.io/cluster-issuer` annotation. If `ingress.certManager.createClusterIssuer=true`, this chart also creates a `ClusterIssuer` configured for ACME validation using either DNS-01 or HTTP-01.

For GKE with Cloud DNS and DNS-01, configure:

- `ingress.certManager.acme.solver=dns01`
- `ingress.certManager.acme.dns01.cloudDNS.project`
- `ingress.certManager.acme.dns01.cloudDNS.hostedZoneName`
- `ingress.certManager.acme.dns01.cloudDNS.serviceAccountSecretRef`

For `ClusterIssuer`, the Cloud DNS service account secret must exist in the cert-manager cluster resource namespace (typically `cert-manager`).

When installing the bundled HAProxy subchart, this chart sets `haproxyIngress.nameOverride: haproxy-ingress` to ensure generated object names stay lowercase and Kubernetes-compatible.

For GKE `LoadBalancer` services, this chart also disables HAProxy QUIC/UDP and the extra `stat`/`admin` service ports by default to avoid mixed-protocol LB errors.

## Control-Plane API Base Path

When exposing control-plane behind a path prefix (for example `/api`), set both:

- `ingress.controlPlanePath=/api`
- `controlPlane.apiBasePath=/api`

## Postgres Migration Behavior

`llm-gateway` applies SQL migrations on startup. `control-plane` waits for `v_registry_agents` to appear before it starts, which avoids startup races. The gateway startup probe allows long-running concurrent index migrations to finish before liveness checks can restart the pod. Migration contenders poll a non-blocking advisory lock so they do not retain database snapshots while a concurrent index build is waiting to finish.

## Bitnami PostgreSQL Image Source

The chart pins PostgreSQL to `bitnamilegacy/postgresql` by default because versioned tags for `bitnami/postgresql` may not be available on Docker Hub.

For air-gapped installs, `global.imageRegistryOverride` and `global.imageRepositoryPrefixOverride` redirect every image this chart owns, including the `psql` init container. They do **not** reach the bundled Bitnami subchart, which reads its own `global.imageRegistry`; mirror that image separately or set `postgresql.image.repository` directly.

## Optional TOML Runtime Files

Both backend services support TOML runtime files with `--config`:

- llm-gateway: `--config` or `LLM_GATEWAY_CONFIG_FILE`
- control-plane: `--config` or `CONTROL_PLANE_CONFIG_FILE`

Source precedence is:

1. defaults
2. config file
3. environment variables
4. CLI flags

This chart keeps args and env as the default wiring. To use TOML files in-cluster, mount a `ConfigMap` or `Secret` and pass `--config=<mounted-path>` via `extraArgs`.

## Additional Guides

| Guide                               | Covers                                                      |
| ----------------------------------- | ----------------------------------------------------------- |
| `docs/google-workspace-sso.md`      | Google Workspace SSO setup for the control plane            |
| `docs/plugin-runtime-bootstrap.md`  | Hook/plugin bootstrap and signer rotation                   |
| `docs/prometheus-metrics.md`        | Native Prometheus metrics endpoint and scrape configuration |
| `docs/splunk-hec-log-forwarding.md` | Splunk HEC log forwarding via an OpenTelemetry Collector    |

## Troubleshooting

### Viewing Logs

```bash
kubectl logs -f deployment/guardian-llm-gateway -n guardian
kubectl logs -f deployment/guardian-control-plane -n guardian
```

### Checking Pod Status

```bash
kubectl get pods -n guardian -l app.kubernetes.io/name=gateway-stack
kubectl describe pod <pod-name> -n guardian
```

### Verifying Configuration

View the resolved container arguments and environment:

```bash
kubectl get deployment guardian-llm-gateway -n guardian -o yaml
kubectl exec -it deployment/guardian-llm-gateway -n guardian -- env | sort
```

Test the health endpoints:

```bash
kubectl exec -it deployment/guardian-llm-gateway -n guardian -- curl -s localhost:10000/health
kubectl exec -it deployment/guardian-control-plane -n guardian -- curl -s localhost:10010/health
```

### Common Issues

**Render fails with `must not be the default value 'change-me'`**

- Set `database.password` and `postgresql.auth.password`, or supply `database.existingSecret` and `postgresql.auth.existingSecret`
- Set `controlPlane.auth.registrationTokenSecret`, or supply `controlPlane.auth.existingSecret`

**control-plane stuck in Init**

- The `wait-for-registry-views` init container is waiting on llm-gateway migrations
- Check llm-gateway logs for migration progress and confirm both services share one database
- Verify the DSN in the database Secret reaches the intended host

**Guardian console not reachable**

- The console is only routed when `ingress.controlPlanePath` is not `/`; set it and `controlPlane.apiBasePath` to a prefix such as `/api`
- Verify `guardianUI.runtime.apiURL` points at the control-plane API URL

**Agent registration rejected**

- Confirm `llmGateway.registration.enabled=true` and a credential signer seed is present
- Verify llm-gateway and control-plane resolve the same `registrationTokenSecret`
- Check clock skew against `llmGateway.signature.defaultClockSkew`

**Certificates not issued**

- Confirm `ingress.certManager.clusterIssuer` names an existing ClusterIssuer
- For DNS-01, the solver secret must exist in the cert-manager namespace
- `ingress.tls.enabled` defaults to `true`; without an issuer the referenced TLS Secret is never created

**Credential change not taking effect**

- Secrets supplied via `existingSecret` are not tracked by the `checksum/secrets` annotation
- Roll the workload manually: `kubectl rollout restart deployment/guardian-llm-gateway -n guardian`

## Health Endpoints

| Endpoint                                | Service       | Description                                               |
| --------------------------------------- | ------------- | --------------------------------------------------------- |
| `GET /health`                           | llm-gateway   | Liveness, readiness, and startup probe target             |
| `GET {controlPlane.apiBasePath}/health` | control-plane | Liveness and readiness; `/health` when no base path       |
| `GET /`                                 | console       | Liveness and readiness for the Guardian console           |
| `GET /metrics`                          | llm-gateway   | Prometheus metrics on a dedicated port (default `:10001`) |

See `docs/prometheus-metrics.md` for enabling and scraping the metrics endpoint.

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://docs.eqtylab.io
- GitHub: https://github.com/eqtylab/guardian-infrastructure
