# Governance Service

A Helm chart for deploying the EQTY Lab Governance Service on Kubernetes.

## Description

The Governance Service provides governance validation, analysis capabilities, and workflow processing for the Governance Platform. It includes REST API endpoints for governance operations and a background worker service for processing governance workflows. This chart can be deployed standalone or as part of the Governance Platform umbrella chart.

## Configuration Model

Governance Service uses runtime configuration injection. Application configuration is provided through Helm values and injected into the container at startup.

This allows:

- A single immutable container image across environments
- Configuration changes without rebuilding images
- Clear separation of infrastructure and application settings
- Automatic configuration inheritance from umbrella chart globals

## Deployment Options

### Option 1: As Part of Governance Platform (Recommended)

When deployed via the `governance-platform` umbrella chart, Governance Service automatically inherits configuration from global values with zero additional configuration required.

**Example umbrella chart configuration:**

```yaml
global:
  domain: "governance.yourcompany.com"
  environmentType: "production"

  secrets:
    database:
      secretName: "platform-database"
      values:
        password: "YOUR_DB_PASSWORD"

    encryption:
      secretName: "platform-encryption"
      values:
        key: "YOUR_ENCRYPTION_KEY"

    storage:
      gcs:
        secretName: "platform-gcs"
        values:
          serviceAccountJson: "YOUR_GCS_SA_JSON"

    auth:
      provider: "auth0"
      auth0:
        secretName: "platform-auth0"

    governanceWorker:
      secretName: "platform-worker"
      values:
        encryptionKey: "WORKER_ENCRYPTION_KEY"
        clientId: "WORKER_CLIENT_ID"
        clientSecret: "WORKER_CLIENT_SECRET"

    governanceServiceAI:
      secretName: "platform-ai"
      values:
        apiKey: "YOUR_ANTHROPIC_API_KEY"

governance-service:
  enabled: true
  replicaCount: 2

  config:
    storageProvider: "gcs" # Explicitly set storage provider
    gcsBucketName: "governance-attachments"
    auth0Domain: "yourcompany.auth0.com" # Must be set when using Auth0

  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10

  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/rewrite-target: /$2
```

**What gets auto-configured:**

- ✅ Database connection (host, port, credentials)
- ✅ Encryption keys
- ✅ Storage credentials (GCS, Azure Blob, AWS S3)
- ✅ Auth provider configuration (Auth0 or Keycloak)
- ✅ Worker credentials and authentication
- ✅ AI API credentials
- ✅ Integration service URLs (Auth, Integrity)
- ✅ Environment type
- ✅ Image pull secrets

**Note:** Storage provider type must be explicitly set via `config.storageProvider`. This allows different services to use different storage providers.

### Option 2: Standalone Deployment

For standalone deployments outside the umbrella chart:

```yaml
enabled: true

externalDatabase:
  host: "postgresql.default.svc.cluster.local"
  database: "governance"
  user: "postgres"
  password: "YOUR_PASSWORD" # Or use secret reference

config:
  appEnv: "production"
  logLevel: "info"

  storageProvider: "gcs"
  gcsBucketName: "governance-attachments"

  auth0Domain: "yourcompany.auth0.com"
  auth0ClientId: "YOUR_CLIENT_ID"
  auth0ClientSecret: "YOUR_CLIENT_SECRET"

  integrityServiceUrl: "https://governance.yourcompany.com/integrityService"
  authServiceUrl: "https://governance.yourcompany.com/authService"

  serviceAccount:
    enabled: true
    serviceName: "governance-worker"
    authServiceApiKey: "YOUR_API_KEY"

  ai:
    enabled: true
    apiKey: "YOUR_ANTHROPIC_API_KEY"

secrets:
  encryption:
    name: "governance-encryption"
  storage:
    gcs:
      name: "governance-gcs-credentials"
  worker:
    name: "governance-worker-credentials"

service:
  enabled: true
  type: ClusterIP
  port: 10001

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/rewrite-target: /$2
  hosts:
    - host: governance.yourcompany.com
      paths:
        - path: "/governanceService(/|$)(.*)"
          pathType: ImplementationSpecific
  tls:
    - secretName: governance-service-tls
      hosts:
        - governance.yourcompany.com

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- PostgreSQL database (provided by umbrella chart or external)
- Storage provider (GCS, Azure Blob Storage, or AWS S3)
- Authentication provider (Auth0 or Keycloak)
- Anthropic API key (for AI features, optional)
- Ingress controller (nginx, traefik, etc.)
- TLS certificates (manual or via cert-manager)

## Installing the Chart

### Via Umbrella Chart (Recommended)

```bash
helm install governance-platform eqtylab/governance-platform \
  -f values.yaml \
  --namespace governance \
  --create-namespace
```

### Standalone Installation

```bash
helm install governance-service eqtylab/governance-service \
  -f values.yaml \
  --namespace governance \
  --create-namespace
```

## Uninstalling the Chart

```bash
helm uninstall governance-service --namespace governance
```

This removes all Kubernetes components associated with the chart and deletes the release.

## Values

### Global Parameters (Umbrella Chart)

When deployed via the umbrella chart, these global values are automatically used:

| Key                                           | Type   | Description                                       |
| --------------------------------------------- | ------ | ------------------------------------------------- |
| global.domain                                 | string | Base domain for all services                      |
| global.environmentType                        | string | Environment type (development/staging/production) |
| global.secrets.database.secretName            | string | Name of database credentials secret               |
| global.secrets.encryption.secretName          | string | Name of encryption key secret                     |
| global.secrets.auth.provider                  | string | Auth provider (auth0 or keycloak)                 |
| global.secrets.auth.auth0.secretName          | string | Auth0 credentials secret name                     |
| global.secrets.auth.keycloak.secretName       | string | Keycloak credentials secret name                  |
| global.secrets.storage.gcs.secretName         | string | GCS credentials secret name                       |
| global.secrets.storage.azure_blob.secretName  | string | Azure Blob credentials secret name                |
| global.secrets.storage.aws_s3.secretName      | string | AWS S3 credentials secret name                    |
| global.secrets.governanceWorker.secretName    | string | Worker credentials secret name                    |
| global.secrets.governanceServiceAI.secretName | string | AI API key secret name                            |

### Chart-Specific Parameters

| Key              | Type   | Default                                | Description                                           |
| ---------------- | ------ | -------------------------------------- | ----------------------------------------------------- |
| enabled          | bool   | `true`                                 | Enable this subchart (umbrella chart only)            |
| replicaCount     | int    | `1`                                    | Number of replicas to deploy                          |
| image.repository | string | `"ghcr.io/eqtylab/governance-service"` | Container image repository                            |
| image.pullPolicy | string | `"IfNotPresent"`                       | Image pull policy                                     |
| image.tag        | string | `""`                                   | Overrides the image tag (default is chart appVersion) |
| imagePullSecrets | list   | `[]`                                   | Additional image pull secrets (beyond global)         |
| command          | list   | `["./governance-service"]`             | Container entrypoint command                          |
| args             | list   | `[]`                                   | Container arguments (-debug-config, -help, etc.)      |

### Service Account

| Key                        | Type   | Default | Description                                              |
| -------------------------- | ------ | ------- | -------------------------------------------------------- |
| serviceAccount.create      | bool   | `false` | Specifies whether a service account should be created    |
| serviceAccount.automount   | bool   | `true`  | Automatically mount the ServiceAccount's API credentials |
| serviceAccount.annotations | object | `{}`    | Annotations to add to the service account                |
| serviceAccount.name        | string | `""`    | The name of the service account (generated if not set)   |

### Security

| Key                | Type   | Default | Description                        |
| ------------------ | ------ | ------- | ---------------------------------- |
| podAnnotations     | object | `{}`    | Annotations to add to pods         |
| podLabels          | object | `{}`    | Labels to add to pods              |
| podSecurityContext | object | `{}`    | Security context for the pod       |
| securityContext    | object | `{}`    | Security context for the container |

### Service

| Key             | Type   | Default       | Description               |
| --------------- | ------ | ------------- | ------------------------- |
| service.enabled | bool   | `true`        | Create a Service resource |
| service.type    | string | `"ClusterIP"` | Kubernetes service type   |
| service.port    | int    | `10001`       | Service port              |

### Ingress

| Key                 | Type   | Default                                                                                                                     | Description                 |
| ------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| ingress.enabled     | bool   | `false`                                                                                                                     | Enable ingress              |
| ingress.className   | string | `""`                                                                                                                        | Ingress class name          |
| ingress.annotations | object | `{}`                                                                                                                        | Ingress annotations         |
| ingress.hosts       | list   | `[{"host":"governance.example.com","paths":[{"path":"/governanceService(/\|$)(.*)","pathType":"ImplementationSpecific"}]}]` | Ingress hosts configuration |
| ingress.tls         | list   | `[]`                                                                                                                        | Ingress TLS configuration   |

### Resources

| Key                                           | Type   | Default | Description                          |
| --------------------------------------------- | ------ | ------- | ------------------------------------ |
| resources                                     | object | `{}`    | CPU/Memory resource requests/limits  |
| autoscaling.enabled                           | bool   | `false` | Enable horizontal pod autoscaling    |
| autoscaling.minReplicas                       | int    | `1`     | Minimum number of replicas           |
| autoscaling.maxReplicas                       | int    | `100`   | Maximum number of replicas           |
| autoscaling.targetCPUUtilizationPercentage    | int    | `80`    | Target CPU utilization percentage    |
| autoscaling.targetMemoryUtilizationPercentage | int    | `80`    | Target memory utilization percentage |

> 💡 **Note:** Resources are empty by default. For production, set appropriate requests and limits (recommended: cpu 250m-500m, memory 256Mi-512Mi).

### High Availability

| Key                              | Type | Default | Description                                                                                           |
| -------------------------------- | ---- | ------- | ----------------------------------------------------------------------------------------------------- |
| podDisruptionBudget.minAvailable | int  | `1`     | Minimum available pods during disruptions (only applied when replicaCount > 1 or autoscaling.enabled) |

### Node Scheduling

| Key          | Type   | Default | Description                       |
| ------------ | ------ | ------- | --------------------------------- |
| nodeSelector | object | `{}`    | Node labels for pod assignment    |
| tolerations  | list   | `[]`    | Tolerations for pod assignment    |
| affinity     | object | `{}`    | Affinity rules for pod assignment |

### Health Checks

| Key                                | Type   | Default     | Description                   |
| ---------------------------------- | ------ | ----------- | ----------------------------- |
| startupProbe.httpGet.path          | string | `"/health"` | Startup probe HTTP path       |
| startupProbe.httpGet.port          | string | `"http"`    | Startup probe port            |
| startupProbe.periodSeconds         | int    | `10`        | Startup probe period          |
| startupProbe.failureThreshold      | int    | `30`        | Startup failure threshold     |
| livenessProbe.httpGet.path         | string | `"/health"` | Liveness probe HTTP path      |
| livenessProbe.httpGet.port         | string | `"http"`    | Liveness probe port           |
| livenessProbe.initialDelaySeconds  | int    | `10`        | Liveness probe initial delay  |
| livenessProbe.periodSeconds        | int    | `10`        | Liveness probe period         |
| livenessProbe.failureThreshold     | int    | `3`         | Liveness failure threshold    |
| readinessProbe.httpGet.path        | string | `"/health"` | Readiness probe HTTP path     |
| readinessProbe.httpGet.port        | string | `"http"`    | Readiness probe port          |
| readinessProbe.initialDelaySeconds | int    | `5`         | Readiness probe initial delay |
| readinessProbe.periodSeconds       | int    | `5`         | Readiness probe period        |
| readinessProbe.failureThreshold    | int    | `2`         | Readiness failure threshold   |

### Database Configuration

| Key                                        | Type   | Default             | Description                                                 |
| ------------------------------------------ | ------ | ------------------- | ----------------------------------------------------------- |
| externalDatabase.host                      | string | `""`                | Database host (auto-generated as {Release.Name}-postgresql) |
| externalDatabase.port                      | int    | `5432`              | Database port                                               |
| externalDatabase.database                  | string | `"governance"`      | Database name                                               |
| externalDatabase.user                      | string | `"postgres"`        | Database user                                               |
| externalDatabase.password                  | string | `""`                | Database password (leave empty to use secret reference)     |
| externalDatabase.sslmode                   | string | `"disable"`         | SSL mode (disable/require/verify-ca/verify-full)            |
| externalDatabase.passwordSecretKeyRef.name | string | `""`                | Secret name containing database password                    |
| externalDatabase.passwordSecretKeyRef.key  | string | `""`                | Secret key name for password                                |
| migrations.runAtStartup                    | bool   | `true`              | Run database migrations automatically at startup            |
| migrations.path                            | string | `"/app/migrations"` | Path to migration files within the container                |

### Secret Configuration

All secret references support global fallbacks when deployed via umbrella chart.

#### Encryption Secret

| Key                     | Type   | Default | Description                                  |
| ----------------------- | ------ | ------- | -------------------------------------------- |
| secrets.encryption.name | string | `""`    | Secret name (auto-populated from global)     |
| secrets.encryption.key  | string | `""`    | Secret key name (auto-populated from global) |

#### Auth0 Secret (only used when auth provider is Auth0)

| Key                           | Type   | Default | Description                                   |
| ----------------------------- | ------ | ------- | --------------------------------------------- |
| secrets.auth0.name            | string | `""`    | Secret name (auto-populated from global)      |
| secrets.auth0.clientIdKey     | string | `""`    | Secret key for client ID (auto-populated)     |
| secrets.auth0.clientSecretKey | string | `""`    | Secret key for client secret (auto-populated) |

#### Keycloak Secret (only used when auth provider is Keycloak)

| Key                                                         | Type   | Default                | Description                                     |
| ----------------------------------------------------------- | ------ | ---------------------- | ----------------------------------------------- |
| secrets.keycloak.enabled                                    | bool   | `false`                | Enable Keycloak (auto-detected from global)     |
| secrets.keycloak.existingSecret                             | string | `""`                   | Secret name (auto-populated from global)        |
| secrets.keycloak.existingSecretKeys.clientId                | string | `"KEYCLOAK_CLIENT_ID"` | Secret key for client ID                        |
| secrets.keycloak.existingSecretKeys.realm                   | string | `"KEYCLOAK_REALM"`     | Secret key for realm                            |
| secrets.keycloak.existingSecretKeys.url                     | string | `"KEYCLOAK_URL"`       | Secret key for URL                              |
| secrets.keycloak.existingClientSecretKeyRef.name            | string | `""`                   | Client secret name (auto-populated from global) |
| secrets.keycloak.existingClientSecretKeyRef.clientSecretKey | string | `""`                   | Client secret key (auto-populated from global)  |

#### Storage Secrets

**Azure Blob Storage (only used when storage provider is azure_blob):**

| Key                                            | Type   | Default | Description                              |
| ---------------------------------------------- | ------ | ------- | ---------------------------------------- |
| secrets.storage.azure_blob.name                | string | `""`    | Secret name (auto-populated from global) |
| secrets.storage.azure_blob.accountNameKey      | string | `""`    | Account name key (auto-populated)        |
| secrets.storage.azure_blob.accountKeyKey       | string | `""`    | Account key (auto-populated)             |
| secrets.storage.azure_blob.connectionStringKey | string | `""`    | Connection string key (auto-populated)   |

**AWS S3 (only used when storage provider is aws_s3):**

| Key                                       | Type   | Default | Description                              |
| ----------------------------------------- | ------ | ------- | ---------------------------------------- |
| secrets.storage.aws_s3.name               | string | `""`    | Secret name (auto-populated from global) |
| secrets.storage.aws_s3.accessKeyIdKey     | string | `""`    | Access key ID key (auto-populated)       |
| secrets.storage.aws_s3.secretAccessKeyKey | string | `""`    | Secret access key (auto-populated)       |

**Google Cloud Storage (only used when storage provider is gcs):**

| Key                                       | Type   | Default | Description                               |
| ----------------------------------------- | ------ | ------- | ----------------------------------------- |
| secrets.storage.gcs.name                  | string | `""`    | Secret name (auto-populated from global)  |
| secrets.storage.gcs.serviceAccountJsonKey | string | `""`    | Service account JSON key (auto-populated) |

#### Worker Secret

| Key                             | Type   | Default | Description                              |
| ------------------------------- | ------ | ------- | ---------------------------------------- |
| secrets.worker.name             | string | `""`    | Secret name (auto-populated from global) |
| secrets.worker.encryptionKeyKey | string | `""`    | Encryption key (auto-populated)          |
| secrets.worker.clientIdKey      | string | `""`    | Client ID key (auto-populated)           |
| secrets.worker.clientSecretKey  | string | `""`    | Client secret key (auto-populated)       |

### Auth0 Sync Configuration

| Key                | Type | Default | Description                             |
| ------------------ | ---- | ------- | --------------------------------------- |
| auth0SyncAtStartup | bool | `true`  | Sync Auth0 users at application startup |
| auth0SyncPageSize  | int  | `100`   | Number of users to sync per page        |

### Application Configuration

All config values support global fallbacks when deployed via umbrella chart.

#### Application Settings

| Key             | Type   | Default     | Description                                    |
| --------------- | ------ | ----------- | ---------------------------------------------- |
| config.path     | string | `"/health"` | Health check endpoint path                     |
| config.appEnv   | string | `""`        | Application environment (auto-set from global) |
| config.logLevel | string | `"info"`    | Logging level (debug/info/warn/error)          |

#### HTTP Server Configuration

| Key                        | Type | Default | Description                                 |
| -------------------------- | ---- | ------- | ------------------------------------------- |
| config.server.readTimeout  | int  | `30`    | Maximum time to read request (seconds)      |
| config.server.writeTimeout | int  | `30`    | Maximum time to write response (seconds)    |
| config.server.idleTimeout  | int  | `120`   | Maximum idle time for connections (seconds) |

#### Indicator Configuration

| Key                                          | Type   | Default                     | Description                           |
| -------------------------------------------- | ------ | --------------------------- | ------------------------------------- |
| config.indicators.configPath                 | string | `"/app/configs/indicators"` | Path to indicator configuration files |
| config.indicators.reloadInterval             | int    | `300`                       | How often to reload configs (seconds) |
| config.indicators.validateOnLoad             | bool   | `true`                      | Validate configurations when loading  |
| config.indicators.osGuardrailsEnabled        | bool   | `false`                     | Enable OS guardrails                  |
| config.indicators.osGuardrailsBatchSize      | int    | `100`                       | Batch size for OS guardrails          |
| config.indicators.osGuardrailsTimeoutSeconds | int    | `5`                         | Timeout for OS guardrails (seconds)   |

#### Storage Configuration

| Key                    | Type   | Default | Description                                             |
| ---------------------- | ------ | ------- | ------------------------------------------------------- |
| config.storageProvider | string | `""`    | Storage provider (gcs/azure_blob/aws_s3) - **REQUIRED** |

**Google Cloud Storage (only used when storageProvider is "gcs"):**

| Key                  | Type   | Default | Description                    |
| -------------------- | ------ | ------- | ------------------------------ |
| config.gcsBucketName | string | `""`    | GCS bucket name (**REQUIRED**) |

**AWS S3 (only used when storageProvider is "aws_s3"):**

| Key                         | Type   | Default | Description                                       |
| --------------------------- | ------ | ------- | ------------------------------------------------- |
| config.awsS3Region          | string | `""`    | AWS region (**REQUIRED**)                         |
| config.awsS3BucketName      | string | `""`    | AWS S3 bucket name (**REQUIRED**)                 |
| config.awsS3Folder          | string | `""`    | AWS S3 folder/prefix (optional)                   |
| config.awsS3AccessKeyId     | string | `""`    | AWS access key ID (leave empty to use secret)     |
| config.awsS3SecretAccessKey | string | `""`    | AWS secret access key (leave empty to use secret) |

**Azure Blob Storage (only used when storageProvider is "azure_blob"):**

| Key                                 | Type   | Default | Description                                                 |
| ----------------------------------- | ------ | ------- | ----------------------------------------------------------- |
| config.azureStorageAccountName      | string | `""`    | Azure storage account name (leave empty to use secret)      |
| config.azureStorageAccountKey       | string | `""`    | Azure storage account key (leave empty to use secret)       |
| config.azureStorageConnectionString | string | `""`    | Azure storage connection string (leave empty to use secret) |
| config.azureStorageContainerName    | string | `""`    | Azure container name (**REQUIRED**)                         |
| config.azureUseManagedIdentity      | bool   | `false` | Use Azure managed identity for authentication               |

#### Auth0 Configuration (only used when auth provider is Auth0)

| Key                      | Type   | Default | Description                                     |
| ------------------------ | ------ | ------- | ----------------------------------------------- |
| config.auth0Domain       | string | `""`    | Auth0 tenant domain (**must be set**)           |
| config.auth0ClientId     | string | `""`    | Auth0 client ID (leave empty to use secret)     |
| config.auth0ClientSecret | string | `""`    | Auth0 client secret (leave empty to use secret) |

#### Integration URLs

| Key                        | Type   | Default | Description                                        |
| -------------------------- | ------ | ------- | -------------------------------------------------- |
| config.integrityServiceUrl | string | `""`    | Integrity Service URL (auto-generated from global) |
| config.authServiceUrl      | string | `""`    | Auth Service URL (auto-generated from global)      |

#### Service Account Configuration (for worker authentication)

| Key                                             | Type   | Default               | Description                                            |
| ----------------------------------------------- | ------ | --------------------- | ------------------------------------------------------ |
| config.serviceAccount.enabled                   | bool   | `true`                | Enable service account authentication for worker       |
| config.serviceAccount.authServiceUrl            | string | `""`                  | Auth service URL (falls back to config.authServiceUrl) |
| config.serviceAccount.authServiceApiKey         | string | `""`                  | API key for auth service (auto-generated if available) |
| config.serviceAccount.serviceName               | string | `"governance-worker"` | Service account name                                   |
| config.serviceAccount.existingSecret            | string | `""`                  | Use existing secret for API key                        |
| config.serviceAccount.existingSecretKeys.apiKey | string | `"api-secret"`        | Secret key name for API key                            |

#### AI Configuration

| Key                         | Type   | Default                      | Description                                    |
| --------------------------- | ------ | ---------------------------- | ---------------------------------------------- |
| config.ai.enabled           | bool   | `true`                       | Enable AI features                             |
| config.ai.provider          | string | `"anthropic"`                | AI provider                                    |
| config.ai.model             | string | `"claude-3-7-sonnet-latest"` | AI model name                                  |
| config.ai.temperature       | float  | `0.7`                        | Temperature for AI responses                   |
| config.ai.maxTokens         | int    | `4000`                       | Maximum tokens for AI responses                |
| config.ai.timeoutSeconds    | int    | `60`                         | Timeout for AI requests (seconds)              |
| config.ai.retryAttempts     | int    | `3`                          | Number of retry attempts for AI requests       |
| config.ai.secretKeyRef.name | string | `""`                         | AI API key secret (auto-populated from global) |
| config.ai.secretKeyRef.key  | string | `""`                         | AI API key secret key (auto-populated)         |
| config.ai.apiKey            | string | `""`                         | AI API key (leave empty to use secret)         |
| config.ai.useV2             | bool   | `true`                       | Use V2 API                                     |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level config values** - Explicitly set in `governance-service.config.*`
2. **Global values** - Set in `global.*` (umbrella chart)
3. **Chart defaults** - Default values from `values.yaml`

### Example Configuration Flow

```yaml
# Umbrella chart values.yaml
global:
  domain: "governance.prod.company.com"
  environmentType: "production"
  secrets:
    storage:
      gcs:
        secretName: "platform-gcs"

governance-service:
  enabled: true
  # config.appEnv automatically becomes: production
  # Integration URLs auto-generated from global.domain
  # Storage credentials auto-populated from global.secrets.storage.gcs

  # Must explicitly set storage provider:
  config:
    storageProvider: "gcs" # Required - not auto-set
    gcsBucketName: "governance-attachments" # Required - not auto-set
```

## Storage Provider Configuration

### Google Cloud Storage

```yaml
global:
  secrets:
    storage:
      gcs:
        secretName: "platform-gcs"

governance-service:
  config:
    storageProvider: "gcs" # Explicitly set storage provider
    gcsBucketName: "governance-attachments" # Must be set
```

### Azure Blob Storage

```yaml
global:
  secrets:
    storage:
      azure_blob:
        secretName: "platform-azure-blob"

governance-service:
  config:
    storageProvider: "azure_blob" # Explicitly set storage provider
    azureStorageContainerName: "governance-data" # Must be set
```

### AWS S3

```yaml
global:
  secrets:
    storage:
      aws_s3:
        secretName: "platform-aws-s3"

governance-service:
  config:
    storageProvider: "aws_s3" # Explicitly set storage provider
    awsS3Region: "us-east-1" # Must be set
    awsS3BucketName: "governance-bucket" # Must be set
    awsS3Folder: "attachments" # Optional prefix
```

## Upgrading

### Upgrading via Umbrella Chart

```bash
helm upgrade governance-platform eqtylab/governance-platform \
  -f values.yaml \
  --namespace governance
```

### Upgrading Standalone

```bash
helm upgrade governance-service eqtylab/governance-service \
  -f values.yaml \
  --namespace governance
```

## Troubleshooting

### Viewing Logs

```bash
kubectl logs -f deployment/governance-service -n governance
```

### Checking Pod Status

```bash
kubectl get pods -n governance -l app.kubernetes.io/name=governance-service
kubectl describe pod <pod-name> -n governance
```

### Testing Configuration

View environment variables in running pod:

```bash
kubectl exec -it deployment/governance-service -n governance -- env | sort
```

Test health endpoint:

```bash
kubectl exec -it deployment/governance-service -n governance -- curl localhost:10001/health
```

### Common Issues

**Application not accessible**

- Verify ingress is enabled and configured correctly
- Check DNS points to your ingress controller
- Verify TLS certificates are valid
- Ensure `global.domain` matches your DNS configuration

**Database connection errors**

- Verify database host is correct (should be PostgreSQL service name)
- Check database credentials in secret
- Ensure database `governance` exists
- Verify migrations completed successfully: check logs for migration output
- Check network policies allow traffic between services

**Storage errors**

- Verify storage provider is explicitly set via `config.storageProvider`
- Check storage credentials in secret
- For GCS: verify service account JSON is valid and bucket exists
- For Azure: verify account name, key/connection string, and container exist
- For AWS: verify access keys are valid, bucket exists, and region is correct
- Ensure service has network access to storage provider

**Authentication fails**

- Verify auth provider matches `global.secrets.auth.provider`
- For Auth0: check domain, client ID, and client secret are correct
- For Keycloak: check URL, realm, client ID, and client secret are correct
- Ensure auth service is running and accessible
- Check worker credentials are properly configured

**Worker authentication failures**

- Check worker credentials secret exists (`secrets.worker.name`)
- Verify service account is configured in auth service
- Ensure auth service API key is valid
- Check `config.serviceAccount.authServiceUrl` is accessible

**AI feature errors**

- Verify AI is enabled via `config.ai.enabled`
- Check Anthropic API key is configured in secret
- Ensure API key secret exists and is accessible
- Verify network access to Anthropic API
- Check timeout and retry settings if requests are failing

**Configuration not applying**

- Remember: service-level config overrides global config
- Check for typos in global value paths
- Restart pods if configuration was updated: `kubectl rollout restart deployment/governance-service -n governance`
- Use `-debug-config` or `-debug-config-only` args to see loaded configuration

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://docs.eqtylab.io
- GitHub: https://github.com/eqtylab/governance-studio-infrastructure
