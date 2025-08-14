# Governance Platform Umbrella Chart

This Helm chart deploys the complete Governance Platform, including all necessary components and dependencies.

## Components

The Governance Platform consists of the following components:

1. **Compliance Service** - A compliance management system for governance processes
2. **Governance Service** - A service for validating and analyzing governance data
3. **Integrity Service** - A service for ensuring data integrity and auditability
4. **Governance UI** - A user interface for managing governance processes
5. **PostgreSQL** - Database used by all services
6. **Redis** - Cache/message broker used by Compliance Garage

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- Persistent volume provisioner support in the underlying infrastructure
- **Ingress Controller** (see [Ingress Requirements](#ingress-requirements) below)
- **TLS Certificate Management** (see [TLS Configuration](#tls-configuration) below)
- Secrets created in the cluster (see below)

## Ingress Requirements

This chart **assumes you have an ingress controller already installed** in your cluster. The chart is configured by default to use:

- **NGINX Ingress Controller** (`global.ingress.className: "nginx"`)
- **cert-manager** for automatic TLS certificate management

### Supported Ingress Controllers

While the chart defaults to NGINX, you can use any ingress controller by configuring the appropriate class:

```yaml
global:
  ingress:
    className: "traefik" # or "alb", "gce", etc.
    annotations:
      # Remove cert-manager annotations if not using cert-manager
      # cert-manager.io/issuer: letsencrypt-prod
```

### Installing NGINX Ingress Controller (Optional)

If you don't have an ingress controller installed, you can install NGINX Ingress Controller:

```bash
# Install NGINX Ingress Controller
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

## TLS Configuration

The chart assumes you have a TLS certificate management solution. There are several options:

### Option 1: cert-manager (Recommended)

Install cert-manager for automatic certificate management:

```bash
# Install cert-manager
helm install cert-manager cert-manager \
  --repo https://charts.jetstack.io \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

# Create a ClusterIssuer for Let's Encrypt
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### Option 2: Manual TLS Secrets

If you prefer to manage TLS certificates manually, create the TLS secret before installing:

```bash
# Create TLS secret with your certificates
kubectl create secret tls platform-tls \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  --namespace governance-prod

# Configure the chart to use your secret
helm install governance-platform ./charts/governance-platform \
  --set global.ingress.tlsSecretName=platform-tls \
  --set global.ingress.annotations=null \
  --namespace governance-prod
```

### Option 3: Disable TLS

For development environments, you can disable TLS entirely:

```yaml
global:
  ingress:
    annotations:
      # Remove cert-manager annotations
    tls: []
```

## Secret Management

The chart requires several secrets to function properly. You have two options for managing these secrets:

### Option 1: Automatic Secret Creation

The chart can automatically create the required secrets during installation. To use this feature:

1. Set `global.secrets.createSecrets` to `true` in your values file
2. Provide the secret values in your values file or through `--set` parameters

**Example using a secrets values file (recommended for security):**

A sample secrets template file is provided at `secrets-sample.yaml`. You can use this as a starting point:

```bash
# Copy and customize the sample secrets file
cp secrets-sample.yaml my-secrets.yaml
# Edit my-secrets.yaml with your actual secret values
vim my-secrets.yaml

# Install the chart with your secrets file
helm install governance-platform ./charts/governance-platform \
  --create-namespace \
  --namespace governance-dev \
  --values values-dev.yaml \
  --values my-secrets.yaml
```

> **IMPORTANT**: Never check your actual secrets file into version control. Add `*-secrets.yaml` to your `.gitignore` file.

### Option 2: Manually Created Secrets

Alternatively, you can create the secrets manually before installing the chart:

1. Create the following secrets in your Kubernetes cluster:

   - `compliance-secrets` - Contains database credentials and API keys
   - `auth0-secret` - Authentication credentials
   - `blob-secret` - Cloud storage credentials
   - `azure-kv-secret` - Azure Key Vault credentials (if using Azure)
   - `hf-secret` - Hugging Face credentials
   - `platform-encryption` - Encryption keys
   - `ghcr-pull-secret` - Image pull credentials for GitHub Container Registry

2. Set `global.secrets.createSecrets` to `false` in your values file

3. Ensure the secret names match those specified in your values file under `global.secrets.*`

## Installation

### Install the chart

#### Local Development (using charts from filesystem)

For local development, you can use the chart directly from the repository:

```bash
# Update dependencies from local filesystem
helm dependency update ./charts/governance-platform

# Install using local charts
helm install governance-platform ./charts/governance-platform \
  --create-namespace \
  --namespace governance-dev \
  --values values-dev.yaml
```

#### Production Installation (using OCI registry)

For production deployments, it's recommended to use the OCI registry:

```bash
# Optional: Login to GitHub Container Registry
export CR_PAT=YOUR_GITHUB_TOKEN
echo $CR_PAT | helm registry login ghcr.io -u USERNAME --password-stdin

# Install from OCI registry
helm install governance-platform oci://ghcr.io/eqtylab/charts/governance-platform/governance-platform \
  --version 0.1.0 \
  --create-namespace \
  --namespace governance-prod \
  --values values-prod.yaml
```

## Configuration

### Global Parameters

| Parameter                    | Description                                         | Default                    |
| ---------------------------- | --------------------------------------------------- | -------------------------- |
| `global.environmentType`     | Environment type (development, staging, production) | `"production"`             |
| `global.domain`              | Base domain for ingress hostnames                   | `"governance.example.com"` |
| `global.imagePullPolicy`     | Default pull policy for images                      | `"IfNotPresent"`           |
| `global.defaultStorageClass` | Default storage class for PVCs                      | `""` (use cluster default) |

### Global Database Configuration

| Parameter                    | Description           | Default                              |
| ---------------------------- | --------------------- | ------------------------------------ |
| `global.postgresql.host`     | PostgreSQL hostname   | `"{{ .Release.Name }}-postgresql"`   |
| `global.postgresql.port`     | PostgreSQL port       | `5432`                               |
| `global.postgresql.database` | Default database name | `"governance"`                       |
| `global.postgresql.username` | PostgreSQL username   | `"postgres"`                         |
| `global.redis.host`          | Redis hostname        | `"{{ .Release.Name }}-redis-master"` |
| `global.redis.port`          | Redis port            | `6379`                               |

### Global Ingress Configuration

> **Note**: These settings assume you have an ingress controller installed. See [Ingress Requirements](#ingress-requirements) for details.

| Parameter                      | Description                        | Default                    |
| ------------------------------ | ---------------------------------- | -------------------------- |
| `global.ingress.enabled`       | Enable ingress for external access | `true`                     |
| `global.ingress.className`     | Ingress controller class ⚠️        | `"nginx"`                  |
| `global.ingress.host`          | Base domain for all services       | `"governance.example.com"` |
| `global.ingress.tlsSecretName` | TLS secret name ⚠️                 | `"platform-tls"`           |
| `global.ingress.annotations`   | Ingress annotations ⚠️             | See values.yaml            |

⚠️ **Requires external dependencies**:

- `className`: Requires NGINX Ingress Controller (or change to your ingress controller)
- `tlsSecretName`: Requires TLS secret (manual or cert-manager managed)
- `annotations`: Default annotations assume cert-manager is installed

### Global Resource Configuration

| Parameter                                 | Description            | Default   |
| ----------------------------------------- | ---------------------- | --------- |
| `global.defaultResources.requests.cpu`    | Default CPU request    | `"100m"`  |
| `global.defaultResources.requests.memory` | Default memory request | `"256Mi"` |
| `global.defaultResources.limits.cpu`      | Default CPU limit      | `"500m"`  |
| `global.defaultResources.limits.memory`   | Default memory limit   | `"512Mi"` |

### Secret Management Configuration

| Parameter                                | Description                                    | Default                 |
| ---------------------------------------- | ---------------------------------------------- | ----------------------- |
| `global.secrets.createSecrets`           | Whether to automatically create secrets        | `true`                  |
| `global.secrets.complianceSecretName`    | Name of the Compliance Garage secret           | `"compliance-secrets"`  |
| `global.secrets.auth0SecretName`         | Name of the Auth0 credentials secret           | `"auth0-secret"`        |
| `global.secrets.blobStoreSecretName`     | Name of the blob storage credentials secret    | `"blob-secret"`         |
| `global.secrets.azureKVSecretName`       | Name of the Azure Key Vault credentials secret | `"azure-kv-secret"`     |
| `global.secrets.huggingFaceSecretName`   | Name of the Hugging Face token secret          | `"hf-secret"`           |
| `global.secrets.encryptionKeySecretName` | Name of the platform encryption secret         | `"platform-encryption"` |
| `global.secrets.imagePullSecretName`     | Name of the image pull secret                  | `"ghcr-pull-secret"`    |
| `global.secrets.openaiSecretName`        | Name of the OpenAI API secret                  | `"openai-secret"`       |

### Compliance Garage Configuration

| Parameter                                                 | Description                        | Default                                              |
| --------------------------------------------------------- | ---------------------------------- | ---------------------------------------------------- |
| `compliance-garage.enabled`                               | Enable Compliance Garage component | `true`                                               |
| `compliance-garage.compliance-api.replicaCount`           | Number of API replicas             | `1`                                                  |
| `compliance-garage.compliance-api.image.repository`       | API container image repository     | `"ghcr.io/eqtylab/compliance-garage/compliance-api"` |
| `compliance-garage.compliance-api.image.tag`              | API container image tag            | `"latest-20250506-132949"`                           |
| `compliance-garage.compliance-worker.replicaCount`        | Number of worker replicas          | `1`                                                  |
| `compliance-garage.compliance-worker.persistence.enabled` | Enable worker persistent storage   | `true`                                               |
| `compliance-garage.compliance-worker.persistence.size`    | Worker storage size                | `"5Gi"`                                              |
| `compliance-garage.complianceCoordinator.replicaCount`    | Number of coordinator replicas     | `1`                                                  |
| `compliance-garage.complianceProcessor.replicaCount`      | Number of processor replicas       | `1`                                                  |
| `compliance-garage.complianceProcessor.persistence.size`  | Processor storage size             | `"1Gi"`                                              |

### Governance Service Configuration

| Parameter                                       | Description                         | Default                                           |
| ----------------------------------------------- | ----------------------------------- | ------------------------------------------------- |
| `governance-service.enabled`                    | Enable Governance Service component | `true`                                            |
| `governance-service.replicaCount`               | Number of replicas                  | `1`                                               |
| `governance-service.image.repository`           | Container image repository          | `"ghcr.io/eqtylab/governance-service"`            |
| `governance-service.image.tag`                  | Container image tag                 | `"sha-fb520fe"`                                   |
| `governance-service.ingress.enabled`            | Enable ingress                      | `true`                                            |
| `governance-service.externalDatabase.host`      | External database host              | `"governance-platform-postgresql"`                  |
| `governance-service.externalDatabase.database`  | Database name                       | `"governance"`                                    |
| `governance-service.migrations.runAtStartup`    | Run migrations at startup           | `true`                                            |
| `governance-service.config.gcsBucketName`       | GCS bucket for attachments          | `"gov-studio-prod-attachments"`                   |
| `governance-service.config.auth0Domain`         | Auth0 domain                        | `"governance-platform.us.auth0.com"`                |
| `governance-service.config.integrityServiceUrl` | Integrity service URL               | `"http://governance-platform-integrity-service:80"` |
| `governance-service.auth0SyncAtStartup`         | Sync Auth0 users at startup         | `true`                                            |

### Governance Studio Configuration

| Parameter                                        | Description                    | Default                                              |
| ------------------------------------------------ | ------------------------------ | ---------------------------------------------------- |
| `governance-studio.enabled`                      | Enable Governance Studio component | `true`                                               |
| `governance-studio.replicaCount`                 | Number of replicas             | `1`                                                  |
| `governance-studio.image.repository`             | Container image repository     | `"ghcr.io/eqtylab/verify-frontend"`                  |
| `governance-studio.image.tag`                    | Container image tag            | `"latest"`                                           |
| `governance-studio.config.apiUrl`                | Backend API URL                | `"https://governance.example.com/governanceService"` |
| `governance-studio.config.auth0Domain`           | Auth0 domain                   | `"governance-studio.us.auth0.com"`                   |
| `governance-studio.config.auth0ClientId`         | Auth0 client ID                | `"your_auth0_client_id"`                             |
| `governance-studio.config.environment`           | Application environment        | `"production"`                                       |
| `governance-studio.config.appTitle`              | Application title              | `"Governance Studio"`                                |
| `governance-studio.config.features.compliance`   | Enable compliance features     | `true`                                               |
| `governance-studio.config.features.governance`   | Enable governance features     | `true`                                               |
| `governance-studio.config.features.guardian`     | Enable guardian features       | `true`                                               |
| `governance-studio.config.features.lineage`      | Enable lineage features        | `true`                                               |
| `governance-studio.config.branding.logoUrl`      | Company logo URL               | `"/vite.svg"`                                        |
| `governance-studio.config.branding.primaryColor` | Primary brand color            | `"#0f172a"`                                          |
| `governance-studio.config.branding.companyName`  | Company name                   | `"EQTY Lab"`                                         |

### Integrity Service Configuration

| Parameter                                              | Description                        | Default                                             |
| ------------------------------------------------------ | ---------------------------------- | --------------------------------------------------- |
| `integrity-service.enabled`                            | Enable Integrity Service component | `true`                                              |
| `integrity-service.deployment.replicaCount`            | Number of replicas                 | `1`                                                 |
| `integrity-service.image.repository`                   | Container image repository         | `"ghcr.io/eqtylab"`                                 |
| `integrity-service.image.name`                         | Container image name               | `"integrity-service"`                               |
| `integrity-service.image.tag`                          | Container image tag                | `"61c5345"`                                         |
| `integrity-service.env.integrityDbHost`                | Database host                      | `"{{ .Release.Name }}-postgresql"`                  |
| `integrity-service.env.integrityDbName`                | Database name                      | `"IntegrityServiceDB"`                              |
| `integrity-service.env.integrityAppBlobStoreType`      | Blob storage type                  | `"azure_blob"`                                      |
| `integrity-service.env.integrityAppBlobStoreAccount`   | Azure storage account              | `"govstudiostagstorageacct"`                        |
| `integrity-service.env.integrityAppBlobStoreContainer` | Azure blob container               | `"rootstore"`                                       |
| `integrity-service.env.integrityServiceUrl`            | Service URL                        | `"https://governance.example.com/integrityService"` |
| `integrity-service.service.port`                       | Service port                       | `80`                                                |
| `integrity-service.service.targetPort`                 | Container port                     | `3050`                                              |

### PostgreSQL Configuration

| Parameter                                          | Description                | Default                                               |
| -------------------------------------------------- | -------------------------- | ----------------------------------------------------- |
| `postgresql.enabled`                               | Enable PostgreSQL database | `true`                                                |
| `postgresql.global.postgresql.auth.database`       | Database name              | `"governance"`                                        |
| `postgresql.global.postgresql.auth.username`       | Database username          | `"postgres"`                                          |
| `postgresql.global.postgresql.auth.existingSecret` | Existing secret name       | `"{{ .Values.global.secrets.complianceSecretName }}"` |
| `postgresql.primary.persistence.enabled`           | Enable persistence         | `true`                                                |
| `postgresql.primary.persistence.size`              | Storage size               | `10Gi`                                                |
| `postgresql.primary.resources.requests.cpu`        | CPU request                | `500m`                                                |
| `postgresql.primary.resources.requests.memory`     | Memory request             | `1Gi`                                                 |
| `postgresql.primary.resources.limits.cpu`          | CPU limit                  | `2000m`                                               |
| `postgresql.primary.resources.limits.memory`       | Memory limit               | `2Gi`                                                 |

### Redis Configuration

| Parameter                                | Description                       | Default                                               |
| ---------------------------------------- | --------------------------------- | ----------------------------------------------------- |
| `redis.enabled`                          | Enable Redis cache/message broker | `true`                                                |
| `redis.auth.enabled`                     | Enable Redis authentication       | `false`                                               |
| `redis.auth.existingSecret`              | Existing secret name              | `"{{ .Values.global.secrets.complianceSecretName }}"` |
| `redis.master.persistence.enabled`       | Enable master persistence         | `false`                                               |
| `redis.master.persistence.size`          | Master storage size               | `8Gi`                                                 |
| `redis.master.resources.requests.cpu`    | CPU request                       | `200m`                                                |
| `redis.master.resources.requests.memory` | Memory request                    | `512Mi`                                               |
| `redis.master.resources.limits.cpu`      | CPU limit                         | `500m`                                                |
| `redis.master.resources.limits.memory`   | Memory limit                      | `1Gi`                                                 |
| `redis.replica.replicaCount`             | Number of Redis replicas          | `0`                                                   |

### Advanced Configuration Examples

#### Custom Domain Configuration

```yaml
global:
  domain: "governance.yourcompany.com"
  ingress:
    host: "governance.yourcompany.com"
    tlsSecretName: "yourcompany-tls"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod" # Requires cert-manager
```

#### Alternative Ingress Controller Configuration

```yaml
global:
  ingress:
    className: "traefik" # Using Traefik instead of NGINX
    annotations:
      traefik.ingress.kubernetes.io/router.tls: "true"
      # Remove cert-manager annotations if not using cert-manager
```

#### Manual TLS Configuration

```yaml
global:
  ingress:
    tlsSecretName: "my-custom-tls-secret"
    annotations:
      # Remove all cert-manager related annotations
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/enable-cors: "true"
      nginx.ingress.kubernetes.io/proxy-body-size: "64m"
```

#### Production Resource Configuration

```yaml
global:
  defaultResources:
    requests:
      cpu: "250m"
      memory: "512Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"

postgresql:
  primary:
    resources:
      requests:
        cpu: 1000m
        memory: 2Gi
      limits:
        cpu: 4000m
        memory: 4Gi
```

#### High Availability Configuration

```yaml
compliance-garage:
  compliance-api:
    replicaCount: 3
  compliance-worker:
    replicaCount: 2

governance-service:
  replicaCount: 2

governance-studio:
  replicaCount: 3

redis:
  replica:
    replicaCount: 1
```

#### Custom Storage Configuration

```yaml
global:
  defaultStorageClass: "fast-ssd"

postgresql:
  primary:
    persistence:
      size: 50Gi
      storageClass: "fast-ssd"

compliance-garage:
  compliance-worker:
    persistence:
      size: 20Gi
      storageClass: "standard"
```

## Environment-Specific Values Files

This chart comes with environment-specific values files:

- `values.yaml` - Default values
- `values-prod.yaml` - Production environment values
- `values-stag.yaml` - Staging environment values
- `values-dev.yaml` - Development environment values

## Ingress Configuration

This chart uses path-based routing with rewrite rules, allowing all services to be accessed through a single domain. The default configuration is:

- Compliance Service API: `https://<domain>/complianceService/...`
- Governance Service API: `https://<domain>/governanceService/...`
- Integrity Service: `https://<domain>/integrityService/...`

## Architecture

The Governance Platform uses a microservices architecture with the following components:

- **Compliance Service** - Contains API, Worker, Coordinator, and Processor services
- **Governance Service** - Provides the governance API endpoints and processing system
- **Integrity Service** - Handles data integrity and blockchain validation
- **PostgreSQL** - Shared database across services
- **Redis** - Message broker for Compliance Garage components

## Upgrading

To upgrade the chart to a new version:

### Local Development

```bash
# Update dependencies from local filesystem
helm dependency update ./charts/governance-platform

# Upgrade using local charts
helm upgrade governance-platform ./charts/governance-platform \
  --namespace governance-dev \
  --values values-dev.yaml \
  --values my-secrets.yaml
```

### Staging Environment

```bash
# Update dependencies
helm dependency update ./charts/governance-platform

# Upgrade staging deployment
helm upgrade governance-platform ./charts/governance-platform \
  --namespace governance-stag \
  --values values-stag.yaml \
  --values my-secrets.yaml
```

### Production Environment

```bash
# Upgrade using OCI registry (recommended for production)
helm upgrade governance-platform oci://ghcr.io/eqtylab/charts/governance-platform/governance-platform \
  --version 0.1.1 \
  --namespace governance-prod \
  --values values-prod.yaml \
  --values my-secrets.yaml
```

### Upgrade Best Practices

1. **Backup Database**: Always backup your PostgreSQL database before upgrading
2. **Test in Staging**: Test the upgrade in a staging environment first
3. **Check Breaking Changes**: Review the CHANGELOG for any breaking changes
4. **Rolling Updates**: The chart supports rolling updates with zero downtime
5. **Version Pinning**: Use specific chart versions in production rather than latest

## Monitoring and Health Checks

### Health Check Endpoints

Each service provides health check endpoints for monitoring:

- **Compliance Service API**: `GET /health`
- **Governance Service API**: `GET /health`
- **Integrity Service API**: `GET /health`
- **Governance UI**: `GET /health` (via nginx)

### Monitoring Commands

```bash
# Check all pods status
kubectl get pods -n governance-prod

# Check specific service logs
kubectl logs -f deployment/governance-platform-compliance-garage-api -n governance-prod
kubectl logs -f deployment/governance-platform-governance-service -n governance-prod
kubectl logs -f deployment/governance-platform-integrity-service -n governance-prod

# Check ingress status
kubectl get ingress -n governance-prod
kubectl describe ingress governance-platform-ingress -n governance-prod

# Monitor resource usage
kubectl top pods -n governance-prod
kubectl top nodes
```

### Database Health

```bash
# Check PostgreSQL connection
kubectl exec -it deployment/governance-platform-postgresql -n governance-prod -- psql -U postgres -c "SELECT version();"

# Check Redis connection
kubectl exec -it deployment/governance-platform-redis-master -n governance-prod -- redis-cli ping
```

## Uninstallation

To uninstall/delete the deployment:

```bash
helm uninstall governance-platform -n governance-prod
```

> **Warning**: This will delete all resources associated with the release, including persistent volumes. Ensure you have proper backups before uninstalling.
