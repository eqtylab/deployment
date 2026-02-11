# Integrity Service

A Helm chart for deploying the EQTY Lab Integrity Service on Kubernetes.

## Description

The Integrity Service provides verifiable credentials, data lineage tracking, and statement registry capabilities for the Governance Platform.

Key capabilities:

- **Verifiable Credentials**: Issue and verify W3C-compliant credentials
- **Data Lineage**: Track provenance and transformation history of data assets
- **Statement Registry**: Store and retrieve signed integrity statements
- **Blob Storage Integration**: Azure Blob Storage, AWS S3, and Google Cloud Storage support for artifact persistence

## Configuration Model

Integrity Service uses runtime configuration injected via environment variables. Application configuration is provided through Helm values and injected into the container at startup.

This allows:

- A single immutable container image across environments
- Configuration changes without rebuilding images
- Clear separation of infrastructure and application settings
- Automatic configuration inheritance from umbrella chart globals

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- PostgreSQL database (provided by umbrella chart or external)
- Azure Blob Storage, AWS S3, or Google Cloud Storage account (with container/bucket created)
- Ingress controller (NGINX, Traefik, etc.)
- TLS certificates (manual or via cert-manager)

## Deployment

When deployed via the `governance-platform` umbrella chart, Integrity Service automatically inherits configuration from global values with no additional configuration required.

### Quick Start

Minimum configuration required in your umbrella chart values:

**Azure Blob Storage:**

```yaml
integrity-service:
  image:
    tag: ""
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/rewrite-target: "/$2"
      nginx.ingress.kubernetes.io/proxy-body-size: "0"
    hosts:
      - host: "governance.yourcompany.com"
        paths:
          - path: "/integrityService(/|$)(.*)"
            pathType: "ImplementationSpecific"
    tls:
      - secretName: "integrity-service-tls"
        hosts:
          - "governance.yourcompany.com"
  config:
    integrityAppBlobStoreType: "azure_blob"
    integrityAppBlobStoreAccount: "your-storage-account"
    integrityAppBlobStoreContainer: "your-integrity-store-container"
```

**AWS S3:**

```yaml
integrity-service:
  image:
    tag: ""
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/rewrite-target: "/$2"
      nginx.ingress.kubernetes.io/proxy-body-size: "0"
    hosts:
      - host: "governance.yourcompany.com"
        paths:
          - path: "/integrityService(/|$)(.*)"
            pathType: "ImplementationSpecific"
    tls:
      - secretName: "integrity-service-tls"
        hosts:
          - "governance.yourcompany.com"
  config:
    integrityAppBlobStoreType: "aws_s3"
    integrityAppBlobStoreAwsRegion: "us-east-1"
    integrityAppBlobStoreAwsBucket: "your-integrity-store-bucket"
    integrityAppBlobStoreAwsFolder: "your-integrity-store-folder"
```

**Google Cloud Storage:**

```yaml
integrity-service:
  image:
    tag: ""
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/rewrite-target: "/$2"
      nginx.ingress.kubernetes.io/proxy-body-size: "0"
    hosts:
      - host: "governance.yourcompany.com"
        paths:
          - path: "/integrityService(/|$)(.*)"
            pathType: "ImplementationSpecific"
    tls:
      - secretName: "integrity-service-tls"
        hosts:
          - "governance.yourcompany.com"
  config:
    integrityAppBlobStoreType: "gcs"
    integrityAppBlobStoreGcsBucket: "your-integrity-store-bucket"
    integrityAppBlobStoreGcsFolder: "your-integrity-store-folder"
```

### Required Configuration

Beyond what is auto-configured, these values **must** be explicitly set:

**Azure Blob Storage:**

- `config.integrityAppBlobStoreType` - Set to `"azure_blob"`
- `config.integrityAppBlobStoreAccount` - Azure storage account name (e.g., `your-storage-account`)
- `config.integrityAppBlobStoreContainer` - Azure blob container name (e.g., `your-integrity-store-container`)

**AWS S3:**

- `config.integrityAppBlobStoreType` - Set to `"aws_s3"`
- `config.integrityAppBlobStoreAwsRegion` - AWS region (e.g., `us-east-1`)
- `config.integrityAppBlobStoreAwsBucket` - S3 bucket name (e.g., `your-integrity-store-bucket`)
- `config.integrityAppBlobStoreAwsFolder` - S3 folder/prefix (e.g., `your-integrity-store-folder`)

**Google Cloud Storage:**

- `config.integrityAppBlobStoreType` - Set to `"gcs"`
- `config.integrityAppBlobStoreGcsBucket` - GCS bucket name (e.g., `your-integrity-store-bucket`)
- `config.integrityAppBlobStoreGcsFolder` - GCS folder/prefix (e.g., `your-integrity-store-folder`)

**What gets auto-configured:**

From global values:

- Database connection (host, port, credentials from `global.postgresql.*` and `global.secrets.database`)
- Storage credentials (from `global.secrets.storage.azure_blob`, `global.secrets.storage.aws_s3`, or `global.secrets.storage.gcs`)
- Auth service URL (generated as `http://{Release.Name}-auth-service:8080`)
- Environment type (from `global.environmentType`)
- Image pull secrets (from `global.secrets.imageRegistry`)
- Public service URL (from `global.domain`)

Generated defaults:

- Database host defaults to `{Release.Name}-postgresql` (co-deployed PostgreSQL)
- Integrity service URL defaults to `https://{global.domain}/integrityService`

## Values

### Global Parameters (Umbrella Chart)

When deployed via the umbrella chart, these global values are automatically used:

| Key                                          | Type   | Description                                             |
| -------------------------------------------- | ------ | ------------------------------------------------------- |
| global.domain                                | string | Base domain for all services                            |
| global.environmentType                       | string | Environment type (development/staging/production)       |
| global.postgresql.host                       | string | PostgreSQL host (defaults to {Release.Name}-postgresql) |
| global.postgresql.port                       | int    | PostgreSQL port (defaults to 5432)                      |
| global.postgresql.database                   | string | PostgreSQL database name                                |
| global.postgresql.username                   | string | PostgreSQL username                                     |
| global.secrets.database.secretName           | string | Name of database credentials secret                     |
| global.secrets.imageRegistry.secretName      | string | Name of image pull secret                               |
| global.secrets.storage.azure_blob.secretName | string | Azure Blob credentials secret name                      |
| global.secrets.storage.aws_s3.secretName     | string | AWS S3 credentials secret name                          |
| global.secrets.storage.gcs.secretName        | string | GCS credentials secret name                             |

### Chart-Specific Parameters

| Key              | Type   | Default                               | Description                                           |
| ---------------- | ------ | ------------------------------------- | ----------------------------------------------------- |
| enabled          | bool   | `true`                                | Enable this subchart (umbrella chart only)            |
| replicaCount     | int    | `2`                                   | Number of replicas to deploy                          |
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

> **Note:** Resources are empty by default. For production, set appropriate requests and limits (recommended: cpu 100m-500m, memory 256Mi-512Mi).

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

### Database Configuration

| Key                           | Type   | Default                | Description                                                      |
| ----------------------------- | ------ | ---------------------- | ---------------------------------------------------------------- |
| config.integrityAppDbHost     | string | `""`                   | Database host (auto-generated as {Release.Name}-postgresql)      |
| config.integrityAppDbPort     | string | `""`                   | Database port (auto-configured from global.postgresql.port)      |
| config.integrityAppDbName     | string | `"IntegrityServiceDB"` | Database name                                                    |
| config.integrityAppDbUser     | string | `""`                   | Database user (auto-configured from global.postgresql.username)  |
| config.integrityAppDbPassword | string | `""`                   | Database password (auto-configured from global.secrets.database) |

### Secret Configuration

All secret references support global fallbacks when deployed via umbrella chart.

#### Database Secrets

| Key                   | Type   | Description                                                           |
| --------------------- | ------ | --------------------------------------------------------------------- |
| secrets.database.name | string | Secret name (auto-configured from global.secrets.database.secretName) |

#### Storage Secrets

AWS S3 (only used when integrityAppBlobStoreType is "aws_s3"):

| Key                         | Type   | Description                                                                 |
| --------------------------- | ------ | --------------------------------------------------------------------------- |
| secrets.storage.aws_s3.name | string | Secret name (auto-configured from global.secrets.storage.aws_s3.secretName) |

Azure Blob Storage (only used when integrityAppBlobStoreType is "azure_blob"):

| Key                             | Type   | Description                                                                     |
| ------------------------------- | ------ | ------------------------------------------------------------------------------- |
| secrets.storage.azure_blob.name | string | Secret name (auto-configured from global.secrets.storage.azure_blob.secretName) |

Google Cloud Storage (only used when integrityAppBlobStoreType is "gcs"):

| Key                      | Type   | Description                                                              |
| ------------------------ | ------ | ------------------------------------------------------------------------ |
| secrets.storage.gcs.name | string | Secret name (auto-configured from global.secrets.storage.gcs.secretName) |

### Application Configuration

All config values support global fallbacks when deployed via umbrella chart.

#### Application Settings

| Key                        | Type   | Default               | Description                                                                                |
| -------------------------- | ------ | --------------------- | ------------------------------------------------------------------------------------------ |
| config.rustEnv             | string | `""`                  | Rust environment (auto-configured from global.environmentType)                             |
| config.integrityServiceUrl | string | `""`                  | Public URL for this service (auto-generated as `https://{global.domain}/integrityService`) |
| config.swaggerBasePath     | string | `"/integrityService"` | Base path for Swagger UI                                                                   |

#### Blob Storage Configuration

| Key                                            | Type   | Default | Description                                                                |
| ---------------------------------------------- | ------ | ------- | -------------------------------------------------------------------------- |
| config.integrityAppBlobStoreType               | string | `""`    | Storage provider (**must be set**; `aws_s3`, `azure_blob`, or `gcs`)       |
| config.integrityAppBlobStoreAwsRegion          | string | `""`    | AWS region (**must be set** when using S3)                                 |
| config.integrityAppBlobStoreAwsBucket          | string | `""`    | AWS S3 bucket name (**must be set** when using S3)                         |
| config.integrityAppBlobStoreAwsFolder          | string | `""`    | AWS S3 folder/prefix (**must be set** when using S3)                       |
| config.integrityAppBlobStoreAwsAccessKeyId     | string | `""`    | AWS access key ID (auto-configured from global.secrets.storage.aws_s3)     |
| config.integrityAppBlobStoreAwsSecretAccessKey | string | `""`    | AWS secret access key (auto-configured from global.secrets.storage.aws_s3) |
| config.integrityAppBlobStoreAccount            | string | `""`    | Azure storage account name (**must be set** when using Azure Blob)         |
| config.integrityAppBlobStoreContainer          | string | `""`    | Azure blob container name (**must be set** when using Azure Blob)          |
| config.integrityAppBlobStoreKey                | string | `""`    | Azure storage key (auto-configured from global.secrets.storage.azure_blob) |
| config.integrityAppBlobStoreGcsBucket          | string | `""`    | GCS bucket name (**must be set** when using GCS)                           |
| config.integrityAppBlobStoreGcsFolder          | string | `""`    | GCS folder/prefix (**must be set** when using GCS)                         |

#### Logging Configuration

| Key                                                | Type   | Default   | Description                                               |
| -------------------------------------------------- | ------ | --------- | --------------------------------------------------------- |
| config.integrityAppLoggingLogLevelDefault          | string | `"warn"`  | Default log level (trace/debug/info/warn/error)           |
| config.integrityAppLoggingLogLevelIntegrityService | string | `"trace"` | Integrity service log level (trace/debug/info/warn/error) |

#### Authentication Configuration

| Key                         | Type   | Default          | Description                                                                  |
| --------------------------- | ------ | ---------------- | ---------------------------------------------------------------------------- |
| config.integrityAppAuthType | string | `"auth_service"` | Authentication type                                                          |
| config.integrityAppAuthUrl  | string | `""`             | Auth service URL (auto-generated as http://{Release.Name}-auth-service:8080) |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level config values** - Explicitly set in `integrity-service.config.*`
2. **Global values** - Set in `global.*` (umbrella chart)
3. **Chart defaults** - Default values from `values.yaml`

## Azure Blob Storage Configuration

### Required Azure Setup

1. **Create an Azure Storage Account**
2. **Create a Blob Container** for integrity artifacts (e.g., `integrity-data`)
3. **Obtain account credentials** (account name, account key, connection string)

### Example Configuration

```yaml
integrity-service:
  config:
    integrityAppBlobStoreType: "azure_blob"
    integrityAppBlobStoreAccount: "your-storage-account"
    integrityAppBlobStoreContainer: "your-integrity-store-container"

secrets:
  storage:
    azure_blob:
      name: "platform-azure-blob"
```

### Secret Creation

```bash
kubectl create secret generic platform-azure-blob \
  --from-literal=account-key=YOUR_AZURE_STORAGE_ACCOUNT_KEY \
  --from-literal=connection-string="DefaultEndpointsProtocol=https;..." \
  --namespace governance
```

## AWS S3 Configuration

### Required AWS Setup

1. **Create an S3 Bucket** for integrity artifacts (e.g., `integrity-data`)
2. **Create an IAM User or Role** with S3 access to the bucket
3. **Obtain credentials** (access key ID, secret access key)

### Example Configuration

```yaml
integrity-service:
  config:
    integrityAppBlobStoreType: "aws_s3"
    integrityAppBlobStoreAwsRegion: "us-east-1"
    integrityAppBlobStoreAwsBucket: "your-integrity-store-bucket"
    integrityAppBlobStoreAwsFolder: "your-integrity-store-folder"

secrets:
  storage:
    aws_s3:
      name: "platform-aws-s3"
```

### Secret Creation

```bash
kubectl create secret generic platform-aws-s3 \
  --from-literal=access-key-id=YOUR_AWS_ACCESS_KEY \
  --from-literal=secret-access-key=YOUR_AWS_SECRET_KEY \
  --namespace governance
```

## Google Cloud Storage Configuration

### Required GCS Setup

1. **Create a GCS Bucket** for integrity artifacts (e.g., `integrity-data`)
2. **Create a Service Account** with Storage Object Admin access to the bucket
3. **Export a JSON key** for the service account

### Example Configuration

```yaml
integrity-service:
  config:
    integrityAppBlobStoreType: "gcs"
    integrityAppBlobStoreGcsBucket: "your-integrity-store-bucket"
    integrityAppBlobStoreGcsFolder: "your-integrity-store-folder"

secrets:
  storage:
    gcs:
      name: "platform-gcs"
```

### Secret Creation

```bash
kubectl create secret generic platform-gcs \
  --from-file=service-account-json=YOUR_SERVICE_ACCOUNT_KEY.json \
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

### Verifying Configuration

View key environment variables in the running pod:

```bash
kubectl exec -it deployment/integrity-service -n governance -- env | grep INTEGRITY_APP
```

View all environment variables:

```bash
kubectl exec -it deployment/integrity-service -n governance -- env | sort
```

Test health endpoint:

```bash
kubectl exec -it deployment/integrity-service -n governance -- curl -s localhost:3050/health/v1
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
- For GCS: verify bucket exists, service account JSON key is mounted correctly
- Ensure service has network access to storage

**Authentication fails**

- Verify auth service is running and accessible
- Check `integrityAppAuthUrl` points to correct service
- Ensure auth service URL is reachable from integrity service pods

**Configuration not applying**

- Remember: service-level config overrides global config
- Check for typos in global value paths
- Restart pods if configuration was updated: `kubectl rollout restart deployment/integrity-service -n governance`

## Health Endpoints

| Endpoint         | Description          |
| ---------------- | -------------------- |
| `GET /health/v1` | Overall health check |

### API Documentation

Swagger UI is available at:

```
https://{domain}/integrityService/swagger/index.html
```

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://docs.eqtylab.io
- GitHub: https://github.com/eqtylab/governance-studio-infrastructure
