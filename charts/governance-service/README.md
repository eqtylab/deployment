# Governance Service

A Helm chart for deploying the EQTY Lab Governance Service on Kubernetes.

## Description

The Governance Service provides governance validation, analysis capabilities, and workflow processing for the Governance Platform. It includes REST API endpoints for governance operations and a background worker service for processing governance workflows.

Key capabilities:

- **Governance Workflows**: Validation, analysis, and processing of governance policies
- **Storage Integration**: Multi-provider support for GCS, Azure Blob, and AWS S3
- **Worker Service**: Background processing with service account authentication
- **Multi-Provider Auth**: Backend support for Auth0, Keycloak, and Microsoft Entra ID identity providers

## Configuration Model

Governance Service uses runtime configuration injected via environment variables. Application configuration is provided through Helm values and injected into the container at startup.

This allows:

- A single immutable container image across environments
- Configuration changes without rebuilding images
- Clear separation of infrastructure and application settings
- Automatic configuration inheritance from umbrella chart globals

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- PostgreSQL database (provided by umbrella chart or external)
- Storage provider (GCS, Azure Blob Storage, or AWS S3)
- Authentication provider (Auth0, Keycloak, or Entra ID)
- Ingress controller (NGINX, Traefik, etc.)
- TLS certificates (manual or via cert-manager)

## Deployment

When deployed via the `governance-platform` umbrella chart, Governance Service automatically inherits configuration from global values with no additional configuration required.

### Quick Start

Minimum configuration required in your umbrella chart values:

**Auth0:**

```yaml
global:
  secrets:
    auth:
      provider: "auth0"

governance-service:
  image:
    tag: ""
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/rewrite-target: "/$2"
      nginx.ingress.kubernetes.io/proxy-body-size: "64m"
    hosts:
      - host: "governance.yourcompany.com"
        paths:
          - path: "/governanceService(/|$)(.*)"
            pathType: "ImplementationSpecific"
    tls:
      - secretName: "governance-service-tls"
        hosts:
          - "governance.yourcompany.com"
  config:
    auth0Domain: "your-tenant.us.auth0.com"

    # Storage Configuration - GCS
    storageProvider: "gcs"
    gcsBucketName: "your-governance-artifacts-bucket"

    # Storage Configuration - Azure Blob (uncomment to use instead)
    # storageProvider: "azure_blob"
    # azureStorageAccountName: "your-storage-account"
    # azureStorageContainerName: "your-governance-artifacts-container"

    # Storage Configuration - AWS S3 (uncomment to use instead)
    # storageProvider: "aws_s3"
    # awsS3Region: "us-east-1"
    # awsS3BucketName: "your-governance-artifacts-bucket"
```

**Keycloak:**

```yaml
global:
  secrets:
    auth:
      provider: "keycloak"

governance-service:
  image:
    tag: ""
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/rewrite-target: "/$2"
      nginx.ingress.kubernetes.io/proxy-body-size: "64m"
    hosts:
      - host: "governance.yourcompany.com"
        paths:
          - path: "/governanceService(/|$)(.*)"
            pathType: "ImplementationSpecific"
    tls:
      - secretName: "governance-service-tls"
        hosts:
          - "governance.yourcompany.com"
  config:
    keycloakUrl: "https://keycloak.yourcompany.com"
    keycloakRealm: "governance"

    # Storage Configuration - GCS
    storageProvider: "gcs"
    gcsBucketName: "your-governance-artifacts-bucket"

    # Storage Configuration - Azure Blob (uncomment to use instead)
    # storageProvider: "azure_blob"
    # azureStorageAccountName: "your-storage-account"
    # azureStorageContainerName: "your-governance-artifacts-container"

    # Storage Configuration - AWS S3 (uncomment to use instead)
    # storageProvider: "aws_s3"
    # awsS3Region: "us-east-1"
    # awsS3BucketName: "your-governance-artifacts-bucket"
```

**Microsoft Entra ID:**

```yaml
global:
  secrets:
    auth:
      provider: "entra"

governance-service:
  image:
    tag: ""
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/rewrite-target: "/$2"
      nginx.ingress.kubernetes.io/proxy-body-size: "64m"
    hosts:
      - host: "governance.yourcompany.com"
        paths:
          - path: "/governanceService(/|$)(.*)"
            pathType: "ImplementationSpecific"
    tls:
      - secretName: "governance-service-tls"
        hosts:
          - "governance.yourcompany.com"
  config:
    entraTenantId: "your-tenant-id"

    # Storage Configuration - GCS
    storageProvider: "gcs"
    gcsBucketName: "your-governance-artifacts-bucket"

    # Storage Configuration - Azure Blob (uncomment to use instead)
    # storageProvider: "azure_blob"
    # azureStorageAccountName: "your-storage-account"
    # azureStorageContainerName: "your-governance-artifacts-container"

    # Storage Configuration - AWS S3 (uncomment to use instead)
    # storageProvider: "aws_s3"
    # awsS3Region: "us-east-1"
    # awsS3BucketName: "your-governance-artifacts-bucket"
```

### Required Configuration

Beyond what is auto-configured, these values **must** be explicitly set:

**Storage (exactly one provider must be configured):**

- `config.storageProvider` - Storage provider type (`gcs`, `azure_blob`, or `aws_s3`)
- GCS: `config.gcsBucketName` - GCS bucket name
- Azure Blob: `config.azureStorageAccountName` - Storage account name, `config.azureStorageContainerName` - Azure container name
- AWS S3: `config.awsS3Region` - AWS region, `config.awsS3BucketName` - S3 bucket name

**Auth0:**

- `config.auth0Domain` - Auth0 tenant domain (e.g., `yourcompany.auth0.com`)
- Client ID and secret are auto-configured from the `global.secrets.auth.auth0` secret

**Keycloak:**

- `config.keycloakUrl` - Keycloak server URL (e.g., `https://keycloak.yourcompany.com`)
- `config.keycloakRealm` - Keycloak realm name (e.g., `governance`)
- Service account client ID and secret are auto-configured from the `global.secrets.auth.keycloak` secret

**Microsoft Entra ID:**

- `config.entraTenantId` - Microsoft Entra ID tenant ID (can also be auto-configured from `global.secrets.auth.entra` secret)
- Client ID and secret are auto-configured from the `global.secrets.auth.entra` secret

Only one authentication provider should be configured at a time, set via `global.secrets.auth.provider` in the umbrella chart.

**What gets auto-configured:**

From global values:

- Database connection (host, port, credentials from `global.postgresql.*` and `global.secrets.database`)
- Auth provider configuration (from `global.secrets.auth.provider`)
- Encryption keys (from `global.secrets.encryption`)
- Storage credentials (from `global.secrets.storage.*`)
- Auth service credentials for worker authentication (from `global.secrets.authService`)
- Environment type (from `global.environmentType`)
- Image pull secrets (from `global.secrets.imageRegistry`)

Generated defaults:

- Database host defaults to `{Release.Name}-postgresql` (co-deployed PostgreSQL)
- Swagger host defaults to `global.domain`
- Integration service URLs use internal cluster DNS (e.g., `http://{Release.Name}-integrity-service:3050`)
- Public API base path defaults to `https://{global.domain}/governanceService` (when ingress is enabled)

## Values

### Global Parameters (Umbrella Chart)

When deployed via the umbrella chart, these global values are automatically used:

| Key                                          | Type   | Description                                       |
| -------------------------------------------- | ------ | ------------------------------------------------- |
| global.domain                                | string | Base domain for all services                      |
| global.environmentType                       | string | Environment type (development/staging/production) |
| global.postgresql.host                       | string | PostgreSQL host                                   |
| global.postgresql.port                       | int    | PostgreSQL port                                   |
| global.postgresql.database                   | string | PostgreSQL database name                          |
| global.postgresql.username                   | string | PostgreSQL username                               |
| global.secrets.database.secretName           | string | Name of database credentials secret               |
| global.secrets.encryption.secretName         | string | Name of encryption key secret                     |
| global.secrets.auth.provider                 | string | Auth provider (auth0, keycloak, or entra)         |
| global.secrets.auth.auth0.secretName         | string | Auth0 credentials secret name                     |
| global.secrets.auth.keycloak.secretName      | string | Keycloak credentials secret name                  |
| global.secrets.auth.entra.secretName         | string | Entra ID credentials secret name                  |
| global.secrets.storage.gcs.secretName        | string | GCS credentials secret name                       |
| global.secrets.storage.azure_blob.secretName | string | Azure Blob credentials secret name                |
| global.secrets.storage.aws_s3.secretName     | string | AWS S3 credentials secret name                    |
| global.secrets.authService.secretName        | string | Auth service API key secret name                  |
| global.secrets.imageRegistry.secretName      | string | Image registry credentials secret name            |

### Chart-Specific Parameters

| Key              | Type   | Default                                | Description                                           |
| ---------------- | ------ | -------------------------------------- | ----------------------------------------------------- |
| enabled          | bool   | `true`                                 | Enable this subchart (umbrella chart only)            |
| replicaCount     | int    | `2`                                    | Number of replicas to deploy                          |
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

> **Note:** Resources are empty by default. For production, set appropriate requests and limits (recommended: cpu 250m-500m, memory 256Mi-512Mi).

### High Availability

| Key                                | Type | Default | Description                                                                        |
| ---------------------------------- | ---- | ------- | ---------------------------------------------------------------------------------- |
| podDisruptionBudget.enabled        | bool | `true`  | Enable Pod Disruption Budget                                                       |
| podDisruptionBudget.minAvailable   | int  | `1`     | Minimum available pods during disruptions (only rendered when replicaCount > 1)    |
| podDisruptionBudget.maxUnavailable | int  | `1`     | Maximum unavailable pods during disruptions (only rendered when replicaCount <= 1) |

### Node Scheduling

| Key            | Type   | Default | Description                       |
| -------------- | ------ | ------- | --------------------------------- |
| nodeSelector   | object | `{}`    | Node labels for pod assignment    |
| tolerations    | list   | `[]`    | Tolerations for pod assignment    |
| affinity       | object | `{}`    | Affinity rules for pod assignment |
| initContainers | list   | `[]`    | Init containers to add to the pod |

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

| Key                                        | Type   | Default             | Description                                                           |
| ------------------------------------------ | ------ | ------------------- | --------------------------------------------------------------------- |
| externalDatabase.host                      | string | `""`                | Database host (auto-generated as {Release.Name}-postgresql)           |
| externalDatabase.port                      | int    | `5432`              | Database port                                                         |
| externalDatabase.name                      | string | `"governance"`      | Database name                                                         |
| externalDatabase.user                      | string | `"postgres"`        | Database user                                                         |
| externalDatabase.password                  | string | `""`                | Database password (auto-configured from global.secrets.database)      |
| externalDatabase.sslMode                   | string | `"disable"`         | SSL mode (disable/require/verify-ca/verify-full)                      |
| externalDatabase.passwordSecretKeyRef.name | string | `""`                | Secret name (auto-configured from global.secrets.database.secretName) |
| externalDatabase.passwordSecretKeyRef.key  | string | `"password"`        | Secret key name for password                                          |
| migrations.runAtStartup                    | bool   | `true`              | Run database migrations automatically at startup                      |
| migrations.path                            | string | `"/app/migrations"` | Path to migration files within the container                          |

### Secret Configuration

All secret references support global fallbacks when deployed via umbrella chart.

#### Encryption Secret

| Key                     | Type   | Description                                                             |
| ----------------------- | ------ | ----------------------------------------------------------------------- |
| secrets.encryption.name | string | Secret name (auto-configured from global.secrets.encryption.secretName) |

#### Auth0 Secret (only used when auth provider is Auth0)

| Key                     | Type   | Description                                                             |
| ----------------------- | ------ | ----------------------------------------------------------------------- |
| secrets.auth.auth0.name | string | Secret name (auto-configured from global.secrets.auth.auth0.secretName) |

#### Keycloak Secret (only used when auth provider is Keycloak)

| Key                        | Type   | Description                                                                |
| -------------------------- | ------ | -------------------------------------------------------------------------- |
| secrets.auth.keycloak.name | string | Secret name (auto-configured from global.secrets.auth.keycloak.secretName) |

#### Entra ID Secret (only used when auth provider is Entra ID)

| Key                     | Type   | Description                                                             |
| ----------------------- | ------ | ----------------------------------------------------------------------- |
| secrets.auth.entra.name | string | Secret name (auto-configured from global.secrets.auth.entra.secretName) |

#### Storage Secrets

**Azure Blob Storage (only used when storage provider is azure_blob):**

| Key                             | Type   | Description                                                                     |
| ------------------------------- | ------ | ------------------------------------------------------------------------------- |
| secrets.storage.azure_blob.name | string | Secret name (auto-configured from global.secrets.storage.azure_blob.secretName) |

**AWS S3 (only used when storage provider is aws_s3):**

| Key                         | Type   | Description                                                                 |
| --------------------------- | ------ | --------------------------------------------------------------------------- |
| secrets.storage.aws_s3.name | string | Secret name (auto-configured from global.secrets.storage.aws_s3.secretName) |

**Google Cloud Storage (only used when storage provider is gcs):**

| Key                      | Type   | Description                                                              |
| ------------------------ | ------ | ------------------------------------------------------------------------ |
| secrets.storage.gcs.name | string | Secret name (auto-configured from global.secrets.storage.gcs.secretName) |

#### Auth Service Secret

| Key                      | Type   | Description                                                              |
| ------------------------ | ------ | ------------------------------------------------------------------------ |
| secrets.authService.name | string | Secret name (auto-configured from global.secrets.authService.secretName) |

### Application Configuration

All config values support global fallbacks when deployed via umbrella chart.

#### Application Settings

| Key                            | Type   | Default     | Description                                                           |
| ------------------------------ | ------ | ----------- | --------------------------------------------------------------------- |
| config.healthPath              | string | `"/health"` | Health check endpoint path                                            |
| config.appEnv                  | string | `""`        | Application environment (auto-configured from global.environmentType) |
| config.logLevel                | string | `"info"`    | Logging level (debug/info/warn/error)                                 |
| config.credentialEncryptionKey | string | `""`        | Encryption key (auto-configured from global.secrets.encryption)       |

#### HTTP Server Configuration

| Key                           | Type   | Default                | Description                                               |
| ----------------------------- | ------ | ---------------------- | --------------------------------------------------------- |
| config.server.readTimeout     | int    | `30`                   | Maximum time to read request (seconds)                    |
| config.server.writeTimeout    | int    | `30`                   | Maximum time to write response (seconds)                  |
| config.server.idleTimeout     | int    | `120`                  | Maximum idle time for connections (seconds)               |
| config.server.swaggerEnabled  | bool   | `true`                 | Enable Swagger documentation                              |
| config.server.swaggerHost     | string | `""`                   | Swagger host (auto-generated from global.domain)          |
| config.server.swaggerBasePath | string | `"/governanceService"` | Swagger base path (only used when swaggerEnabled is true) |

#### Storage Configuration

| Key                    | Type   | Default | Description                                             |
| ---------------------- | ------ | ------- | ------------------------------------------------------- |
| config.storageProvider | string | `""`    | Storage provider (gcs/azure_blob/aws_s3) - **REQUIRED** |

**Google Cloud Storage (only used when storageProvider is "gcs"):**

| Key                  | Type   | Default | Description                    |
| -------------------- | ------ | ------- | ------------------------------ |
| config.gcsBucketName | string | `""`    | GCS bucket name (**REQUIRED**) |

**AWS S3 (only used when storageProvider is "aws_s3"):**

| Key                         | Type   | Default | Description                                                                |
| --------------------------- | ------ | ------- | -------------------------------------------------------------------------- |
| config.awsS3Region          | string | `""`    | AWS region (**REQUIRED**)                                                  |
| config.awsS3BucketName      | string | `""`    | AWS S3 bucket name (**REQUIRED**)                                          |
| config.awsS3AccessKeyId     | string | `""`    | AWS access key ID (auto-configured from global.secrets.storage.aws_s3)     |
| config.awsS3SecretAccessKey | string | `""`    | AWS secret access key (auto-configured from global.secrets.storage.aws_s3) |

**Azure Blob Storage (only used when storageProvider is "azure_blob"):**

| Key                                 | Type   | Default | Description                                                                              |
| ----------------------------------- | ------ | ------- | ---------------------------------------------------------------------------------------- |
| config.azureStorageAccountName      | string | `""`    | Azure storage account name (**must be set** when using Azure Blob)                       |
| config.azureStorageAccountKey       | string | `""`    | Azure storage account key (auto-configured from global.secrets.storage.azure_blob)       |
| config.azureStorageConnectionString | string | `""`    | Azure storage connection string (auto-configured from global.secrets.storage.azure_blob) |
| config.azureStorageContainerName    | string | `""`    | Azure container name (**REQUIRED**)                                                      |
| config.azureUseManagedIdentity      | bool   | `false` | Use Azure managed identity for authentication                                            |

#### Authentication Provider Configuration

| Key                 | Type   | Default | Description                                                                              |
| ------------------- | ------ | ------- | ---------------------------------------------------------------------------------------- |
| config.authProvider | string | `""`    | Auth provider (auth0/keycloak/entra) - auto-configured from global.secrets.auth.provider |

#### Auth0 Configuration (only used when auth provider is Auth0)

| Key                       | Type   | Default | Description                                                          |
| ------------------------- | ------ | ------- | -------------------------------------------------------------------- |
| config.auth0Domain        | string | `""`    | Auth0 tenant domain (**must be set**)                                |
| config.auth0ClientId      | string | `""`    | Auth0 client ID (auto-configured from global.secrets.auth.auth0)     |
| config.auth0ClientSecret  | string | `""`    | Auth0 client secret (auto-configured from global.secrets.auth.auth0) |
| config.auth0SyncAtStartup | bool   | `true`  | Sync Auth0 users at application startup                              |
| config.auth0SyncPageSize  | int    | `100`   | Number of users to sync per page                                     |

#### Keycloak Configuration (only used when auth provider is Keycloak)

| Key                         | Type   | Default | Description                                                                                |
| --------------------------- | ------ | ------- | ------------------------------------------------------------------------------------------ |
| config.keycloakUrl          | string | `""`    | Keycloak server URL (**must be set**, e.g., "https://keycloak.example.com")                |
| config.keycloakRealm        | string | `""`    | Keycloak realm name (**must be set**, e.g., "governance")                                  |
| config.keycloakClientId     | string | `""`    | Keycloak service account client ID (auto-configured from global.secrets.auth.keycloak)     |
| config.keycloakClientSecret | string | `""`    | Keycloak service account client secret (auto-configured from global.secrets.auth.keycloak) |

#### Microsoft Entra ID Configuration (only used when auth provider is Entra ID)

| Key                      | Type   | Default | Description                                                                   |
| ------------------------ | ------ | ------- | ----------------------------------------------------------------------------- |
| config.entraTenantId     | string | `""`    | Microsoft Entra ID tenant ID (auto-configured from global.secrets.auth.entra) |
| config.entraClientId     | string | `""`    | Entra client ID (auto-configured from global.secrets.auth.entra)              |
| config.entraClientSecret | string | `""`    | Entra client secret (auto-configured from global.secrets.auth.entra)          |

#### Integration URLs

| Key                        | Type   | Default | Description                                                                            |
| -------------------------- | ------ | ------- | -------------------------------------------------------------------------------------- |
| config.integrityServiceUrl | string | `""`    | Integrity Service URL (auto-generated as http://{Release.Name}-integrity-service:3050) |
| config.authServiceUrl      | string | `""`    | Auth Service URL (auto-generated as http://{Release.Name}-auth-service:8080)           |

#### Worker Service Account Configuration

The governance-service background worker authenticates against the auth-service using an API key. This configuration controls how the worker identifies itself and connects to the auth-service.

| Key                                             | Type   | Default               | Description                                                            |
| ----------------------------------------------- | ------ | --------------------- | ---------------------------------------------------------------------- |
| config.serviceAccount.enabled                   | bool   | `true`                | Enable service account authentication for the background worker        |
| config.serviceAccount.authServiceUrl            | string | `""`                  | Auth-service URL for worker auth (falls back to config.authServiceUrl) |
| config.serviceAccount.authServiceApiKey         | string | `""`                  | Auth-service API key (auto-configured from global.secrets.authService) |
| config.serviceAccount.serviceName               | string | `"governance-worker"` | Worker identity name used when authenticating with the auth-service    |
| config.serviceAccount.existingSecret            | string | `""`                  | Override secret name (falls back to secrets.authService)               |
| config.serviceAccount.existingSecretKeys.apiKey | string | `"api-secret"`        | Key within the secret containing the auth-service API key              |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level config values** - Explicitly set in `governance-service.config.*`
2. **Global values** - Set in `global.*` (umbrella chart)
3. **Chart defaults** - Default values from `values.yaml`

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
    gcsBucketName: "your-governance-artifacts-bucket" # Must be set
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
    azureStorageAccountName: "your-storage-account" # Must be set
    azureStorageContainerName: "your-governance-artifacts-container" # Must be set
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
    awsS3BucketName: "your-governance-artifacts-bucket" # Must be set
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

### Verifying Configuration

View key environment variables in the running pod:

```bash
kubectl exec -it deployment/governance-service -n governance -- env | grep -E 'STORAGE|AUTH|ENTRA|KEYCLOAK|DATABASE|DB_'
```

View all environment variables:

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
- For Entra: check tenant ID, client ID, and client secret are correct
- Ensure auth service is running and accessible
- Check worker credentials are properly configured

**Worker authentication failures**

- Check auth service secret exists (`secrets.authService.name`)
- Verify service account is configured in auth service
- Ensure auth service API key is valid
- Check `config.serviceAccount.authServiceUrl` is accessible

**Configuration not applying**

- Remember: service-level config overrides global config
- Check for typos in global value paths
- Restart pods if configuration was updated: `kubectl rollout restart deployment/governance-service -n governance`
- Use `-debug-config` or `-debug-config-only` args to see loaded configuration

## Health Endpoints

| Endpoint      | Description          |
| ------------- | -------------------- |
| `GET /health` | Overall health check |

### API Documentation

When `config.server.swaggerEnabled` is `true` (default), Swagger UI is available at:

```
https://{domain}/governanceService/swagger/index.html
```

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://docs.eqtylab.io
- GitHub: https://github.com/eqtylab/governance-studio-infrastructure
