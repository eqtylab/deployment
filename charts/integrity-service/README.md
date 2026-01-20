# Integrity Service

A Helm chart for deploying the EQTY Lab Integrity Service on Kubernetes.

## Description

The Integrity Service provides verifiable credentials, data lineage tracking, and statement registry capabilities for the Governance Platform. This chart can be deployed standalone or as part of the Governance Platform umbrella chart.

## Configuration Model

Integrity Service uses runtime configuration injection via environment variables. Application configuration is provided through Helm values and injected into the container at startup.

This allows:

- A single immutable container image across environments
- Configuration changes without rebuilding images
- Clear separation of infrastructure and application settings
- Automatic configuration inheritance from umbrella chart globals

## Deployment Options

### Option 1: As Part of Governance Platform (Recommended)

When deployed via the `governance-platform` umbrella chart, Integrity Service automatically inherits configuration from global values with zero additional configuration required.

**Example umbrella chart configuration:**

```yaml
global:
  domain: "governance.yourcompany.com"
  environmentType: "production"

  secrets:
    database:
      secretName: "platform-database"
      values:
        username: "postgres"
        password: "YOUR_DB_PASSWORD"

    storage:
      azure_blob:
        secretName: "platform-azure-blob"
        values:
          accountName: "yourstorageaccount"
          accountKey: "YOUR_STORAGE_KEY"
          connectionString: "YOUR_CONNECTION_STRING"

integrity-service:
  enabled: true
  replicaCount: 2

  config:
    integrityAppBlobStoreType: "azure_blob" # Explicitly set storage provider
    integrityAppBlobStoreAccount: "yourstorageaccount"
    integrityAppBlobStoreContainer: "integrity-data"

  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10

  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/rewrite-target: /$2
```

**What gets auto-configured:**

- ✅ Database connection (host, port, credentials)
- ✅ Storage credentials (Azure Blob, AWS S3)
- ✅ Auth service URL
- ✅ Environment type
- ✅ Image pull secrets
- ✅ Public service URL

**Note:** Storage provider type must be explicitly set via `config.integrityAppBlobStoreType`. This allows different services to use different storage providers.

### Option 2: Standalone Deployment

For standalone deployments outside the umbrella chart:

```yaml
enabled: true

config:
  rustEnv: "production"

  # Database configuration
  integrityAppDbHost: "postgresql.default.svc.cluster.local"
  integrityAppDbName: "IntegrityServiceDB"
  integrityAppDbUser: "postgres"
  integrityAppDbPassword: "YOUR_PASSWORD" # Or use secret reference

  # Blob storage (Azure example)
  integrityAppBlobStoreType: "azure_blob"
  integrityAppBlobStoreAccount: "yourstorageaccount"
  integrityAppBlobStoreContainer: "integrity-data"
  integrityAppBlobStoreKey: "YOUR_STORAGE_KEY" # Or use secret reference

  # Auth configuration
  integrityAppAuthType: "auth_service"
  integrityAppAuthUrl: "http://auth-service:8080"

  # Service URL
  integrityServiceUrl: "https://governance.yourcompany.com/integrityService"

secrets:
  database:
    name: "integrity-db-credentials"

  storage:
    azure_blob:
      name: "integrity-storage-credentials"

service:
  enabled: true
  type: ClusterIP
  port: 3050

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/rewrite-target: /$2
  hosts:
    - host: governance.yourcompany.com
      paths:
        - path: "/integrityService(/|$)(.*)"
          pathType: ImplementationSpecific
  tls:
    - secretName: integrity-tls
      hosts:
        - governance.yourcompany.com

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- PostgreSQL database (can be deployed via umbrella chart)
- Azure Blob Storage or AWS S3 account
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
helm install integrity-service eqtylab/integrity-service \
  -f values.yaml \
  --namespace governance \
  --create-namespace
```

## Uninstalling the Chart

```bash
helm uninstall integrity-service --namespace governance
```

This removes all Kubernetes components associated with the chart and deletes the release.

## Values

### Global Parameters (Umbrella Chart)

When deployed via the umbrella chart, these global values are automatically used:

| Key                                          | Type   | Description                                       |
| -------------------------------------------- | ------ | ------------------------------------------------- |
| global.domain                                | string | Base domain for all services                      |
| global.environmentType                       | string | Environment type (development/staging/production) |
| global.postgresql.username                   | string | PostgreSQL username                               |
| global.secrets.database.secretName           | string | Name of database credentials secret               |
| global.secrets.imageRegistry.secretName      | string | Name of image pull secret                         |
| global.secrets.storage.azure_blob.secretName | string | Azure Blob credentials secret name                |
| global.secrets.storage.aws_s3.secretName     | string | AWS S3 credentials secret name                    |

### Chart-Specific Parameters

| Key              | Type   | Default                               | Description                                           |
| ---------------- | ------ | ------------------------------------- | ----------------------------------------------------- |
| enabled          | bool   | `true`                                | Enable this subchart (umbrella chart only)            |
| replicaCount     | int    | `1`                                   | Number of replicas to deploy                          |
| image.repository | string | `"ghcr.io/eqtylab/integrity-service"` | Container image repository                            |
| image.pullPolicy | string | `"IfNotPresent"`                      | Image pull policy                                     |
| image.tag        | string | `""`                                  | Overrides the image tag (default is chart appVersion) |
| imagePullSecrets | list   | `[]`                                  | Additional image pull secrets (beyond global)         |

### Service Account

| Key                        | Type   | Default | Description                                                                  |
| -------------------------- | ------ | ------- | ---------------------------------------------------------------------------- |
| serviceAccount.create      | bool   | `false` | Specifies whether a service account should be created                        |
| serviceAccount.automount   | bool   | `true`  | Automatically mount the ServiceAccount's API credentials                     |
| serviceAccount.annotations | object | `{}`    | Annotations to add to the service account                                    |
| serviceAccount.name        | string | `""`    | The name of the service account (generated if serviceAccount.create is true) |

### Security

| Key                                    | Type   | Default | Description                                                       |
| -------------------------------------- | ------ | ------- | ----------------------------------------------------------------- |
| podAnnotations                         | object | `{}`    | Annotations to add to pods                                        |
| podLabels                              | object | `{}`    | Labels to add to pods                                             |
| podSecurityContext                     | object | `{}`    | Security context for the pod                                      |
| securityContext.readOnlyRootFilesystem | bool   | `false` | Read-only root filesystem (disabled for Rust app file operations) |

### Service

| Key             | Type   | Default       | Description                                    |
| --------------- | ------ | ------------- | ---------------------------------------------- |
| service.enabled | bool   | `true`        | Create a Service resource                      |
| service.type    | string | `"ClusterIP"` | Kubernetes service type                        |
| service.port    | int    | `3050`        | Service port exposed by the Kubernetes Service |

### Ingress

| Key                 | Type   | Default                                                                                                                    | Description                 |
| ------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| ingress.enabled     | bool   | `false`                                                                                                                    | Enable ingress              |
| ingress.className   | string | `""`                                                                                                                       | Ingress class name          |
| ingress.annotations | object | `{}`                                                                                                                       | Ingress annotations         |
| ingress.hosts       | list   | `[{"host":"governance.example.com","paths":[{"path":"/integrityService(/\|$)(.*)","pathType":"ImplementationSpecific"}]}]` | Ingress hosts configuration |
| ingress.tls         | list   | `[]`                                                                                                                       | Ingress TLS configuration   |

### Resources

| Key                                           | Type   | Default | Description                          |
| --------------------------------------------- | ------ | ------- | ------------------------------------ |
| resources                                     | object | `{}`    | CPU/Memory resource requests/limits  |
| autoscaling.enabled                           | bool   | `false` | Enable horizontal pod autoscaling    |
| autoscaling.minReplicas                       | int    | `1`     | Minimum number of replicas           |
| autoscaling.maxReplicas                       | int    | `100`   | Maximum number of replicas           |
| autoscaling.targetCPUUtilizationPercentage    | int    | `80`    | Target CPU utilization percentage    |
| autoscaling.targetMemoryUtilizationPercentage | int    | `80`    | Target memory utilization percentage |

> 💡 **Note:** Resources are empty by default. For production, set appropriate requests and limits (recommended: cpu 100m-500m, memory 256Mi-512Mi).

### High Availability

| Key                              | Type | Default | Description                                                                                              |
| -------------------------------- | ---- | ------- | -------------------------------------------------------------------------------------------------------- |
| podDisruptionBudget.enabled      | bool | `false` | Enable Pod Disruption Budget                                                                             |
| podDisruptionBudget.minAvailable | int  | `1`     | Minimum available pods during disruptions (only applied when autoscaling is enabled or replicaCount > 1) |

### Node Scheduling

| Key          | Type   | Default | Description                       |
| ------------ | ------ | ------- | --------------------------------- |
| nodeSelector | object | `{}`    | Node labels for pod assignment    |
| tolerations  | list   | `[]`    | Tolerations for pod assignment    |
| affinity     | object | `{}`    | Affinity rules for pod assignment |

### Health Checks

| Key                                | Type   | Default        | Description                   |
| ---------------------------------- | ------ | -------------- | ----------------------------- |
| startupProbe.httpGet.path          | string | `"/health/v1"` | Startup probe HTTP path       |
| startupProbe.httpGet.port          | string | `"http"`       | Startup probe port            |
| startupProbe.periodSeconds         | int    | `10`           | Startup probe period          |
| startupProbe.failureThreshold      | int    | `30`           | Startup failure threshold     |
| livenessProbe.httpGet.path         | string | `"/health/v1"` | Liveness probe HTTP path      |
| livenessProbe.httpGet.port         | string | `"http"`       | Liveness probe port           |
| livenessProbe.initialDelaySeconds  | int    | `10`           | Liveness probe initial delay  |
| livenessProbe.periodSeconds        | int    | `10`           | Liveness probe period         |
| livenessProbe.failureThreshold     | int    | `3`            | Liveness failure threshold    |
| readinessProbe.httpGet.path        | string | `"/health/v1"` | Readiness probe HTTP path     |
| readinessProbe.httpGet.port        | string | `"http"`       | Readiness probe port          |
| readinessProbe.initialDelaySeconds | int    | `5`            | Readiness probe initial delay |
| readinessProbe.periodSeconds       | int    | `5`            | Readiness probe period        |
| readinessProbe.failureThreshold    | int    | `2`            | Readiness failure threshold   |

### Persistence

| Key                             | Type   | Default                | Description                                                             |
| ------------------------------- | ------ | ---------------------- | ----------------------------------------------------------------------- |
| persistence.enabled             | bool   | `false`                | Enable persistent volume for integrity data                             |
| persistence.integrity.mountPath | string | `"/data/integrity"`    | Container mount path for integrity data                                 |
| persistence.integrity.hostPath  | string | `"/var/lib/integrity"` | Host path for data storage (only used when persistence.enabled is true) |

### Application Configuration

All config values support global fallbacks when deployed via umbrella chart.

#### Application Settings

| Key                        | Type   | Default | Description                                             |
| -------------------------- | ------ | ------- | ------------------------------------------------------- |
| config.rustEnv             | string | `""`    | Rust environment (auto-set from global.environmentType) |
| config.integrityServiceUrl | string | `""`    | Public URL for this service (auto-generated)            |

#### Database Configuration

| Key                           | Type   | Default                | Description                                                 |
| ----------------------------- | ------ | ---------------------- | ----------------------------------------------------------- |
| config.integrityAppDbHost     | string | `""`                   | Database host (auto-generated as {Release.Name}-postgresql) |
| config.integrityAppDbName     | string | `"IntegrityServiceDB"` | Database name                                               |
| config.integrityAppDbUser     | string | `""`                   | Database user (auto-set from global.postgresql.username)    |
| config.integrityAppDbPassword | string | `""`                   | Database password (leave empty to use secret reference)     |

#### Blob Storage Configuration

| Key                                         | Type   | Default | Description                                                     |
| ------------------------------------------- | ------ | ------- | --------------------------------------------------------------- |
| config.integrityAppBlobStoreType            | string | `""`    | Storage provider (aws_s3 or azure_blob, must be set explicitly) |
| config.integrityAppBlobStoreRegion          | string | `""`    | AWS region (AWS S3 only, must be set when using S3)             |
| config.integrityAppBlobStoreBucket          | string | `""`    | AWS S3 bucket name (AWS S3 only, must be set when using S3)     |
| config.integrityAppBlobStoreFolder          | string | `""`    | AWS S3 folder/prefix (AWS S3 only)                              |
| config.integrityAppBlobStoreAccessKeyId     | string | `""`    | AWS access key ID (leave empty to use secret, AWS S3 only)      |
| config.integrityAppBlobStoreSecretAccessKey | string | `""`    | AWS secret access key (leave empty to use secret, AWS S3 only)  |
| config.integrityAppBlobStoreAccount         | string | `""`    | Azure storage account name (Azure Blob only)                    |
| config.integrityAppBlobStoreContainer       | string | `""`    | Azure blob container name (Azure Blob only, must be set)        |
| config.integrityAppBlobStoreKey             | string | `""`    | Azure storage key (leave empty to use secret, Azure Blob only)  |

#### Logging Configuration

| Key                                                | Type   | Default   | Description                                               |
| -------------------------------------------------- | ------ | --------- | --------------------------------------------------------- |
| config.integrityAppLoggingLogLevelDefault          | string | `"warn"`  | Default log level (trace/debug/info/warn/error)           |
| config.integrityAppLoggingLogLevelIntegrityService | string | `"trace"` | Integrity service log level (trace/debug/info/warn/error) |

#### Authentication Configuration

| Key                         | Type   | Default          | Description                       |
| --------------------------- | ------ | ---------------- | --------------------------------- |
| config.integrityAppAuthType | string | `"auth_service"` | Authentication type               |
| config.integrityAppAuthUrl  | string | `""`             | Auth service URL (auto-generated) |

### Secret Configuration

Secrets reference Kubernetes Secret resources created by the umbrella chart or manually.

#### Secret Key Names

Secret key names (the keys within each Kubernetes Secret) follow this pattern:

- **Umbrella chart deployment**: Key names are defined in `global.secrets.*.keys` - this is the single source of truth
- **Standalone deployment**: Templates use hardcoded defaults (e.g., `access-key-id`, `client-id`, `password`)

When deploying standalone, create your secrets using the default key names:

```bash
# Example: Database credentials
kubectl create secret generic integrity-database \
  --from-literal=password=YOUR_PASSWORD

# Example: AWS S3 storage
kubectl create secret generic integrity-aws-s3 \
  --from-literal=access-key-id=YOUR_ACCESS_KEY \
  --from-literal=secret-access-key=YOUR_SECRET_KEY
```

If your existing secrets use different key names, you can override them via `global.secrets.*.keys` in your values file.

**Default key names by secret type:**

| Secret Type | Default Key Names                    |
| ----------- | ------------------------------------ |
| Database    | `password`                           |
| AWS S3      | `access-key-id`, `secret-access-key` |
| Azure Blob  | `account-key`                        |

#### Database Secrets

| Key                   | Type   | Description                              |
| --------------------- | ------ | ---------------------------------------- |
| secrets.database.name | string | Secret name (auto-populated from global) |

#### Storage Secrets

AWS S3 (only used when integrityAppBlobStoreType is "aws_s3"):

| Key                         | Type   | Description                              |
| --------------------------- | ------ | ---------------------------------------- |
| secrets.storage.aws_s3.name | string | Secret name (auto-populated from global) |

Azure Blob Storage (only used when integrityAppBlobStoreType is "azure_blob"):

| Key                             | Type   | Description                              |
| ------------------------------- | ------ | ---------------------------------------- |
| secrets.storage.azure_blob.name | string | Secret name (auto-populated from global) |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level config values** - Explicitly set in `integrity-service.config.*`
2. **Global values** - Set in `global.*` (umbrella chart)
3. **Chart defaults** - Default values from `values.yaml`

### Example Configuration Flow

```yaml
# Umbrella chart values.yaml
global:
  domain: "governance.prod.company.com"
  environmentType: "production"
  postgresql:
    username: "postgres"

integrity-service:
  enabled: true
  # config.rustEnv automatically becomes: production
  # config.integrityAppDbUser automatically becomes: postgres
  # config.integrityAppDbHost automatically becomes: {Release.Name}-postgresql

  # Must explicitly set storage provider:
  config:
    integrityAppBlobStoreType: "azure_blob" # Required - not auto-set
    integrityAppBlobStoreContainer: "integrity-data" # Required - not auto-set
```

## Storage Provider Configuration

### Azure Blob Storage

```yaml
global:
  secrets:
    storage:
      azure_blob:
        secretName: "platform-azure-blob"

integrity-service:
  config:
    integrityAppBlobStoreType: "azure_blob" # Explicitly set storage provider
    integrityAppBlobStoreContainer: "integrity-data" # Must be set
```

### AWS S3

```yaml
global:
  secrets:
    storage:
      aws_s3:
        secretName: "platform-aws-s3"

integrity-service:
  config:
    integrityAppBlobStoreType: "aws_s3" # Explicitly set storage provider
    integrityAppBlobStoreRegion: "us-east-1" # Must be set
    integrityAppBlobStoreBucket: "integrity-data" # Must be set
    integrityAppBlobStoreFolder: "statements"
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
helm upgrade integrity-service eqtylab/integrity-service \
  -f values.yaml \
  --namespace governance
```

## Troubleshooting

### Viewing Logs

```bash
kubectl logs -f deployment/integrity-service -n governance
```

### Checking Pod Status

```bash
kubectl get pods -n governance -l app.kubernetes.io/name=integrity-service
kubectl describe pod <pod-name> -n governance
```

### Testing Configuration

View environment variables in running pod:

```bash
kubectl exec -it deployment/integrity-service -n governance -- env | grep INTEGRITY_APP
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
- Ensure database `IntegrityServiceDB` exists
- Verify network policies allow traffic between services

**Storage errors**

- Verify storage provider is explicitly set via `integrityAppBlobStoreType`
- Check storage credentials in secret
- For Azure: verify account name and container exist, container name must be set explicitly
- For AWS: verify bucket exists, region and bucket name must be set explicitly
- Ensure service has network access to storage

**Authentication fails**

- Verify auth service is running and accessible
- Check `integrityAppAuthUrl` points to correct service
- Ensure auth service URL is reachable from integrity service pods

**Configuration not applying**

- Remember: service-level config overrides global config
- Check for typos in global value paths
- Restart pods if configuration was updated: `kubectl rollout restart deployment/integrity-service -n governance`

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://docs.eqtylab.io
- GitHub: https://github.com/eqtylab/governance-studio-infrastructure
