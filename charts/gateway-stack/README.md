# Gateway Stack

A Helm chart for deploying the Agent Gateway stack on Kubernetes.

## Description

The Gateway Stack runs the LLM Gateway of the Agent Gateway for the Guardian Platform: a signing proxy in front of upstream model providers. Its management API, the Control Plane, is the [`control-plane`](../control-plane/README.md) chart.

Key capabilities:

- **LLM Gateway**: RFC 9421 signed proxy for Anthropic and OpenAI upstreams, with an append-only audit trail
- **Hook/Plugin Runtime**: Signed plugin distribution with GCS or S3 artifact storage and encrypted plugin secrets
- **Agent Registration**: Ed25519-signed verifiable credentials issued to onboarding agents

The chart also bundles PostgreSQL (Bitnami) and an optional HAProxy ingress controller.

Public routes (`ingress.enabled`), agent registration (`llmGateway.registration.enabled`), and the bundled HAProxy controller all default to `false`. A default install stays cluster-internal and allocates no LoadBalancer; enable each once hostnames, TLS, and an auth policy have been chosen.

## Configuration Model

The Gateway Stack uses runtime configuration injected via container arguments and environment variables. Application configuration is provided through Helm values and applied to the container at startup.

The llm-gateway container also receives `LLM_GATEWAY_SERVICE_VERSION`, auto-populated from `Chart.Version` and not user-configurable. It carries the service-prefixed name the service's config loader expects, rather than the bare `SERVICE_VERSION` used by the platform charts.

This allows:

- A single immutable container image across environments
- Configuration changes without rebuilding images
- Clear separation of infrastructure and application settings
- Automatic configuration inheritance from umbrella chart globals

The LLM Gateway also supports TOML runtime files with `--config`, which this chart does not use by default. See [Optional TOML Runtime Files](#optional-toml-runtime-files).

## Prerequisites

- Kubernetes 1.29+
- Helm 3.20+
- PostgreSQL database (bundled with this chart, or provided by the umbrella chart or external)
- Ingress controller (bundled HAProxy, or an existing controller serving `ingress.className`) when `ingress.enabled=true`
- TLS certificates (manual or via cert-manager) when `ingress.tls.enabled=true`
- Object storage (GCS or S3-compatible) when the plugin runtime is enabled

## Deployment

When deployed via the `guardian-platform` umbrella chart, the Gateway Stack inherits its database configuration and the Control Plane's registration token Secret from global values. It is disabled by default there; enable it with `charts/guardian-platform/examples/values-gateway.yaml`.

### Quick Start

```bash
helm dependency build charts/gateway-stack
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
| `examples/values-stag.yaml`   | Staging install with PostgreSQL credentials from a pre-created Secret                                                  |
| `examples/values-onprem.yaml` | Air-gapped install with an external database, S3-compatible plugin artifact storage, and pre-issued TLS certificates   |

### Required Configuration

Set these before a production install. Image tags are omitted deliberately: leaving
`image.tag` empty resolves to the chart `appVersion`, which the platform release
process pins to the release version. Set a tag only to pin outside a release.
`llmGateway.image` also accepts `digest: sha256:...`, which takes precedence
over its tag while retaining registry mirror behavior.

- `llmGateway.image.repository`
- `llmGateway.registration.credentialSigner.existingSecret` when `llmGateway.registration.enabled=true`
- `global.secrets.controlPlane.secretName` when `llmGateway.registration.enabled=true`: the Control Plane's Secret holding `registration-token-secret`, or the key set in `global.secrets.controlPlane.keys.registrationTokenSecret`
- `ingress.enabled=true` (plus `haproxyIngress.enabled=true` unless an existing ingress controller serves `ingress.className`)
- `ingress.hosts.llmGateway`
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

| Key                                                      | Type   | Description                                                                                               |
| -------------------------------------------------------- | ------ | --------------------------------------------------------------------------------------------------------- |
| global.imageRegistryOverride                             | string | Replace only the image registry host (e.g., `registry.customer.example`)                                  |
| global.imageRepositoryPrefixOverride                     | string | Replace the full EQTY Lab image repository prefix (e.g., `registry.example/eqty`)                         |
| global.imagePullPolicy                                   | string | Default image pull policy for platform installs                                                           |
| global.imagePullSecrets                                  | list   | Image pull secrets for every workload in this chart when global.secrets.imageRegistry.secretName is empty |
| global.secrets.imageRegistry.secretName                  | string | Name of image pull secret                                                                                 |
| global.secrets.controlPlane.secretName                   | string | Secret holding the registration token secret (key `registration-token-secret`)                            |
| global.secrets.controlPlane.keys.registrationTokenSecret | string | Key holding the registration token secret (defaults to `registration-token-secret`)                       |

### Chart-Specific Parameters

| Key              | Type   | Default | Description                                                                                                           |
| ---------------- | ------ | ------- | --------------------------------------------------------------------------------------------------------------------- |
| enabled          | bool   | `true`  | Enable this subchart (umbrella chart only)                                                                            |
| imagePullSecrets | list   | `[]`    | Image pull secrets, used only when global.secrets.imageRegistry.secretName and global.imagePullSecrets are both empty |
| nameOverride     | string | `""`    | Override the chart name used for resource naming                                                                      |
| fullnameOverride | string | `""`    | Override the full name prefix for every resource this chart creates                                                   |

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

| Key                                   | Type   | Default                                  | Description                                                                                 |
| ------------------------------------- | ------ | ---------------------------------------- | ------------------------------------------------------------------------------------------- |
| llmGateway.replicaCount               | int    | `1`                                      | Number of replicas to deploy                                                                |
| llmGateway.image.repository           | string | `"ghcr.io/eqtylab/guardian-llm-gateway"` | Container image repository                                                                  |
| llmGateway.image.tag                  | string | `""`                                     | Overrides the image tag (default is chart appVersion)                                       |
| llmGateway.image.digest               | string | `""`                                     | Immutable sha256 digest; takes precedence over the tag                                      |
| llmGateway.image.pullPolicy           | string | `""`                                     | Image pull policy (auto-configured from global.imagePullPolicy, defaults to `IfNotPresent`) |
| llmGateway.listenAddr                 | string | `":10000"`                               | Listen address                                                                              |
| llmGateway.deploymentEnvironment      | string | `""`                                     | Reported on audit events and used by gateway runtime policy                                 |
| llmGateway.service.enabled            | bool   | `true`                                   | Create a Service resource                                                                   |
| llmGateway.service.type               | string | `"ClusterIP"`                            | Kubernetes service type                                                                     |
| llmGateway.service.port               | int    | `10000`                                  | Service port                                                                                |
| llmGateway.upstreams.anthropicURL     | string | `"https://api.anthropic.com"`            | Anthropic upstream URL                                                                      |
| llmGateway.upstreams.openaiURL        | string | `"https://api.openai.com"`               | OpenAI upstream URL                                                                         |
| llmGateway.signature.label            | string | `"sig"`                                  | RFC 9421 signature label; must match Viper's `sig`                                          |
| llmGateway.signature.defaultSigMaxAge | string | `"60s"`                                  | Maximum accepted signature age                                                              |
| llmGateway.signature.defaultClockSkew | string | `"120s"`                                 | Allowed clock skew                                                                          |
| llmGateway.extraArgs                  | list   | `[]`                                     | Extra container arguments                                                                   |
| llmGateway.extraEnv                   | list   | `[]`                                     | Extra environment variables                                                                 |
| llmGateway.resources                  | object | `{}`                                     | Resource requests and limits                                                                |

### LLM Gateway Registration and Audit

| Key                                                     | Type   | Default                           | Description                                                                                     |
| ------------------------------------------------------- | ------ | --------------------------------- | ----------------------------------------------------------------------------------------------- |
| llmGateway.registration.enabled                         | bool   | `false`                           | Enable agent registration                                                                       |
| llmGateway.registration.tokenIssuer                     | string | `"control-plane"`                 | Registration token issuer; must match the Control Plane's `config.auth.registrationTokenIssuer` |
| llmGateway.registration.credentialSigner.seed           | string | `""`                              | Inline Ed25519 seed; prefer `existingSecret`                                                    |
| llmGateway.registration.credentialSigner.existingSecret | string | `""`                              | Pre-created Secret holding the signer seed                                                      |
| llmGateway.registration.credentialSigner.secretKey      | string | `"seed"`                          | Key within the signer Secret                                                                    |
| llmGateway.authServiceBaseURL                           | string | `""`                              | Auth-service URL for API-key enroll; empty disables that path                                   |
| llmGateway.authServiceIdentityIssuer                    | string | `""`                              | Registry identity issuer; defaults to `<authServiceBaseURL>/api/v1/auth`                        |
| llmGateway.audit.enabled                                | bool   | `true`                            | Enable audit logging                                                                            |
| llmGateway.audit.queueDir                               | string | `"/var/lib/guardian/audit-queue"` | Audit queue directory (emptyDir)                                                                |
| llmGateway.audit.queueMaxBytes                          | int    | `10737418240`                     | Audit queue size cap (10 GiB)                                                                   |
| llmGateway.audit.batchSize                              | int    | `100`                             | Audit batch size                                                                                |
| llmGateway.audit.flushInterval                          | string | `"1s"`                            | Audit flush interval                                                                            |
| llmGateway.audit.retentionDays                          | int    | `90`                              | Audit retention in days                                                                         |

### LLM Gateway Plugin Runtime

| Key                                                     | Type   | Default                                | Description                                                                                                 |
| ------------------------------------------------------- | ------ | -------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| llmGateway.plugins.enabled                              | bool   | `false`                                | Enable the plugin runtime                                                                                   |
| llmGateway.plugins.pollInterval                         | string | `"15s"`                                | Plugin poll interval                                                                                        |
| llmGateway.plugins.authorizerShadowEnabled              | bool   | `false`                                | Evaluate authorizer plugins without enforcing decisions                                                     |
| llmGateway.plugins.endQueueDir                          | string | `"/var/lib/guardian/plugin-end-queue"` | Async `request.end` queue directory                                                                         |
| llmGateway.plugins.endQueueMaxBytes                     | int    | `134217728`                            | End queue size cap (128 MiB)                                                                                |
| llmGateway.plugins.artifactCacheDir                     | string | `"/var/lib/guardian/plugin-artifacts"` | Plugin artifact cache directory                                                                             |
| llmGateway.plugins.artifactStorage.provider             | string | `""`                                   | Artifact storage provider (`gcs`, `s3`, `azure`, or `file`)                                                 |
| llmGateway.plugins.artifactStorage.bucket               | string | `""`                                   | Artifact storage bucket or Azure container; the mount path for `file`                                       |
| llmGateway.plugins.artifactStorage.prefix               | string | `""`                                   | Artifact storage key prefix                                                                                 |
| llmGateway.plugins.trustedSignerKeys                    | object | `{}`                                   | Map of signer key ID to Ed25519 public key (standard-base64 raw 32 bytes or `did:key`)                      |
| llmGateway.plugins.secrets.resolutionOrder              | list   | `[]`                                   | Secret resolver order; prefer `["store"]` for shared deployments                                            |
| llmGateway.plugins.secrets.encryptionKey.existingSecret | string | `""`                                   | Secret holding the plugin secret encryption key                                                             |
| llmGateway.plugins.secretEnvs                           | object | `{}`                                   | Inline plugin secret env vars (local/dev fallback; only rendered when `llmGateway.plugins.enabled` is true) |
| llmGateway.plugins.secretEnvsSecret.name                | string | `""`                                   | Secret providing plugin secret env vars (local/dev fallback)                                                |
| llmGateway.projectContext.mode                          | string | `"disabled"`                           | Project context mode (`disabled`, `observe`, or `enforce`); requires the plugin runtime                     |

### Plugin Artifact Storage Backends

The Control Plane's equivalents are in the [`control-plane`](../control-plane/README.md) chart.

| Key                                                                  | Type   | Default                                       | Description                                                             |
| -------------------------------------------------------------------- | ------ | --------------------------------------------- | ----------------------------------------------------------------------- |
| llmGateway.plugins.artifactStorage.gcs.endpoint                      | string | `""`                                          | GCS endpoint override                                                   |
| llmGateway.plugins.artifactStorage.gcs.existingSecret                | string | `""`                                          | Secret holding a GCS service account JSON; unset uses workload identity |
| llmGateway.plugins.artifactStorage.gcs.secretKey                     | string | `"serviceAccountJson"`                        | Key holding the service account JSON                                    |
| llmGateway.plugins.artifactStorage.gcs.mountPath                     | string | `"/run/secrets/guardian-plugin-artifact-gcs"` | Where the service account JSON is mounted                               |
| llmGateway.plugins.artifactStorage.s3.endpoint                       | string | `""`                                          | S3 endpoint override                                                    |
| llmGateway.plugins.artifactStorage.s3.region                         | string | `""`                                          | S3 region; required when provider is `s3`                               |
| llmGateway.plugins.artifactStorage.s3.forcePathStyle                 | bool   | `false`                                       | Use path-style S3 addressing                                            |
| llmGateway.plugins.artifactStorage.s3.accessKeyID                    | string | `""`                                          | S3 access key ID; required when no `existingSecret` is set              |
| llmGateway.plugins.artifactStorage.s3.secretAccessKey                | string | `""`                                          | S3 secret access key; required when no `existingSecret` is set          |
| llmGateway.plugins.artifactStorage.s3.existingSecret                 | string | `""`                                          | Pre-created Secret holding the S3 credentials                           |
| llmGateway.plugins.artifactStorage.s3.secretKeys.accessKeyID         | string | `"accessKeyID"`                               | Key holding the access key ID                                           |
| llmGateway.plugins.artifactStorage.s3.secretKeys.secretAccessKey     | string | `"secretAccessKey"`                           | Key holding the secret access key                                       |
| llmGateway.plugins.artifactStorage.azure.accountName                 | string | `""`                                          | Storage account name; required with an account key or managed identity  |
| llmGateway.plugins.artifactStorage.azure.endpoint                    | string | `""`                                          | Blob service endpoint override; not with `connectionString`             |
| llmGateway.plugins.artifactStorage.azure.useManagedIdentity          | bool   | `false`                                       | Authenticate with the pod's managed identity                            |
| llmGateway.plugins.artifactStorage.azure.accountKey                  | string | `""`                                          | Account key                                                             |
| llmGateway.plugins.artifactStorage.azure.connectionString            | string | `""`                                          | Connection string                                                       |
| llmGateway.plugins.artifactStorage.azure.existingSecret              | string | `""`                                          | Pre-created Secret holding an account key or a connection string        |
| llmGateway.plugins.artifactStorage.azure.secretKeys.accountKey       | string | `"accountKey"`                                | Key holding the account key                                             |
| llmGateway.plugins.artifactStorage.azure.secretKeys.connectionString | string | `"connectionString"`                          | Key holding the connection string                                       |
| llmGateway.plugins.artifactStorage.file.existingClaim                | string | `""`                                          | ReadWriteMany PVC mounted at `bucket`; required when provider is `file` |
| llmGateway.plugins.secrets.encryptionKey.secretKey                   | string | `"encryption-key"`                            | Key holding the plugin secret encryption key                            |

### Ingress

| Key                                           | Type   | Default                                            | Description                                          |
| --------------------------------------------- | ------ | -------------------------------------------------- | ---------------------------------------------------- |
| ingress.enabled                               | bool   | `false`                                            | Enable ingress                                       |
| ingress.className                             | string | `"haproxy"`                                        | Ingress class name                                   |
| ingress.annotations                           | object | `{}`                                               | Annotations applied to the Ingress                   |
| ingress.llmGatewayAnnotations                 | object | `{}`                                               | Additional annotations applied to the Ingress        |
| ingress.hosts.llmGateway                      | string | `"gateway.example.com"`                            | LLM Gateway host                                     |
| ingress.tls.enabled                           | bool   | `true`                                             | Enable TLS                                           |
| ingress.tls.llmGatewaySecretName              | string | `""`                                               | Defaults to `{fullname}-llm-gateway-tls`             |
| ingress.certManager.enabled                   | bool   | `true`                                             | Add the cert-manager cluster-issuer annotation       |
| ingress.certManager.clusterIssuer             | string | `""`                                               | ClusterIssuer name                                   |
| ingress.certManager.createClusterIssuer       | bool   | `false`                                            | Create a cluster-scoped ClusterIssuer                |
| ingress.certManager.acme.email                | string | `""`                                               | ACME registration email                              |
| ingress.certManager.acme.server               | string | `"https://acme-v02.api.letsencrypt.org/directory"` | ACME directory server                                |
| ingress.certManager.acme.privateKeySecretName | string | `""`                                               | Defaults to `{fullname}-acme-account-key`            |
| ingress.certManager.acme.solver               | string | `"dns01"`                                          | ACME solver (`dns01` or `http01`)                    |
| ingress.certManager.acme.http01.ingressClass  | string | `""`                                               | HTTP-01 solver ingress class                         |
| ingress.certManager.acme.dns01                | object | `{}`                                               | DNS-01 solver configuration, passed through verbatim |

### Service Account

| Key                                   | Type   | Default | Description                                                                  |
| ------------------------------------- | ------ | ------- | ---------------------------------------------------------------------------- |
| llmGateway.serviceAccount.create      | bool   | `true`  | Specifies whether a service account should be created                        |
| llmGateway.serviceAccount.automount   | bool   | `true`  | Automatically mount the ServiceAccount's API credentials                     |
| llmGateway.serviceAccount.annotations | object | `{}`    | Annotations to add to the service account; bind cloud IAM identities here    |
| llmGateway.serviceAccount.name        | string | `""`    | The name of the service account (generated if serviceAccount.create is true) |

### Security

| Key                           | Type   | Default                 | Description                                                                             |
| ----------------------------- | ------ | ----------------------- | --------------------------------------------------------------------------------------- |
| llmGateway.podAnnotations     | object | `{}`                    | Annotations to add to pods                                                              |
| llmGateway.podLabels          | object | `{}`                    | Labels to add to pods                                                                   |
| llmGateway.podSecurityContext | object | `{"runAsNonRoot":true}` | Security context for the pod                                                            |
| llmGateway.securityContext    | object | see values.yaml         | Container security context; drops all capabilities and uses a read-only root filesystem |

The LLM Gateway carries a `checksum/secrets` pod annotation, so changing a chart-managed Secret rolls its pods.

### Resources

| Key                                                      | Type   | Default | Description                          |
| -------------------------------------------------------- | ------ | ------- | ------------------------------------ |
| llmGateway.resources                                     | object | `{}`    | CPU/Memory resource requests/limits  |
| llmGateway.autoscaling.enabled                           | bool   | `false` | Enable horizontal pod autoscaling    |
| llmGateway.autoscaling.minReplicas                       | int    | `1`     | Minimum number of replicas           |
| llmGateway.autoscaling.maxReplicas                       | int    | `10`    | Maximum number of replicas           |
| llmGateway.autoscaling.targetCPUUtilizationPercentage    | int    | `80`    | Target CPU utilization percentage    |
| llmGateway.autoscaling.targetMemoryUtilizationPercentage | int    | `80`    | Target memory utilization percentage |

> **Note:** Resources are empty by default. For production, set appropriate requests and limits.

### High Availability

| Key                                           | Type | Default | Description                                                                                                                             |
| --------------------------------------------- | ---- | ------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| llmGateway.podDisruptionBudget.enabled        | bool | `false` | Enable Pod Disruption Budget                                                                                                            |
| llmGateway.podDisruptionBudget.minAvailable   | int  | `1`     | Minimum available pods during disruptions (only rendered when replicaCount, or autoscaling.minReplicas with autoscaling on, is above 1) |
| llmGateway.podDisruptionBudget.maxUnavailable | int  | `1`     | Maximum unavailable pods during disruptions (only rendered otherwise)                                                                   |

### Node Scheduling

| Key                     | Type   | Default | Description                       |
| ----------------------- | ------ | ------- | --------------------------------- |
| llmGateway.nodeSelector | object | `{}`    | Node labels for pod assignment    |
| llmGateway.tolerations  | list   | `[]`    | Tolerations for pod assignment    |
| llmGateway.affinity     | object | `{}`    | Affinity rules for pod assignment |

### Health Checks

| Key                                             | Type | Default | Description                                                      |
| ----------------------------------------------- | ---- | ------- | ---------------------------------------------------------------- |
| llmGateway.probes.startup.failureThreshold      | int  | `180`   | Startup probe failure threshold, sized for long index migrations |
| llmGateway.probes.startup.periodSeconds         | int  | `5`     | Startup probe period                                             |
| llmGateway.probes.liveness.initialDelaySeconds  | int  | `5`     | Liveness probe initial delay                                     |
| llmGateway.probes.liveness.periodSeconds        | int  | `10`    | Liveness probe period                                            |
| llmGateway.probes.readiness.initialDelaySeconds | int  | `3`     | Readiness probe initial delay                                    |
| llmGateway.probes.readiness.periodSeconds       | int  | `10`    | Readiness probe period                                           |

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

| Key                                                    | Type   | Default                          | Description                                                                                                     |
| ------------------------------------------------------ | ------ | -------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| haproxyIngress.enabled                                 | bool   | `false`                          | Deploy the bundled HAProxy controller                                                                           |
| haproxyIngress.nameOverride                            | string | `"haproxy-ingress"`              | Keeps generated object names Kubernetes-compatible                                                              |
| haproxyIngress.controller.replicaCount                 | int    | `1`                              | Number of controller replicas                                                                                   |
| haproxyIngress.controller.extraArgs                    | list   | `["--disable-quic"]`             | Extra controller arguments; replacing the list drops `--disable-quic`                                           |
| haproxyIngress.controller.pprof.enabled                | bool   | `false`                          | Serve `/debug/pprof` on the admin port (6060)                                                                   |
| haproxyIngress.controller.defaultTLSSecret.secret      | string | `"haproxy-ingress-default-cert"` | Secret HAProxy serves for TLS that names none of its hosts; releases in one namespace need different names      |
| haproxyIngress.controller.defaultTLSSecret.create      | bool   | `true`                           | Create a self-signed Secret with that name; skipped when a Secret of that name exists that Helm does not manage |
| haproxyIngress.controller.config.ssl-redirect-port     | string | `"443"`                          | Port in the Location header of HTTP-to-HTTPS redirects                                                          |
| haproxyIngress.controller.config.global-config-snippet | string | `tune.bufsize 32768`             | HAProxy global settings; the 32 KB buffer must hold a request's or response's headers                           |
| haproxyIngress.controller.service.type                 | string | `"LoadBalancer"`                 | Controller service type                                                                                         |
| haproxyIngress.controller.service.enablePorts.quic     | bool   | `false`                          | Enable QUIC port                                                                                                |
| haproxyIngress.controller.service.enablePorts.stat     | bool   | `false`                          | Enable stats port                                                                                               |
| haproxyIngress.controller.service.enablePorts.admin    | bool   | `false`                          | Enable admin port                                                                                               |
| haproxyIngress.controller.service.annotations          | object | `{}`                             | Controller service annotations                                                                                  |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level values** - Explicitly set in `gateway-stack.*`
2. **Global values** - Set in `global.*` (umbrella chart)
3. **Chart defaults** - Default values from `values.yaml`

## Database Wiring

By default, this chart creates a Secret containing a `dsn` key, which the LLM Gateway reads. The Control Plane reads the same database through its own DSN reference.

`database.password` and `postgresql.auth.password` both ship as `change-me` and are rejected at render time at render time. An install must either set real passwords or supply the credentials through a Secret:

- `database.existingSecret` skips the chart-generated DSN Secret entirely
- `postgresql.auth.existingSecret` skips the bundled database's generated password

If you set `database.existingSecret`, the secret must contain:

- `dsn` (or the key name configured at `database.secretKeys.dsn`)

Example DSN:

```text
postgres://guardian:<password>@<host>:5432/guardian_gateway?sslmode=disable
```

The chart-generated DSN percent-encodes `database.user` and `database.password`, so passwords containing `@`, `/`, `?`, `#`, or `:` are safe. A DSN supplied through `database.existingSecret` is used verbatim — percent-encode its userinfo yourself before storing it.

## Registration Token Wiring

When `llmGateway.registration.enabled=true`, `llm-gateway` reads the Control Plane's registration token secret as `LLM_GATEWAY_REGISTRATION_TOKEN_SECRET`, from the Secret named by `global.secrets.controlPlane.secretName` (default `platform-control-plane`), key `global.secrets.controlPlane.keys.registrationTokenSecret` (default `registration-token-secret`). The umbrella chart creates that Secret from `global.secrets.controlPlane`. `llmGateway.registration.tokenIssuer` must match the Control Plane's `config.auth.registrationTokenIssuer`.

API-key enrollment (`viper did register` with `GUARDIAN_API_KEY`) is a separate path. Set `llmGateway.authServiceBaseURL` to the auth-service that minted the key (for example the in-cluster auth-service Guardian uses). Leaving it empty keeps that path disabled and the gateway returns `404 registration_unavailable`.

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

For shared deployments, prefer `llmGateway.plugins.secrets.resolutionOrder: ["store"]` and give the Control Plane and llm-gateway the same encryption key Secret (`llmGateway.plugins.secrets.encryptionKey.existingSecret` here). End users then set integration secret values through the Control Plane's plugin secret API while snapshots keep only `secret_ref` objects. `llmGateway.plugins.secretEnvs` and `secretEnvsSecret` remain available as local/dev fallback paths; when either is set and no explicit resolver order is provided, the chart enables the `env` resolver automatically.

For GCS-backed artifacts, bind the llm-gateway service account to a cloud IAM identity that can read the shared bucket.

The Control Plane signs uploaded plugin artifacts and project configuration manifests; see the [`control-plane`](../control-plane/README.md) chart. Keep its public key in `llmGateway.plugins.trustedSignerKeys`.

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

This chart creates one Ingress:

- `https://<llmGateway host>/` -> `llm-gateway`

When `ingress.certManager.enabled=true`, ingresses include the `cert-manager.io/cluster-issuer` annotation. If `ingress.certManager.createClusterIssuer=true`, this chart also creates a `ClusterIssuer` configured for ACME validation using either DNS-01 or HTTP-01.

For GKE with Cloud DNS and DNS-01, configure:

- `ingress.certManager.acme.solver=dns01`
- `ingress.certManager.acme.dns01.cloudDNS.project`
- `ingress.certManager.acme.dns01.cloudDNS.hostedZoneName`
- `ingress.certManager.acme.dns01.cloudDNS.serviceAccountSecretRef`

For `ClusterIssuer`, the Cloud DNS service account secret must exist in the cert-manager cluster resource namespace (typically `cert-manager`).

When installing the bundled HAProxy subchart, this chart sets `haproxyIngress.nameOverride: haproxy-ingress` to ensure generated object names stay lowercase and Kubernetes-compatible.

The bundled controller serves `haproxyIngress.controller.defaultTLSSecret.secret` for TLS that names none of its hosts. This chart creates that Secret, self-signed, as a release resource on install and on the upgrade that turns the controller on, and keeps its key across upgrades. To use a Secret you manage, such as one cert-manager keeps, set `defaultTLSSecret.secret` to its name and `defaultTLSSecret.create: false`.

For GKE `LoadBalancer` services, this chart also disables HAProxy QUIC/UDP and the extra `stat`/`admin` service ports by default to avoid mixed-protocol LB errors.

## Postgres Migration Behavior

`llm-gateway` applies SQL migrations on startup. The Control Plane waits for `v_registry_agents` to appear before it starts, which avoids startup races. The gateway startup probe allows long-running concurrent index migrations to finish before liveness checks can restart the pod. Migration contenders poll a non-blocking advisory lock so they do not retain database snapshots while a concurrent index build is waiting to finish.

## Bitnami PostgreSQL Image Source

The chart pins PostgreSQL to `bitnamilegacy/postgresql` by default because versioned tags for `bitnami/postgresql` may not be available on Docker Hub.

For air-gapped installs, `global.imageRegistryOverride` redirects the registry host for images this chart owns. `global.imageRepositoryPrefixOverride` redirects only EQTY Lab images whose source begins with `ghcr.io/eqtylab/`; it leaves upstream images at their existing sources. Neither override reaches the bundled Bitnami subchart, which reads its own `global.imageRegistry`; mirror that image separately or set `postgresql.image.repository` directly.

## Optional TOML Runtime Files

llm-gateway supports TOML runtime files with `--config` or `LLM_GATEWAY_CONFIG_FILE`.

Source precedence is:

1. defaults
2. config file
3. environment variables
4. CLI flags

This chart wires the service through args and env only. It has no values for extra volumes or volume mounts, so it cannot mount a TOML file from a `ConfigMap` or `Secret`. Set runtime options with `llmGateway.extraEnv`, or pass CLI flags with `llmGateway.extraArgs`.

## Additional Guides

| Guide                               | Covers                                                      |
| ----------------------------------- | ----------------------------------------------------------- |
| `docs/plugin-runtime-bootstrap.md`  | Hook/plugin bootstrap and signer rotation                   |
| `docs/prometheus-metrics.md`        | Native Prometheus metrics endpoint and scrape configuration |
| `docs/splunk-hec-log-forwarding.md` | Splunk HEC log forwarding via an OpenTelemetry Collector    |

## Troubleshooting

### Viewing Logs

```bash
kubectl logs -f deployment/guardian-llm-gateway -n guardian
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

Test the health endpoint:

```bash
kubectl exec -it deployment/guardian-llm-gateway -n guardian -- curl -s localhost:10000/health
```

### Common Issues

**Render fails with `must not be the default value 'change-me'`**

- Set `database.password` and `postgresql.auth.password`, or supply `database.existingSecret` and `postgresql.auth.existingSecret`

**Agent registration rejected**

- Confirm `llmGateway.registration.enabled=true` and a credential signer seed is present
- Verify `global.secrets.controlPlane.secretName` names the Secret the Control Plane reads
- Check clock skew against `llmGateway.signature.defaultClockSkew`
- `404 registration_unavailable` / `API-key agent registration is not enabled` means `llmGateway.authServiceBaseURL` is unset, not that the key is invalid

**Certificates not issued**

- Confirm `ingress.certManager.clusterIssuer` names an existing ClusterIssuer
- For DNS-01, the solver secret must exist in the cert-manager namespace
- `ingress.tls.enabled` defaults to `true`; without an issuer the referenced TLS Secret is never created

**Credential change not taking effect**

- Secrets supplied via `existingSecret` are not tracked by the `checksum/secrets` annotation
- Roll the workload manually: `kubectl rollout restart deployment/guardian-llm-gateway -n guardian`

## Health Endpoints

| Endpoint       | Service     | Description                                               |
| -------------- | ----------- | --------------------------------------------------------- |
| `GET /health`  | llm-gateway | Liveness, readiness, and startup probe target             |
| `GET /metrics` | llm-gateway | Prometheus metrics on a dedicated port (default `:10001`) |

See `docs/prometheus-metrics.md` for enabling and scraping the metrics endpoint.

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://guardian.docs.eqtylab.io
- GitHub: https://github.com/eqtylab/guardian-infrastructure
