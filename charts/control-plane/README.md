# Control Plane

A Helm chart for deploying the Control Plane on Kubernetes.

## Description

The Control Plane is the management API of the Agent Gateway for the Guardian Platform. Guardian and the CLI onboarding flows call it, and the LLM Gateway reads the agent registry and plugin configuration it writes.

Key capabilities:

- **Agent Registration**: Issues the registration tokens the LLM Gateway verifies when agents enroll
- **Plugin Publishing**: Signs and stores plugin artifacts and project configuration manifests
- **Guardian Adapter**: Resolves platform identity, projects, and integrity status from the Auth, Governance, and Integrity Services
- **VirusTotal Scanning**: Optional scanning of the blobs callers look up through `/v1/vt-scans`

## Configuration Model

The Control Plane uses runtime configuration injected via container arguments and environment variables. Application configuration is provided through Helm values and applied to the container at startup.

The container also receives a `CONTROL_PLANE_SERVICE_VERSION` environment variable, auto-populated from `Chart.Version`. It is reported by the health endpoint, and is not user-configurable.

This allows:

- A single immutable container image across environments
- Configuration changes without rebuilding images
- Clear separation of infrastructure and application settings
- Automatic configuration inheritance from umbrella chart globals

## Prerequisites

- Kubernetes 1.29+
- Helm 3.20+
- PostgreSQL database shared with the LLM Gateway (provided by the umbrella chart or external)
- The LLM Gateway, whose migrations create the registry views the Control Plane waits for
- Object storage (GCS, S3-compatible, Azure Blob, or a ReadWriteMany volume) for plugin artifacts
- Ingress controller (the examples use the HAProxy Kubernetes Ingress Controller)
- TLS certificates (manual or via cert-manager)

## Deployment

When deployed via the `guardian-platform` umbrella chart, the Control Plane inherits its database and credential Secrets from global values. The umbrella chart leaves it disabled; set `control-plane.enabled: true` to deploy it.

### Quick Start

Minimum configuration required in your umbrella chart values:

```yaml
control-plane:
  enabled: true
  image:
    tag: ""
  ingress:
    enabled: true
    className: "haproxy"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
    hosts:
      - host: "cp.guardian.yourcompany.com"
        paths:
          - path: "/"
            pathType: "Prefix"
    tls:
      - secretName: "control-plane-tls"
        hosts:
          - "cp.guardian.yourcompany.com"
  config:
    plugins:
      artifactStorage:
        provider: "gcs"
        bucket: "your-plugin-artifact-bucket"
        prefix: "guardian-plugins"
```

### Required Configuration

Beyond what is auto-configured, these values **must** be explicitly set:

- `config.plugins.artifactStorage.provider` and `config.plugins.artifactStorage.bucket` - Where plugin artifacts are stored
- `global.secrets.controlPlane.values.registrationTokenSecret` - Registration token secret, when `global.secrets.create` is true and `config.auth.enabled` is true (generate with `openssl rand -base64 32`)
- `global.secrets.database.values.gatewayDsn` - DSN of the gateway database, when `global.secrets.create` is true

**What gets auto-configured:**

From global values:

- Database DSN (from `global.secrets.database`, key `gatewayDsn`)
- Registration token secret (from `global.secrets.controlPlane`)
- Image pull policy (from `global.imagePullPolicy`)
- Image pull secrets (from `global.secrets.imageRegistry.secretName`, then `global.imagePullSecrets`)

Generated defaults:

- Auth Service URL defaults to `http://{Release.Name}-auth-service:8080`
- Governance Service URL defaults to `http://{Release.Name}-governance-service:10001`
- Integrity Service URL defaults to `http://{Release.Name}-integrity-service:3050`

## Values

### Global Parameters (Umbrella Chart)

When deployed via the umbrella chart, these global values are automatically used. The chart's own `global.secrets` defaults match the umbrella's Secret names; a Secret reference whose local and global names are both empty fails the render.

| Key                                                      | Type   | Description                                                                                                   |
| -------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------- |
| global.imagePullPolicy                                   | string | Default image pull policy for every container                                                                 |
| global.imagePullSecrets                                  | list   | Image pull secrets when global.secrets.imageRegistry.secretName is empty                                      |
| global.utilityImages.postgres                            | string | Complete image reference for the registry view wait container (empty keeps `docker.io/library/postgres:17.6`) |
| global.secrets.database.secretName                       | string | Name of database credentials secret (standalone default `platform-database`)                                  |
| global.secrets.database.keys.gatewayDsn                  | string | Key holding the gateway DSN (defaults to `gateway-dsn`)                                                       |
| global.secrets.controlPlane.secretName                   | string | Name of the Control Plane secret (standalone default `platform-control-plane`)                                |
| global.secrets.controlPlane.keys.registrationTokenSecret | string | Key holding the registration token secret (defaults to `registration-token-secret`)                           |
| global.secrets.imageRegistry.secretName                  | string | Name of image pull secret                                                                                     |

### Chart-Specific Parameters

| Key              | Type   | Default                                    | Description                                                                                                           |
| ---------------- | ------ | ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| enabled          | bool   | `true`                                     | Enable this subchart (umbrella chart only)                                                                            |
| replicaCount     | int    | `1`                                        | Number of replicas to deploy                                                                                          |
| image.repository | string | `"ghcr.io/eqtylab/guardian-control-plane"` | Container image repository                                                                                            |
| image.pullPolicy | string | `""`                                       | Image pull policy (auto-configured from global.imagePullPolicy, defaults to `IfNotPresent`)                           |
| image.tag        | string | `""`                                       | Overrides the image tag (default is chart appVersion)                                                                 |
| image.digest     | string | `""`                                       | Immutable sha256 digest; takes precedence over image.tag                                                              |
| imagePullSecrets | list   | `[]`                                       | Image pull secrets, used only when global.secrets.imageRegistry.secretName and global.imagePullSecrets are both empty |
| args             | list   | `[]`                                       | Container arguments, appended after those the chart builds from config                                                |

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
| service.port    | int    | `10010`       | Service port exposed by the Kubernetes Service |

### Ingress

| Key                 | Type   | Default                                                                           | Description                 |
| ------------------- | ------ | --------------------------------------------------------------------------------- | --------------------------- |
| ingress.enabled     | bool   | `false`                                                                           | Enable ingress              |
| ingress.className   | string | `""`                                                                              | Ingress class name          |
| ingress.annotations | object | `{}`                                                                              | Ingress annotations         |
| ingress.hosts       | list   | `[{"host":"cp.guardian.example.com","paths":[{"path":"/","pathType":"Prefix"}]}]` | Ingress hosts configuration |
| ingress.tls         | list   | `[]`                                                                              | Ingress TLS configuration   |

### Resources

| Key                                           | Type   | Default | Description                          |
| --------------------------------------------- | ------ | ------- | ------------------------------------ |
| resources                                     | object | `{}`    | CPU/Memory resource requests/limits  |
| autoscaling.enabled                           | bool   | `false` | Enable horizontal pod autoscaling    |
| autoscaling.minReplicas                       | int    | `1`     | Minimum number of replicas           |
| autoscaling.maxReplicas                       | int    | `10`    | Maximum number of replicas           |
| autoscaling.targetCPUUtilizationPercentage    | int    | `80`    | Target CPU utilization percentage    |
| autoscaling.targetMemoryUtilizationPercentage | int    | `80`    | Target memory utilization percentage |

> **Note:** Resources are empty by default. For production, set appropriate requests and limits (recommended: cpu 100m-500m, memory 256Mi-512Mi).

### High Availability

| Key                                | Type | Default | Description                                                                                                                             |
| ---------------------------------- | ---- | ------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| podDisruptionBudget.enabled        | bool | `false` | Enable Pod Disruption Budget                                                                                                            |
| podDisruptionBudget.minAvailable   | int  | `1`     | Minimum available pods during disruptions (only rendered when replicaCount, or autoscaling.minReplicas with autoscaling on, is above 1) |
| podDisruptionBudget.maxUnavailable | int  | `1`     | Maximum unavailable pods during disruptions (only rendered otherwise)                                                                   |

### Node Scheduling

| Key            | Type   | Default | Description                                              |
| -------------- | ------ | ------- | -------------------------------------------------------- |
| nodeSelector   | object | `{}`    | Node labels for pod assignment                           |
| tolerations    | list   | `[]`    | Tolerations for pod assignment                           |
| hostAliases    | list   | `[]`    | Optional pod host aliases (local qualification DNS only) |
| affinity       | object | `{}`    | Affinity rules for pod assignment                        |
| initContainers | list   | `[]`    | Init containers to add to the pod                        |

### Dependency Wait

The `wait-registry-views` init container waits for the registry views the LLM
Gateway's migrations create.

| Key                                    | Type | Default | Description                                                                 |
| -------------------------------------- | ---- | ------- | --------------------------------------------------------------------------- |
| waitDeps.registryViews.enabled         | bool | `true`  | Wait for the registry views; set false when the LLM Gateway is not deployed |
| waitDeps.registryViews.intervalSeconds | int  | `2`     | Seconds between checks                                                      |

### Health Checks

| Key                                | Type   | Default     | Description                                                         |
| ---------------------------------- | ------ | ----------- | ------------------------------------------------------------------- |
| startupProbe.httpGet.path          | string | `"/health"` | Startup probe HTTP path (prefix with config.apiBasePath when set)   |
| startupProbe.httpGet.port          | string | `"http"`    | Startup probe port                                                  |
| startupProbe.failureThreshold      | int    | `180`       | Startup failure threshold                                           |
| startupProbe.periodSeconds         | int    | `5`         | Startup probe period                                                |
| livenessProbe.httpGet.path         | string | `"/health"` | Liveness probe HTTP path (prefix with config.apiBasePath when set)  |
| livenessProbe.httpGet.port         | string | `"http"`    | Liveness probe port                                                 |
| livenessProbe.initialDelaySeconds  | int    | `5`         | Liveness probe initial delay                                        |
| livenessProbe.periodSeconds        | int    | `10`        | Liveness probe period                                               |
| readinessProbe.httpGet.path        | string | `"/health"` | Readiness probe HTTP path (prefix with config.apiBasePath when set) |
| readinessProbe.httpGet.port        | string | `"http"`    | Readiness probe port                                                |
| readinessProbe.initialDelaySeconds | int    | `3`         | Readiness probe initial delay                                       |
| readinessProbe.periodSeconds       | int    | `10`        | Readiness probe period                                              |

### Database Configuration

| Key                                   | Type   | Default | Description                                                                                                   |
| ------------------------------------- | ------ | ------- | ------------------------------------------------------------------------------------------------------------- |
| externalDatabase.dsnSecretKeyRef.name | string | `""`    | Secret holding the gateway DSN (auto-configured from global.secrets.database.secretName)                      |
| externalDatabase.dsnSecretKeyRef.key  | string | `""`    | Key holding the DSN (auto-configured from global.secrets.database.keys.gatewayDsn, defaults to `gateway-dsn`) |

The Control Plane and the LLM Gateway share one database. The DSN names the host, database, and credentials, so the Control Plane reads no `global.postgresql` settings. URL-encode credentials that contain reserved URI characters.

### Secret Configuration

All secret references support global fallbacks when deployed via umbrella chart.

#### Control Plane Secret

| Key                       | Type   | Description                                                                                                                                       |
| ------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| secrets.controlPlane.name | string | Secret holding the registration token secret, read when config.auth.enabled is true (auto-configured from global.secrets.controlPlane.secretName) |

With LLM Gateway registration on, leave `secrets.controlPlane.name` empty and set `global.secrets.controlPlane.secretName`, so both read the same Secret; the umbrella chart fails to render otherwise.

When the umbrella chart creates the Secret, the pod's `checksum/registration-token` annotation follows `global.secrets.controlPlane.values.registrationTokenSecret`, so changing the token rolls the Control Plane. The LLM Gateway's `checksum/secrets` covers the same value.

#### VirusTotal Secret

Only used when config.virusTotal.enabled is true:

| Key                     | Type   | Description                                                                                                     |
| ----------------------- | ------ | --------------------------------------------------------------------------------------------------------------- |
| secrets.virusTotal.name | string | Secret holding the VirusTotal API key (**must be set**, unless config.extraEnv sets `CONTROL_PLANE_VT_API_KEY`) |
| secrets.virusTotal.key  | string | Key holding the API key (defaults to `api-key`)                                                                 |

#### Plugin Secrets

| Key                                | Type   | Description                                                                                                                                             |
| ---------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| secrets.pluginPublisherSigner.name | string | Secret holding the encoded Ed25519 seed that signs plugin artifacts and project configuration manifests (requires config.plugins.publisherSigner.keyID) |
| secrets.pluginPublisherSigner.key  | string | Key holding the seed (defaults to `seed`)                                                                                                               |
| secrets.pluginSecretsKey.name      | string | Secret holding the plugin secrets encryption key; use the same Secret for the LLM Gateway                                                               |
| secrets.pluginSecretsKey.key       | string | Key holding the encryption key (defaults to `encryption-key`)                                                                                           |

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

| Key                 | Type   | Default    | Description                                                                    |
| ------------------- | ------ | ---------- | ------------------------------------------------------------------------------ |
| config.listenAddr   | string | `":10010"` | Listen address                                                                 |
| config.apiBasePath  | string | `""`       | Serve the API under this prefix; set the ingress path and probe paths to match |
| config.corsAllowAll | bool   | `true`     | Allow all CORS origins                                                         |

#### Authentication Configuration

| Key                                   | Type   | Default                        | Description                                                                                                                |
| ------------------------------------- | ------ | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| config.auth.enabled                   | bool   | `false`                        | Enable authentication; reads the registration token secret from secrets.controlPlane                                       |
| config.auth.registrationTokenIssuer   | string | `"control-plane"`              | Registration token issuer                                                                                                  |
| config.auth.allowedEmailDomains       | list   | `[]`                           | Restrict bearer tokens to these email domains                                                                              |
| config.auth.bearer.enabled            | bool   | `false`                        | Enable bearer token verification (must match config.auth.enabled)                                                          |
| config.auth.bearer.mode               | string | `""`                           | `oidc` verifies tokens against issuerURL and clientID; `auth_service` asks the Auth Service (treated as `oidc` when empty) |
| config.auth.bearer.issuerURL          | string | `""`                           | OIDC issuer URL                                                                                                            |
| config.auth.bearer.clientID           | string | `""`                           | OIDC client ID                                                                                                             |
| config.auth.bearer.authServiceBaseURL | string | `""`                           | Auth Service URL for `auth_service` mode (falls back to config.adapter.authServiceBaseURL)                                 |
| config.auth.bearer.scopes             | list   | `["openid","profile","email"]` | Bearer scopes                                                                                                              |

#### Guardian Adapter Configuration

| Key                                             | Type   | Default | Description                                                                               |
| ----------------------------------------------- | ------ | ------- | ----------------------------------------------------------------------------------------- |
| config.adapter.enabled                          | bool   | `false` | Enable the Guardian adapter (set to true by the umbrella chart)                           |
| config.adapter.authServiceBaseURL               | string | `""`    | Auth Service URL (auto-generated as http://{Release.Name}-auth-service:8080)              |
| config.adapter.governanceServiceBaseURL         | string | `""`    | Governance Service URL (auto-generated as http://{Release.Name}-governance-service:10001) |
| config.adapter.httpTimeout                      | string | `"5s"`  | Adapter HTTP timeout                                                                      |
| config.adapter.projectRuntimeReadTimeout        | string | `"30s"` | Project runtime read timeout                                                              |
| config.adapter.integrityBaseURL                 | string | `""`    | Integrity Service URL (auto-generated as http://{Release.Name}-integrity-service:3050)    |
| config.adapter.integrityHTTPTimeout             | string | `"5s"`  | Integrity Service HTTP timeout                                                            |
| config.adapter.integrityStatusCacheTTL          | string | `"5m"`  | Integrity status cache TTL                                                                |
| config.adapter.trustedMembershipIssuerDIDs      | list   | `[]`    | Trusted membership credential issuer DIDs                                                 |
| config.adapter.trustedComplianceIssuerDIDs      | list   | `[]`    | Trusted compliance credential issuer DIDs                                                 |
| config.adapter.allowEmbeddedCredentialBootstrap | bool   | `false` | Allow embedded credential bootstrap                                                       |

#### VirusTotal Configuration

| Key                       | Type | Default | Description                                                           |
| ------------------------- | ---- | ------- | --------------------------------------------------------------------- |
| config.virusTotal.enabled | bool | `false` | Enable VirusTotal scanning; reads the API key from secrets.virusTotal |

#### Plugin Configuration

| Key                                                     | Type   | Default                                       | Description                                                                                                     |
| ------------------------------------------------------- | ------ | --------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| config.plugins.publisherSigner.keyID                    | string | `""`                                          | Signer key ID (**must be set** when secrets.pluginPublisherSigner.name is set)                                  |
| config.plugins.publisherSigner.mountPath                | string | `"/run/secrets/guardian-plugin-publisher"`    | Where the signer seed is mounted                                                                                |
| config.plugins.artifactStorage.provider                 | string | `""`                                          | Storage provider (`gcs`, `s3`, `azure`, or `file`)                                                              |
| config.plugins.artifactStorage.bucket                   | string | `""`                                          | Bucket or container; the mount path when provider is `file`                                                     |
| config.plugins.artifactStorage.prefix                   | string | `""`                                          | Object key prefix                                                                                               |
| config.plugins.artifactStorage.maxUploadBytes           | int    | `536870912`                                   | Maximum plugin upload size (512 MiB)                                                                            |
| config.plugins.artifactStorage.gcs.endpoint             | string | `""`                                          | GCS endpoint override                                                                                           |
| config.plugins.artifactStorage.gcs.kmsKeyName           | string | `""`                                          | GCS KMS key name                                                                                                |
| config.plugins.artifactStorage.gcs.mountPath            | string | `"/run/secrets/guardian-plugin-artifact-gcs"` | Where the service account JSON is mounted                                                                       |
| config.plugins.artifactStorage.s3.endpoint              | string | `""`                                          | S3 endpoint override                                                                                            |
| config.plugins.artifactStorage.s3.region                | string | `""`                                          | S3 region (**must be set** when provider is `s3`)                                                               |
| config.plugins.artifactStorage.s3.forcePathStyle        | bool   | `false`                                       | Use path-style S3 addressing                                                                                    |
| config.plugins.artifactStorage.s3.accessKeyID           | string | `""`                                          | S3 access key ID (**must be set** when provider is `s3` and secrets.pluginArtifactStorage.s3.name is empty)     |
| config.plugins.artifactStorage.s3.secretAccessKey       | string | `""`                                          | S3 secret access key (**must be set** when provider is `s3` and secrets.pluginArtifactStorage.s3.name is empty) |
| config.plugins.artifactStorage.azure.accountName        | string | `""`                                          | Storage account name (**must be set** with an account key or managed identity)                                  |
| config.plugins.artifactStorage.azure.endpoint           | string | `""`                                          | Blob service endpoint override; not with connectionString                                                       |
| config.plugins.artifactStorage.azure.useManagedIdentity | bool   | `false`                                       | Authenticate with the pod's managed identity                                                                    |
| config.plugins.artifactStorage.azure.accountKey         | string | `""`                                          | Account key                                                                                                     |
| config.plugins.artifactStorage.azure.connectionString   | string | `""`                                          | Connection string                                                                                               |
| config.plugins.artifactStorage.file.existingClaim       | string | `""`                                          | ReadWriteMany PVC shared with the LLM Gateway, mounted at bucket (**must be set** when provider is `file`)      |
| config.plugins.trustedSignerKeys                        | object | `{}`                                          | Map of signer key ID to did:key public key                                                                      |

Azure takes exactly one of `accountKey`, `connectionString`, `useManagedIdentity`, or `secrets.pluginArtifactStorage.azure.name`.

The Control Plane writes plugin artifacts and the LLM Gateway reads them, so point both at the same storage.

### Advanced: Extra Configuration

| Key          | Type | Default | Description                 |
| ------------ | ---- | ------- | --------------------------- |
| extraEnvVars | list | `[]`    | Extra environment variables |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level config values** - Explicitly set in `control-plane.config.*`
2. **Global values** - Set in `global.*` (umbrella chart)
3. **Chart defaults** - Default values from `values.yaml`

## Google Cloud Storage Configuration

### Required GCS Setup

1. **Create a GCS Bucket** for plugin artifacts (e.g., `guardian-plugins`)
2. **Grant write access** to the bucket: bind a Google service account to `serviceAccount.annotations` through Workload Identity, or export a JSON key

### Example Configuration

```yaml
control-plane:
  serviceAccount:
    annotations:
      iam.gke.io/gcp-service-account: "guardian-plugins@your-project.iam.gserviceaccount.com"
  config:
    plugins:
      artifactStorage:
        provider: "gcs"
        bucket: "your-plugin-artifact-bucket"
        prefix: "guardian-plugins"
```

### Secret Creation

Only without Workload Identity; set `secrets.pluginArtifactStorage.gcs.name` to the Secret:

```bash
kubectl create secret generic control-plane-gcs \
  --from-file=serviceAccountJson=YOUR_SERVICE_ACCOUNT_KEY.json \
  --namespace guardian
```

## AWS S3 Configuration

### Required AWS Setup

1. **Create an S3 Bucket** for plugin artifacts (e.g., `guardian-plugins`), or a bucket on an S3-compatible store
2. **Create an IAM user** with read and write access to the bucket and generate access keys

### Example Configuration

```yaml
control-plane:
  config:
    plugins:
      artifactStorage:
        provider: "s3"
        bucket: "your-plugin-artifact-bucket"
        prefix: "guardian-plugins"
        s3:
          region: "us-east-1"
  secrets:
    pluginArtifactStorage:
      s3:
        name: "control-plane-s3"
```

### Secret Creation

```bash
kubectl create secret generic control-plane-s3 \
  --from-literal=accessKeyID=YOUR_ACCESS_KEY_ID \
  --from-literal=secretAccessKey=YOUR_SECRET_ACCESS_KEY \
  --namespace guardian
```

## Azure Blob Storage Configuration

### Required Azure Setup

1. **Create an Azure Storage Account** and a **Blob Container** for plugin artifacts (e.g., `guardian-plugins`)
2. **Choose an identity**: a managed identity with access to the container, or the account key or connection string

### Example Configuration

```yaml
control-plane:
  config:
    plugins:
      artifactStorage:
        provider: "azure"
        bucket: "your-plugin-artifact-container"
        prefix: "guardian-plugins"
        azure:
          accountName: "your-storage-account"
  secrets:
    pluginArtifactStorage:
      azure:
        name: "control-plane-azure"
```

### Secret Creation

```bash
kubectl create secret generic control-plane-azure \
  --from-literal=accountKey=YOUR_AZURE_STORAGE_ACCOUNT_KEY \
  --namespace guardian
```

## Shared Volume Configuration

### Required Setup

1. **Create a ReadWriteMany PersistentVolumeClaim** that the Control Plane and the LLM Gateway both mount

### Example Configuration

```yaml
control-plane:
  config:
    plugins:
      artifactStorage:
        provider: "file"
        bucket: "/var/lib/guardian/plugin-store"
        file:
          existingClaim: "guardian-plugin-store"
```

## Plugin Signing and Secrets Configuration

The publisher signer seed signs plugin artifacts and project configuration manifests; keep its public key in `config.plugins.trustedSignerKeys` and in the LLM Gateway's trusted keys. The plugin secrets key encrypts store-backed plugin secrets; use the same Secret for the LLM Gateway.

```bash
kubectl create secret generic guardian-plugin-publisher-signer \
  --from-literal=seed="$(openssl rand -hex 32)" \
  --namespace guardian
kubectl create secret generic guardian-plugin-secrets-key \
  --from-literal=encryption-key="$(openssl rand -base64 32)" \
  --namespace guardian
```

## Upgrading from gateway-stack

Earlier releases ran the Control Plane in the `gateway-stack` chart. Its values moved from `gateway-stack.controlPlane.*` to `control-plane.*`, and the resource names and selector labels changed, so Helm replaces the Deployment on upgrade.

| gateway-stack                                                                                                                                                                                                  | control-plane                                                                                                                                  |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `controlPlane.{replicaCount,image,serviceAccount,podAnnotations,podLabels,podSecurityContext,securityContext,service,resources,autoscaling,podDisruptionBudget,nodeSelector,tolerations,affinity,hostAliases}` | The same keys at the top level                                                                                                                 |
| `controlPlane.probes.*`                                                                                                                                                                                        | `startupProbe`, `livenessProbe`, `readinessProbe`; their paths must start with `config.apiBasePath`                                            |
| `controlPlane.{listenAddr,apiBasePath,corsAllowAll,auth,adapter,plugins}`                                                                                                                                      | `config.*`                                                                                                                                     |
| `controlPlane.extraArgs`                                                                                                                                                                                       | `args`                                                                                                                                         |
| `controlPlane.extraEnv`                                                                                                                                                                                        | `extraEnvVars`                                                                                                                                 |
| `controlPlane.virusTotal.enabled`                                                                                                                                                                              | `config.virusTotal.enabled`                                                                                                                    |
| `controlPlane.virusTotal.{existingSecret,secretKey}`                                                                                                                                                           | `secrets.virusTotal.{name,key}`                                                                                                                |
| `controlPlane.waitForRegistryViews.{enabled,intervalSeconds}`                                                                                                                                                  | `waitDeps.registryViews.*`                                                                                                                     |
| `controlPlane.waitForRegistryViews.image`                                                                                                                                                                      | `global.utilityImages.postgres`, a complete image reference; `pullPolicy` follows `global.imagePullPolicy`, and a digest goes in the reference |
| `controlPlane.waitForRegistryViews.securityContext`                                                                                                                                                            | Removed; the container runs as UID and GID 999 with the platform's restricted security context                                                 |
| `controlPlane.auth.existingSecret`                                                                                                                                                                             | `global.secrets.controlPlane.secretName`, which the LLM Gateway also reads                                                                     |
| `controlPlane.auth.registrationTokenSecret`                                                                                                                                                                    | `global.secrets.controlPlane.values.registrationTokenSecret` (the umbrella creates `platform-control-plane`)                                   |
| `controlPlane.auth.secretKeys.registrationTokenSecret`                                                                                                                                                         | `global.secrets.controlPlane.keys.registrationTokenSecret`                                                                                     |
| `controlPlane.plugins.publisherSigner.{existingSecret,secretKey}`                                                                                                                                              | `secrets.pluginPublisherSigner.{name,key}`                                                                                                     |
| `controlPlane.plugins.secrets.encryptionKey.{existingSecret,secretKey}`                                                                                                                                        | `secrets.pluginSecretsKey.{name,key}`                                                                                                          |
| `controlPlane.plugins.artifactStorage.<provider>.{existingSecret,secretKey,secretKeys}`                                                                                                                        | `secrets.pluginArtifactStorage.<provider>.{name,key,keys}`                                                                                     |
| `database.{existingSecret,secretKeys.dsn}`                                                                                                                                                                     | `externalDatabase.dsnSecretKeyRef.{name,key}`                                                                                                  |
| `ingress.{hosts.controlPlane,controlPlanePath,tls,controlPlaneAnnotations}`                                                                                                                                    | `ingress.{hosts,tls,annotations}`                                                                                                              |
| `ingress.{className,annotations}`, shared with the LLM Gateway                                                                                                                                                 | `ingress.{className,annotations}`, set separately                                                                                              |

When upgrading:

- Set `control-plane.enabled: true`. The umbrella chart leaves the Control Plane off by default, so moving the keys alone removes it
- The ServiceAccount is now `{Release.Name}-control-plane`. Move any Workload Identity binding to it before upgrading
- The Service is now `{Release.Name}-control-plane`. Update `governance-service.config.controlPlaneUrl`
- The registration token secret's key is now `registration-token-secret`. To keep an existing Secret, set `global.secrets.controlPlane.keys.registrationTokenSecret: registrationTokenSecret`
- `global.imageRegistryOverride` no longer redirects the wait container's image. Set `global.utilityImages.postgres` to the mirrored image
- `ingress.tls` is empty by default, and `gateway-stack.ingress.{className,annotations,tls,certManager}` no longer apply to the Control Plane. Set `ingress.tls`, and a `cert-manager.io/cluster-issuer` or `cert-manager.io/issuer` annotation, to keep HTTPS

## Troubleshooting

### Viewing Logs

```bash
kubectl logs -f deployment/control-plane -n guardian
```

### Checking Pod Status

```bash
kubectl get pods -n guardian -l app.kubernetes.io/name=control-plane
kubectl describe pod <pod-name> -n guardian
```

### Verifying Configuration

View the container arguments in the running pod:

```bash
kubectl get deployment/control-plane -n guardian -o jsonpath='{.spec.template.spec.containers[0].args}'
```

Test health endpoint:

```bash
kubectl exec -it deployment/control-plane -n guardian -- curl -s localhost:10010/health
```

### Common Issues

**Application not accessible**

- Verify ingress is enabled and configured correctly
- Check DNS points to your ingress controller
- Verify TLS certificates are valid
- With `config.apiBasePath` set, confirm the ingress path and probe paths carry the same prefix

**Pod stuck in Init**

- The `wait-registry-views` init container is waiting for the LLM Gateway's migrations
- Check the LLM Gateway's logs for migration progress and confirm both services share one database
- Verify the DSN in the database Secret reaches the intended host

**Agent registration rejected**

- Verify the LLM Gateway and the Control Plane read the same registration token secret
- Confirm `config.auth.registrationTokenIssuer` matches the issuer the LLM Gateway expects

**Plugin uploads fail**

- Verify the storage provider, bucket, and prefix
- For GCS with Workload Identity, confirm `serviceAccount.annotations` binds an identity with write access to the bucket
- For the `file` provider, confirm the PVC is ReadWriteMany and shared with the LLM Gateway

**Configuration not applying**

- Remember: service-level config overrides global config
- Check for typos in global value paths
- Restart pods if a Secret was updated: `kubectl rollout restart deployment/control-plane -n guardian`

## Health Endpoints

| Endpoint                          | Description                                                                       |
| --------------------------------- | --------------------------------------------------------------------------------- |
| `GET {config.apiBasePath}/health` | Liveness, readiness, and startup probe target; `/health` when no base path is set |

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://guardian.docs.eqtylab.io
- GitHub: https://github.com/eqtylab/guardian-infrastructure
