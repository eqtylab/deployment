# LLM Gateway

A Helm chart for deploying the LLM Gateway on Kubernetes.

## Description

The LLM Gateway is the signing proxy of the Agent Gateway for the Guardian Platform. Agents send model requests through it; it verifies each request's signature, applies plugins and project policy, forwards the request to the upstream model provider, and records audit events. It shares its database with the Control Plane, which manages the agent registry and plugins it reads.

Key capabilities:

- **Request Verification**: Verifies RFC 9421 message signatures from registered agents
- **Agent Registration**: Enrolls agents with registration tokens the Control Plane issues, or with Auth Service API keys
- **Plugin Runtime**: Runs signed plugins from the Control Plane's artifact storage, with store-backed or environment secrets
- **Audit Logging**: Records every request to the shared database through a local queue

## Configuration Model

The LLM Gateway uses runtime configuration injected via container arguments and environment variables. Application configuration is provided through Helm values and applied to the container at startup.

The container also receives a `LLM_GATEWAY_SERVICE_VERSION` environment variable, auto-populated from `Chart.Version`. It is reported by the health endpoint, and is not user-configurable.

This allows:

- A single immutable container image across environments
- Configuration changes without rebuilding images
- Clear separation of infrastructure and application settings
- Automatic configuration inheritance from umbrella chart globals

## Prerequisites

- Kubernetes 1.29+
- Helm 3.20+
- PostgreSQL database shared with the Control Plane (provided by the umbrella chart or external)
- The Control Plane, which issues registration tokens and publishes plugins
- Ingress controller (the examples use the HAProxy Kubernetes Ingress Controller)
- TLS certificates (manual or via cert-manager)

## Deployment

When deployed via the `guardian-platform` umbrella chart, the LLM Gateway inherits its database and credential Secrets from global values. The umbrella chart leaves it disabled; set `llm-gateway.enabled: true` to deploy it.

### Quick Start

Minimum configuration required in your umbrella chart values:

```yaml
llm-gateway:
  enabled: true
  image:
    tag: ""
  ingress:
    enabled: true
    className: "haproxy"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
    hosts:
      - host: "llmgateway.guardian.yourcompany.com"
        paths:
          - path: "/"
            pathType: "Prefix"
    tls:
      - secretName: "llm-gateway-tls"
        hosts:
          - "llmgateway.guardian.yourcompany.com"
```

### Required Configuration

Beyond what is auto-configured, these values **must** be explicitly set:

- `global.secrets.database.values.gatewayDsn` - DSN of the gateway database, when `global.secrets.create` is true
- `global.secrets.llmGateway.values.credentialSignerSeed` - Credential signer seed, when `global.secrets.create` is true and `config.registration.enabled` is true (generate with `openssl rand -hex 32`)
- `global.secrets.controlPlane.values.registrationTokenSecret` - Registration token secret, when `global.secrets.create` is true and `config.registration.enabled` is true

**What gets auto-configured:**

From global values:

- Database DSN (from `global.secrets.database`, key `gatewayDsn`)
- Registration token secret (from `global.secrets.controlPlane`)
- Credential signer seed and plugin secret environment variables (from `global.secrets.llmGateway`)
- Image pull policy (from `global.imagePullPolicy`)
- Image pull secrets (from `global.secrets.imageRegistry.secretName`, then `global.imagePullSecrets`)

## Values

### Global Parameters (Umbrella Chart)

When deployed via the umbrella chart, these global values are automatically used. The chart's own `global.secrets` defaults match the umbrella's Secret names; a Secret reference whose local and global names are both empty fails the render.

| Key                                                      | Type   | Description                                                                                         |
| -------------------------------------------------------- | ------ | --------------------------------------------------------------------------------------------------- |
| global.imagePullPolicy                                   | string | Default image pull policy for every container                                                       |
| global.imagePullSecrets                                  | list   | Image pull secrets when global.secrets.imageRegistry.secretName is empty                            |
| global.secrets.database.secretName                       | string | Name of database credentials secret (standalone default `platform-database`)                        |
| global.secrets.database.keys.gatewayDsn                  | string | Key holding the gateway DSN (defaults to `gateway-dsn`)                                             |
| global.secrets.controlPlane.secretName                   | string | Name of the Control Plane secret (standalone default `platform-control-plane`)                      |
| global.secrets.controlPlane.keys.registrationTokenSecret | string | Key holding the registration token secret (defaults to `registration-token-secret`)                 |
| global.secrets.llmGateway.secretName                     | string | Name of the LLM Gateway secret (standalone default `platform-llm-gateway`)                          |
| global.secrets.llmGateway.keys.credentialSignerSeed      | string | Key holding the credential signer seed (defaults to `credential-signer-seed`)                       |
| global.secrets.llmGateway.values.pluginSecretEnvs        | object | Plugin secret environment variables the umbrella chart writes to the LLM Gateway secret; names only |
| global.secrets.imageRegistry.secretName                  | string | Name of image pull secret                                                                           |

### Chart-Specific Parameters

| Key              | Type   | Default                         | Description                                                                                                           |
| ---------------- | ------ | ------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| enabled          | bool   | `true`                          | Enable this subchart (umbrella chart only)                                                                            |
| replicaCount     | int    | `2`                             | Number of replicas to deploy                                                                                          |
| image.repository | string | `"ghcr.io/eqtylab/llm-gateway"` | Container image repository                                                                                            |
| image.pullPolicy | string | `""`                            | Image pull policy (auto-configured from global.imagePullPolicy, defaults to `IfNotPresent`)                           |
| image.tag        | string | `""`                            | Overrides the image tag (default is chart appVersion)                                                                 |
| image.digest     | string | `""`                            | Immutable sha256 digest; takes precedence over image.tag                                                              |
| imagePullSecrets | list   | `[]`                            | Image pull secrets, used only when global.secrets.imageRegistry.secretName and global.imagePullSecrets are both empty |
| args             | list   | `[]`                            | Container arguments, appended after those the chart builds from config                                                |

### Service Account

| Key                        | Type   | Default | Description                                                                                         |
| -------------------------- | ------ | ------- | --------------------------------------------------------------------------------------------------- |
| serviceAccount.create      | bool   | `true`  | Specifies whether a service account should be created                                               |
| serviceAccount.automount   | bool   | `true`  | Automatically mount the ServiceAccount's API credentials                                            |
| serviceAccount.annotations | object | `{}`    | Annotations to add to the service account, such as a cloud IAM identity for plugin artifact storage |
| serviceAccount.name        | string | `""`    | The name of the service account (generated if serviceAccount.create is true)                        |

### Security

| Key                                      | Type   | Default | Description                          |
| ---------------------------------------- | ------ | ------- | ------------------------------------ |
| podAnnotations                           | object | `{}`    | Annotations to add to pods           |
| podLabels                                | object | `{}`    | Labels to add to pods                |
| podSecurityContext.runAsNonRoot          | bool   | `true`  | Run the pod as a non-root user       |
| securityContext.runAsNonRoot             | bool   | `true`  | Run the container as a non-root user |
| securityContext.allowPrivilegeEscalation | bool   | `false` | Prevent privilege escalation         |
| securityContext.readOnlyRootFilesystem   | bool   | `true`  | Read-only root filesystem            |
| securityContext.capabilities.drop        | list   | `[ALL]` | Drop all capabilities                |

### Service

| Key             | Type   | Default       | Description                                    |
| --------------- | ------ | ------------- | ---------------------------------------------- |
| service.enabled | bool   | `true`        | Create a Service resource                      |
| service.type    | string | `"ClusterIP"` | Kubernetes service type                        |
| service.port    | int    | `10000`       | Service port exposed by the Kubernetes Service |

### Ingress

| Key                 | Type   | Default                                                                                   | Description                 |
| ------------------- | ------ | ----------------------------------------------------------------------------------------- | --------------------------- |
| ingress.enabled     | bool   | `false`                                                                                   | Enable ingress              |
| ingress.className   | string | `""`                                                                                      | Ingress class name          |
| ingress.annotations | object | `{}`                                                                                      | Ingress annotations         |
| ingress.hosts       | list   | `[{"host":"llmgateway.guardian.example.com","paths":[{"path":"/","pathType":"Prefix"}]}]` | Ingress hosts configuration |
| ingress.tls         | list   | `[]`                                                                                      | Ingress TLS configuration   |

### Resources

| Key                                           | Type   | Default | Description                          |
| --------------------------------------------- | ------ | ------- | ------------------------------------ |
| resources                                     | object | `{}`    | CPU/Memory resource requests/limits  |
| autoscaling.enabled                           | bool   | `false` | Enable horizontal pod autoscaling    |
| autoscaling.minReplicas                       | int    | `2`     | Minimum number of replicas           |
| autoscaling.maxReplicas                       | int    | `10`    | Maximum number of replicas           |
| autoscaling.targetCPUUtilizationPercentage    | int    | `80`    | Target CPU utilization percentage    |
| autoscaling.targetMemoryUtilizationPercentage | int    | `80`    | Target memory utilization percentage |

> **Note:** Resources are empty by default. For production, set appropriate requests and limits (recommended: cpu 100m-500m, memory 256Mi-512Mi).

### High Availability

| Key                                | Type | Default | Description                                                                                                                             |
| ---------------------------------- | ---- | ------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| podDisruptionBudget.enabled        | bool | `true`  | Enable Pod Disruption Budget                                                                                                            |
| podDisruptionBudget.minAvailable   | int  | `1`     | Minimum available pods during disruptions (only rendered when replicaCount, or autoscaling.minReplicas with autoscaling on, is above 1) |
| podDisruptionBudget.maxUnavailable | int  | `1`     | Maximum unavailable pods during disruptions (only rendered otherwise)                                                                   |

Replicas share nothing in memory, and the database migrations each pod runs at startup take a Postgres advisory lock, so pods can start together.

### Node Scheduling

| Key            | Type   | Default | Description                                              |
| -------------- | ------ | ------- | -------------------------------------------------------- |
| nodeSelector   | object | `{}`    | Node labels for pod assignment                           |
| tolerations    | list   | `[]`    | Tolerations for pod assignment                           |
| hostAliases    | list   | `[]`    | Optional pod host aliases (local qualification DNS only) |
| affinity       | object | `{}`    | Affinity rules for pod assignment                        |
| initContainers | list   | `[]`    | Init containers to add to the pod                        |

### Health Checks

| Key                                | Type   | Default     | Description                   |
| ---------------------------------- | ------ | ----------- | ----------------------------- |
| startupProbe.httpGet.path          | string | `"/health"` | Startup probe HTTP path       |
| startupProbe.httpGet.port          | string | `"http"`    | Startup probe port            |
| startupProbe.failureThreshold      | int    | `180`       | Startup failure threshold     |
| startupProbe.periodSeconds         | int    | `5`         | Startup probe period          |
| livenessProbe.httpGet.path         | string | `"/health"` | Liveness probe HTTP path      |
| livenessProbe.httpGet.port         | string | `"http"`    | Liveness probe port           |
| livenessProbe.initialDelaySeconds  | int    | `5`         | Liveness probe initial delay  |
| livenessProbe.periodSeconds        | int    | `10`        | Liveness probe period         |
| readinessProbe.httpGet.path        | string | `"/health"` | Readiness probe HTTP path     |
| readinessProbe.httpGet.port        | string | `"http"`    | Readiness probe port          |
| readinessProbe.initialDelaySeconds | int    | `3`         | Readiness probe initial delay |
| readinessProbe.periodSeconds       | int    | `10`        | Readiness probe period        |

The startup probe allows up to 15 minutes for long-running index migrations before liveness checks can restart the pod.

### Database Configuration

| Key                                   | Type   | Default | Description                                                                                                   |
| ------------------------------------- | ------ | ------- | ------------------------------------------------------------------------------------------------------------- |
| externalDatabase.dsnSecretKeyRef.name | string | `""`    | Secret holding the gateway DSN (auto-configured from global.secrets.database.secretName)                      |
| externalDatabase.dsnSecretKeyRef.key  | string | `""`    | Key holding the DSN (auto-configured from global.secrets.database.keys.gatewayDsn, defaults to `gateway-dsn`) |

The LLM Gateway and the Control Plane share one database, and the LLM Gateway runs its migrations at startup. The DSN names the host, database, and credentials, so the LLM Gateway reads no `global.postgresql` settings. URL-encode credentials that contain reserved URI characters.

### Secret Configuration

All secret references support global fallbacks when deployed via umbrella chart.

#### LLM Gateway Secret

| Key                     | Type   | Description                                                                                                                                          |
| ----------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| secrets.llmGateway.name | string | Secret holding the credential signer seed, read when config.registration.enabled is true (auto-configured from global.secrets.llmGateway.secretName) |

When the umbrella chart creates the Secret, it also holds `global.secrets.llmGateway.values.pluginSecretEnvs`, each as an environment variable of the same name. Setting `secrets.llmGateway.name` skips them; use `secrets.pluginSecretEnvs.name` instead.

#### Control Plane Secret

| Key                       | Type   | Description                                                                                                                                               |
| ------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| secrets.controlPlane.name | string | Secret holding the registration token secret, read when config.registration.enabled is true (auto-configured from global.secrets.controlPlane.secretName) |

The LLM Gateway and the Control Plane must read the same registration token secret; the umbrella chart fails to render when their Secret names differ.

When the umbrella chart creates the Secrets, the pod's `checksum/platform-secrets` annotation follows the registration token, the credential signer seed, and the plugin secret environment variables it reads from them, so changing any of them rolls the LLM Gateway. Values in a Secret named by `secrets.controlPlane.name` or `secrets.llmGateway.name` are left out.

#### Plugin Secrets

| Key                           | Type   | Description                                                                                                                                  |
| ----------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| secrets.pluginSecretsKey.name | string | Secret holding the plugin secrets encryption key; use the same Secret as the Control Plane                                                   |
| secrets.pluginSecretsKey.key  | string | Key holding the encryption key (defaults to `encryption-key`)                                                                                |
| secrets.pluginSecretEnvs.name | string | Secret whose keys become plugin secret environment variables; also sets `config.plugins.secrets.resolutionOrder` to `env` when that is empty |

#### Plugin Artifact Storage Secrets

Only configure the section matching config.plugins.artifactStorage.provider:

| Key                                                       | Type   | Description                                                                          |
| --------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------ |
| secrets.pluginArtifactStorage.gcs.name                    | string | Secret holding a GCS service account JSON; empty uses the pod's Workload Identity    |
| secrets.pluginArtifactStorage.gcs.key                     | string | Key holding the service account JSON (defaults to `serviceAccountJson`)              |
| secrets.pluginArtifactStorage.s3.name                     | string | Secret holding the S3 credentials; empty uses config.plugins.artifactStorage.s3 keys |
| secrets.pluginArtifactStorage.s3.keys.accessKeyID         | string | Key holding the access key ID (defaults to `accessKeyID`)                            |
| secrets.pluginArtifactStorage.s3.keys.secretAccessKey     | string | Key holding the secret access key (defaults to `secretAccessKey`)                    |
| secrets.pluginArtifactStorage.azure.name                  | string | Secret holding an account key or a connection string                                 |
| secrets.pluginArtifactStorage.azure.keys.accountKey       | string | Key holding the account key (defaults to `accountKey`)                               |
| secrets.pluginArtifactStorage.azure.keys.connectionString | string | Key holding the connection string (defaults to `connectionString`)                   |

### Application Configuration

All config values support global fallbacks when deployed via umbrella chart.

#### Application Settings

| Key                               | Type   | Default                       | Description                                                                            |
| --------------------------------- | ------ | ----------------------------- | -------------------------------------------------------------------------------------- |
| config.listenAddr                 | string | `":10000"`                    | Listen address                                                                         |
| config.deploymentEnvironment      | string | `""`                          | Reported on audit events and used by gateway runtime policy                            |
| config.upstreams.anthropicURL     | string | `"https://api.anthropic.com"` | Anthropic upstream URL                                                                 |
| config.upstreams.openaiURL        | string | `"https://api.openai.com"`    | OpenAI upstream URL                                                                    |
| config.signature.label            | string | `"sig"`                       | RFC 9421 signature label; must match the label Viper signs with                        |
| config.signature.defaultSigMaxAge | string | `"60s"`                       | Default signature max age                                                              |
| config.signature.defaultClockSkew | string | `"120s"`                      | Default clock skew allowance                                                           |
| config.projectContext.mode        | string | `"disabled"`                  | `disabled`, `observe`, or `enforce`; requires config.plugins.enabled unless `disabled` |

#### Agent Registration Configuration

| Key                              | Type   | Default           | Description                                                                                                                   |
| -------------------------------- | ------ | ----------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| config.registration.enabled      | bool   | `false`           | Enable token registration; reads the registration token secret from secrets.controlPlane and the seed from secrets.llmGateway |
| config.registration.tokenIssuer  | string | `"control-plane"` | Must match the Control Plane's config.auth.registrationTokenIssuer                                                            |
| config.authServiceBaseURL        | string | `""`              | Auth Service URL for API-key enrollment; empty disables it                                                                    |
| config.authServiceIdentityIssuer | string | `""`              | Identity issuer stamped on agents enrolled with an API key (defaults to `{authServiceBaseURL}/api/v1/auth`)                   |

#### Audit Configuration

| Key                        | Type   | Default                           | Description                               |
| -------------------------- | ------ | --------------------------------- | ----------------------------------------- |
| config.audit.enabled       | bool   | `true`                            | Enable audit logging                      |
| config.audit.queueDir      | string | `"/var/lib/guardian/audit-queue"` | Audit queue directory, an emptyDir volume |
| config.audit.queueMaxBytes | int    | `10737418240`                     | Audit queue size limit (10 GiB)           |
| config.audit.batchSize     | int    | `100`                             | Audit batch size                          |
| config.audit.flushInterval | string | `"1s"`                            | Audit flush interval                      |
| config.audit.retentionDays | int    | `90`                              | Audit retention in days                   |

#### Plugin Configuration

| Key                                                     | Type   | Default                                       | Description                                                                                                            |
| ------------------------------------------------------- | ------ | --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| config.plugins.enabled                                  | bool   | `false`                                       | Enable the plugin runtime                                                                                              |
| config.plugins.pollInterval                             | string | `"15s"`                                       | How often to poll for plugin changes                                                                                   |
| config.plugins.authorizerShadowEnabled                  | bool   | `false`                                       | Evaluate authorizer plugins without enforcing their decisions                                                          |
| config.plugins.endQueueDir                              | string | `"/var/lib/guardian/plugin-end-queue"`        | Plugin end queue directory, an emptyDir volume                                                                         |
| config.plugins.endQueueMaxBytes                         | int    | `134217728`                                   | Plugin end queue size limit (128 MiB)                                                                                  |
| config.plugins.artifactCacheDir                         | string | `"/var/lib/guardian/plugin-artifacts"`        | Plugin artifact cache directory, an emptyDir volume                                                                    |
| config.plugins.artifactStorage.provider                 | string | `""`                                          | Storage provider (`gcs`, `s3`, `azure`, or `file`)                                                                     |
| config.plugins.artifactStorage.bucket                   | string | `""`                                          | Bucket or container; the mount path when provider is `file`                                                            |
| config.plugins.artifactStorage.prefix                   | string | `""`                                          | Object key prefix                                                                                                      |
| config.plugins.artifactStorage.gcs.endpoint             | string | `""`                                          | GCS endpoint override                                                                                                  |
| config.plugins.artifactStorage.gcs.mountPath            | string | `"/run/secrets/guardian-plugin-artifact-gcs"` | Where the service account JSON is mounted                                                                              |
| config.plugins.artifactStorage.s3.endpoint              | string | `""`                                          | S3 endpoint override                                                                                                   |
| config.plugins.artifactStorage.s3.region                | string | `""`                                          | S3 region (**must be set** when provider is `s3`)                                                                      |
| config.plugins.artifactStorage.s3.forcePathStyle        | bool   | `false`                                       | Use path-style S3 addressing                                                                                           |
| config.plugins.artifactStorage.s3.accessKeyID           | string | `""`                                          | S3 access key ID (**must be set** when provider is `s3` and secrets.pluginArtifactStorage.s3.name is empty)            |
| config.plugins.artifactStorage.s3.secretAccessKey       | string | `""`                                          | S3 secret access key (**must be set** when provider is `s3` and secrets.pluginArtifactStorage.s3.name is empty)        |
| config.plugins.artifactStorage.azure.accountName        | string | `""`                                          | Storage account name (**must be set** with an account key or managed identity)                                         |
| config.plugins.artifactStorage.azure.endpoint           | string | `""`                                          | Blob service endpoint override; not with connectionString                                                              |
| config.plugins.artifactStorage.azure.useManagedIdentity | bool   | `false`                                       | Authenticate with the pod's managed identity                                                                           |
| config.plugins.artifactStorage.azure.accountKey         | string | `""`                                          | Account key                                                                                                            |
| config.plugins.artifactStorage.azure.connectionString   | string | `""`                                          | Connection string                                                                                                      |
| config.plugins.artifactStorage.file.existingClaim       | string | `""`                                          | ReadWriteMany PVC shared with the Control Plane, mounted read-only at bucket (**must be set** when provider is `file`) |
| config.plugins.trustedSignerKeys                        | object | `{}`                                          | Map of signer key ID to did:key public key; match the Control Plane's                                                  |
| config.plugins.secrets.resolutionOrder                  | list   | `[]`                                          | Where plugin secrets resolve from (`store`, `env`); `["env"]` when plugin secret environment variables are set         |

Azure takes exactly one of `accountKey`, `connectionString`, `useManagedIdentity`, or `secrets.pluginArtifactStorage.azure.name`.

The Control Plane writes plugin artifacts and the LLM Gateway reads them, so point both at the same storage with read access for the LLM Gateway.

### Advanced: Extra Configuration

| Key          | Type | Default | Description                                                                   |
| ------------ | ---- | ------- | ----------------------------------------------------------------------------- |
| extraEnvVars | list | `[]`    | Extra environment variables, such as the `OTEL_*` variables the gateway reads |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level config values** - Explicitly set in `llm-gateway.config.*`
2. **Global values** - Set in `global.*` (umbrella chart)
3. **Chart defaults** - Default values from `values.yaml`

## Google Cloud Storage Configuration

### Required GCS Setup

1. **Use the Control Plane's GCS bucket** for plugin artifacts
2. **Grant read access** to the bucket: bind a Google service account to `serviceAccount.annotations` through Workload Identity, or export a JSON key

### Example Configuration

```yaml
llm-gateway:
  serviceAccount:
    annotations:
      iam.gke.io/gcp-service-account: "guardian-plugins-reader@your-project.iam.gserviceaccount.com"
  config:
    plugins:
      enabled: true
      artifactStorage:
        provider: "gcs"
        bucket: "your-plugin-artifact-bucket"
        prefix: "guardian-plugins"
```

### Secret Creation

Only without Workload Identity; set `secrets.pluginArtifactStorage.gcs.name` to the Secret:

```bash
kubectl create secret generic llm-gateway-gcs \
  --from-file=serviceAccountJson=YOUR_SERVICE_ACCOUNT_KEY.json \
  --namespace guardian
```

## AWS S3 Configuration

### Required AWS Setup

1. **Use the Control Plane's S3 bucket** for plugin artifacts, or a bucket on an S3-compatible store
2. **Create an IAM user** with read access to the bucket and generate access keys

### Example Configuration

```yaml
llm-gateway:
  config:
    plugins:
      enabled: true
      artifactStorage:
        provider: "s3"
        bucket: "your-plugin-artifact-bucket"
        prefix: "guardian-plugins"
        s3:
          region: "us-east-1"
  secrets:
    pluginArtifactStorage:
      s3:
        name: "llm-gateway-s3"
```

### Secret Creation

```bash
kubectl create secret generic llm-gateway-s3 \
  --from-literal=accessKeyID=YOUR_ACCESS_KEY_ID \
  --from-literal=secretAccessKey=YOUR_SECRET_ACCESS_KEY \
  --namespace guardian
```

## Azure Blob Storage Configuration

### Required Azure Setup

1. **Use the Control Plane's Azure Blob container** for plugin artifacts
2. **Choose an identity**: a managed identity with read access to the container, or the account key or connection string

### Example Configuration

```yaml
llm-gateway:
  config:
    plugins:
      enabled: true
      artifactStorage:
        provider: "azure"
        bucket: "your-plugin-artifact-container"
        prefix: "guardian-plugins"
        azure:
          accountName: "your-storage-account"
  secrets:
    pluginArtifactStorage:
      azure:
        name: "llm-gateway-azure"
```

### Secret Creation

```bash
kubectl create secret generic llm-gateway-azure \
  --from-literal=accountKey=YOUR_AZURE_STORAGE_ACCOUNT_KEY \
  --namespace guardian
```

## Shared Volume Configuration

### Required Setup

1. **Use the Control Plane's ReadWriteMany PersistentVolumeClaim**; the LLM Gateway mounts it read-only

### Example Configuration

```yaml
llm-gateway:
  config:
    plugins:
      enabled: true
      artifactStorage:
        provider: "file"
        bucket: "/var/lib/guardian/plugin-store"
        file:
          existingClaim: "guardian-plugin-store"
```

## Agent Registration and Plugin Secrets Configuration

Token registration needs the Control Plane's registration token secret and an Ed25519 credential signer seed, from which the LLM Gateway issues registration and renewal credentials. With `global.secrets.create`, set `global.secrets.llmGateway.values.credentialSignerSeed`; otherwise create the Secret yourself:

```bash
kubectl create secret generic platform-llm-gateway \
  --from-literal=credential-signer-seed="$(openssl rand -hex 32)" \
  --namespace guardian
```

Plugin secrets resolve from the Control Plane's encrypted store, from environment variables, or both, in `config.plugins.secrets.resolutionOrder` order. The store uses the Control Plane's plugin secrets key:

```yaml
llm-gateway:
  config:
    plugins:
      enabled: true
      secrets:
        resolutionOrder: ["store", "env"]
  secrets:
    pluginSecretsKey:
      name: "guardian-plugin-secrets-key"
```

Environment variables come from `global.secrets.llmGateway.values.pluginSecretEnvs`, or from a Secret named by `secrets.pluginSecretEnvs.name`, for example `GUARDIAN_SECRET__BUILTIN__INTENT_MONITOR__OPENAI_API_KEY`.

## Operations Guides

- [Plugin runtime bootstrap](docs/plugin-runtime-bootstrap.md): signed baseline configuration, rollout, and signer rotation
- [Prometheus metrics](docs/prometheus-metrics.md): the metrics port and scraping it
- [Splunk HEC log forwarding](docs/splunk-hec-log-forwarding.md): OTLP log export through an OpenTelemetry Collector

## Upgrading from gateway-stack

Earlier releases ran the LLM Gateway in the `gateway-stack` chart, which this chart replaces. Its values moved from `gateway-stack.*` to `llm-gateway.*`, and the resource names and selector labels changed, so Helm replaces the Deployment on upgrade. The umbrella chart fails to render while a `gateway-stack` key remains.

| gateway-stack                                                                                                                                                                                    | llm-gateway                                                                                                                                               |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `llmGateway.{replicaCount,image,serviceAccount,podAnnotations,podLabels,podSecurityContext,securityContext,service,resources,autoscaling,podDisruptionBudget,nodeSelector,tolerations,affinity}` | The same keys at the top level                                                                                                                            |
| `llmGateway.probes.*`                                                                                                                                                                            | `startupProbe`, `livenessProbe`, `readinessProbe`                                                                                                         |
| `llmGateway.{listenAddr,deploymentEnvironment,upstreams,signature,authServiceBaseURL,authServiceIdentityIssuer,audit,projectContext}`                                                            | `config.*`                                                                                                                                                |
| `llmGateway.registration.{enabled,tokenIssuer}`                                                                                                                                                  | `config.registration.{enabled,tokenIssuer}`                                                                                                               |
| `llmGateway.registration.credentialSigner.seed`                                                                                                                                                  | `global.secrets.llmGateway.values.credentialSignerSeed` (the umbrella creates `platform-llm-gateway`)                                                     |
| `llmGateway.registration.credentialSigner.existingSecret`                                                                                                                                        | `secrets.llmGateway.name` when `global.secrets.create` is true, so the umbrella chart doesn't create it; otherwise `global.secrets.llmGateway.secretName` |
| `llmGateway.registration.credentialSigner.secretKey`                                                                                                                                             | `global.secrets.llmGateway.keys.credentialSignerSeed`                                                                                                     |
| `llmGateway.plugins.{enabled,pollInterval,authorizerShadowEnabled,endQueueDir,endQueueMaxBytes,artifactCacheDir,artifactStorage,trustedSignerKeys}`                                              | `config.plugins.*`                                                                                                                                        |
| `llmGateway.plugins.secrets.resolutionOrder`                                                                                                                                                     | `config.plugins.secrets.resolutionOrder`                                                                                                                  |
| `llmGateway.plugins.secrets.encryptionKey.{existingSecret,secretKey}`                                                                                                                            | `secrets.pluginSecretsKey.{name,key}`                                                                                                                     |
| `llmGateway.plugins.secretEnvs`                                                                                                                                                                  | `global.secrets.llmGateway.values.pluginSecretEnvs`                                                                                                       |
| `llmGateway.plugins.secretEnvsSecret.name`                                                                                                                                                       | `secrets.pluginSecretEnvs.name`                                                                                                                           |
| `llmGateway.plugins.artifactStorage.<provider>.{existingSecret,secretKey,secretKeys}`                                                                                                            | `secrets.pluginArtifactStorage.<provider>.{name,key,keys}`                                                                                                |
| `llmGateway.extraArgs`                                                                                                                                                                           | `args`                                                                                                                                                    |
| `llmGateway.extraEnv`                                                                                                                                                                            | `extraEnvVars`                                                                                                                                            |
| `database.{existingSecret,secretKeys.dsn}`                                                                                                                                                       | `externalDatabase.dsnSecretKeyRef.{name,key}`                                                                                                             |
| `database.{host,port,sslMode,user,password,name}`                                                                                                                                                | Removed; supply the DSN in a Secret                                                                                                                       |
| `postgresql.*`                                                                                                                                                                                   | Removed; use the umbrella chart's PostgreSQL, which creates `guardian_gateway`, or an external database                                                   |
| `ingress.{enabled,className,annotations}`                                                                                                                                                        | `ingress.{enabled,className,annotations}`                                                                                                                 |
| `ingress.{hosts.llmGateway,llmGatewayAnnotations,tls}`                                                                                                                                           | `ingress.{hosts,annotations,tls}`                                                                                                                         |
| `ingress.certManager.{enabled,clusterIssuer}`                                                                                                                                                    | A `cert-manager.io/cluster-issuer` annotation in `ingress.annotations`                                                                                    |
| `ingress.certManager.{createClusterIssuer,acme}`                                                                                                                                                 | Removed; create the ClusterIssuer outside the chart                                                                                                       |
| `haproxyIngress.*`                                                                                                                                                                               | `haproxyIngress.*` in the umbrella chart                                                                                                                  |

When upgrading:

- Set `llm-gateway.enabled: true`. The umbrella chart leaves the LLM Gateway off by default, so moving the keys alone removes it
- The ServiceAccount is now `{Release.Name}-llm-gateway`. Move any Workload Identity binding to it before upgrading
- The Service is now `{Release.Name}-llm-gateway`. Update anything that calls the old `{Release.Name}-gateway-stack-llm-gateway` Service
- The credential signer seed's key is now `credential-signer-seed`. To keep an existing Secret, set `global.secrets.llmGateway.keys.credentialSignerSeed: seed`
- `ingress.tls` is empty by default. Set `ingress.tls`, and a `cert-manager.io/cluster-issuer` or `cert-manager.io/issuer` annotation, to keep HTTPS
- The default is 2 replicas with a Pod Disruption Budget; set `replicaCount: 1` to keep one

## Troubleshooting

### Viewing Logs

```bash
kubectl logs -f deployment/llm-gateway -n guardian
```

### Checking Pod Status

```bash
kubectl get pods -n guardian -l app.kubernetes.io/name=llm-gateway
kubectl describe pod <pod-name> -n guardian
```

### Verifying Configuration

View the container arguments in the running pod:

```bash
kubectl get deployment/llm-gateway -n guardian -o jsonpath='{.spec.template.spec.containers[0].args}'
```

Test health endpoint:

```bash
kubectl exec -it deployment/llm-gateway -n guardian -- curl -s localhost:10000/health
```

### Common Issues

**Application not accessible**

- Verify ingress is enabled and configured correctly
- Check DNS points to your ingress controller
- Verify TLS certificates are valid
- Model streams can pause for minutes; raise the ingress controller's server timeout, for example `haproxy.org/timeout-server: "600s"`

**Pod not becoming ready**

- The startup probe waits while migrations run; check the logs for migration progress
- Verify the DSN in the database Secret reaches the intended host and database

**Agent registration rejected**

- Verify the LLM Gateway and the Control Plane read the same registration token secret
- Confirm `config.registration.tokenIssuer` matches the Control Plane's `config.auth.registrationTokenIssuer`
- Confirm the credential signer seed is set

**Plugins not loading**

- Verify `config.plugins.artifactStorage` and `config.plugins.trustedSignerKeys` match the Control Plane's
- For GCS with Workload Identity, confirm `serviceAccount.annotations` binds an identity with read access to the bucket
- Confirm `secrets.pluginSecretsKey` names the Control Plane's Secret when plugin secrets come from the store

**Configuration not applying**

- Remember: service-level config overrides global config
- Check for typos in global value paths
- Restart pods if a Secret was updated: `kubectl rollout restart deployment/llm-gateway -n guardian`

## Health Endpoints

| Endpoint      | Description                                   |
| ------------- | --------------------------------------------- |
| `GET /health` | Liveness, readiness, and startup probe target |

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://guardian.docs.eqtylab.io
- GitHub: https://github.com/eqtylab/guardian-infrastructure
