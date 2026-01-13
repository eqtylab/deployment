# Governance Platform

A comprehensive Helm umbrella chart for deploying the complete EQTY Lab Governance Platform on Kubernetes.

## Description

The Governance Platform is an enterprise-grade governance, compliance, and integrity management system. This umbrella chart orchestrates the deployment of all platform components including microservices, databases, and supporting infrastructure.

The platform provides:

- **Governance Management**: Policy management, compliance tracking, and governance workflows
- **Integrity & Lineage**: Verifiable credentials, data lineage, and audit trails
- **Multi-Tenancy**: Organization-based access control and isolation
- **Flexible Authentication**: Support for Auth0, Keycloak, and other identity providers
- **Cloud-Native**: Kubernetes-native with horizontal scaling and high availability

## Architecture

The platform uses a microservices architecture with the following components:

- **Governance Studio** - React-based frontend application for managing governance
- **Governance Service** - Go-based backend API with governance logic and workflow engine
- **Integrity Service** - Rust-based service for verifiable credentials and data integrity
- **Auth Service** - Go-based authentication and authorization service with IDP integration
- **PostgreSQL** - Shared relational database for all services
- **Cloud Storage** - Object storage for attachments (GCS, Azure Blob, or AWS S3)

All services communicate via REST APIs and share authentication through the Auth Service.

## Configuration Model

The Governance Platform uses **centralized configuration inheritance** through Helm's global values system. Application configuration is defined once at the umbrella chart level and automatically cascades to all subcharts.

This allows:

- A single configuration point for shared infrastructure settings
- Automatic cascade of settings to all subcharts
- Service-specific overrides when needed
- Consistent configuration across environments

**Key principle**: Define infrastructure concerns (domains, secrets, databases) globally, and service-specific settings (storage providers, feature flags) at the service level.

## Quick Start

### 1. Create Required Secrets

```bash
# Create namespace
kubectl create namespace governance

# Database credentials
kubectl create secret generic platform-database \
  --from-literal=username=postgres \
  --from-literal=password=YOUR_DB_PASSWORD \
  --namespace governance

# Auth0 M2M credentials (two applications required)
kubectl create secret generic platform-auth0 \
  --from-literal=client-id=YOUR_M2M_CLIENT_ID \
  --from-literal=client-secret=YOUR_M2M_CLIENT_SECRET \
  --from-literal=mgmt-client-id=YOUR_MGMT_API_CLIENT_ID \
  --from-literal=mgmt-client-secret=YOUR_MGMT_API_CLIENT_SECRET \
  --namespace governance

# GCS credentials
kubectl create secret generic platform-gcs \
  --from-literal=service-account-json="$(cat service-account.json | base64)" \
  --namespace governance

# Encryption key
kubectl create secret generic platform-encryption-key \
  --from-literal=encryption-key="$(openssl rand -base64 32)" \
  --namespace governance

# Auth Service secrets
kubectl create secret generic platform-auth-service \
  --from-literal=db-password=YOUR_DB_PASSWORD \
  --from-literal=session-secret="$(openssl rand -base64 32)" \
  --from-literal=api-secret="$(openssl rand -base64 32)" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --namespace governance

# Azure Key Vault credentials (for credential signing)
kubectl create secret generic platform-azure-key-vault \
  --from-literal=client-id=YOUR_AZURE_CLIENT_ID \
  --from-literal=client-secret=YOUR_AZURE_CLIENT_SECRET \
  --from-literal=tenant-id=YOUR_AZURE_TENANT_ID \
  --from-literal=vault-url=https://your-vault.vault.azure.net/ \
  --namespace governance

# Governance Worker credentials (for M2M authentication)
kubectl create secret generic platform-governance-worker \
  --from-literal=encryption-key="$(openssl rand -base64 32)" \
  --from-literal=client-id=YOUR_AUTH0_M2M_CLIENT_ID \
  --from-literal=client-secret=YOUR_AUTH0_M2M_CLIENT_SECRET \
  --namespace governance

# Image pull secret
kubectl create secret docker-registry platform-image-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USERNAME \
  --docker-password=YOUR_GITHUB_PAT \
  --namespace governance
```

### 2. Create Values File

```yaml
# values.yaml
global:
  domain: "governance.yourcompany.com"
  environmentType: "production"

  secrets:
    create: false
    database:
      secretName: "platform-database"
    auth:
      provider: "auth0"
      auth0:
        secretName: "platform-auth0"
    storage:
      gcs:
        secretName: "platform-gcs"
    secretManager:
      provider: "azure_key_vault"
      azure_key_vault:
        secretName: "platform-azure-key-vault"
    encryption:
      secretName: "platform-encryption-key"
    authService:
      secretName: "platform-auth-service"
    governanceWorker:
      secretName: "platform-governance-worker"
    imageRegistry:
      secretName: "platform-image-pull-secret"

governance-studio:
  enabled: true
  config:
    auth0Domain: "your-tenant.us.auth0.com"
    auth0ClientId: "your-spa-client-id" # SPA client ID (public, not a secret)
    auth0Audience: "https://your-tenant.us.auth0.com/api/v2/"
  ingress:
    enabled: true
    className: nginx

governance-service:
  enabled: true
  config:
    storageProvider: "gcs"
    gcsBucketName: "governance-attachments"
  ingress:
    enabled: true
    className: nginx

integrity-service:
  enabled: true
  env:
    integrityAppBlobStoreType: "azure_blob"
    integrityAppBlobStoreAccount: "yourstorageacct"
    integrityAppBlobStoreContainer: "integrity-data"
  ingress:
    enabled: true
    className: nginx

auth-service:
  enabled: true
  config:
    idp:
      auth0:
        domain: "your-tenant.us.auth0.com" # Must be set when using Auth0
        managementAudience: "https://your-tenant.us.auth0.com/api/v2/"
        apiIdentifier: "https://your-tenant.us.auth0.com/api/v2/"
  ingress:
    enabled: true
    className: nginx

postgresql:
  enabled: true
```

### 3. Install

```bash
# Update dependencies
helm dependency update ./charts/governance-platform

# Install
helm install governance-platform ./charts/governance-platform \
  --namespace governance \
  --values values.yaml
```

### 4. Verify

```bash
kubectl get pods -n governance
kubectl get ingress -n governance
```

## Secrets Management

The platform supports two approaches for managing secrets:

### Option 1: Pre-Created Kubernetes Secrets (Recommended for Production)

Create secrets manually in Kubernetes before deploying. This is the most secure approach as secrets never touch your filesystem or version control.

```yaml
# values.yaml
global:
  secrets:
    create: false # Use pre-created secrets
    database:
      secretName: "platform-database"
```

See the [Quick Start](#1-create-required-secrets) section for all required secret creation commands.

### Option 2: Secrets Values File (Development & CI/CD)

For development environments or automated deployments, you can provide secrets via a separate values file that gets passed to Helm.

**Create a secrets.yaml file:**

```yaml
# secrets.yaml - DO NOT commit unencrypted!
global:
  secrets:
    create: true # Auto-create secrets from values below

    database:
      values:
        username: "postgres"
        password: "your-secure-password"

    auth:
      provider: "auth0"
      auth0:
        values:
          clientId: "your-client-id"
          clientSecret: "your-client-secret"
          mgmtClientId: "your-mgmt-client-id"
          mgmtClientSecret: "your-mgmt-client-secret"

    # ... additional secrets
```

**Deploy with separate values files:**

```bash
helm upgrade --install governance-platform ./charts/governance-platform \
  --namespace governance \
  --values ./configs/values.yaml \
  --values ./secrets/secrets.yaml
```

See [examples/secrets-sample.yaml](examples/secrets-sample.yaml) for a complete template.

### Encrypting Secrets for Version Control

If you need to store secrets in version control (for GitOps workflows), **always encrypt them first**. Several tools are available:

#### SOPS (Recommended)

[SOPS](https://github.com/getsops/sops) encrypts YAML values while keeping keys readable. Works with AWS KMS, GCP KMS, Azure Key Vault, and PGP.

```bash
# Install SOPS
brew install sops  # macOS
# or: apt install sops  # Ubuntu

# Encrypt with GCP KMS
sops --encrypt --gcp-kms projects/your-project/locations/global/keyRings/your-keyring/cryptoKeys/your-key \
  secrets.yaml > secrets.enc.yaml

# Encrypt with AWS KMS
sops --encrypt --kms arn:aws:kms:us-east-1:123456789:key/your-key-id \
  secrets.yaml > secrets.enc.yaml

# Decrypt for deployment
sops --decrypt secrets.enc.yaml > secrets.yaml
helm upgrade --install ... --values secrets.yaml
rm secrets.yaml  # Clean up unencrypted file
```

#### Helm Secrets Plugin

[helm-secrets](https://github.com/jkroepke/helm-secrets) integrates SOPS directly with Helm:

```bash
# Install
helm plugin install https://github.com/jkroepke/helm-secrets

# Deploy directly with encrypted files
helm secrets upgrade --install governance-platform ./charts/governance-platform \
  --namespace governance \
  --values ./configs/values.yaml \
  --values ./secrets/secrets.enc.yaml
```

#### Sealed Secrets

[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) encrypts secrets that can only be decrypted by the cluster:

```bash
# Install kubeseal
brew install kubeseal

# Create sealed secret
kubectl create secret generic platform-database \
  --from-literal=password=your-password \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > sealed-database-secret.yaml

# Apply sealed secret (controller decrypts it)
kubectl apply -f sealed-database-secret.yaml
```

#### git-crypt

[git-crypt](https://github.com/AGWA/git-crypt) provides transparent encryption for git repositories:

```bash
# Initialize
git-crypt init

# Add files to encrypt in .gitattributes
echo "secrets/*.yaml filter=git-crypt diff=git-crypt" >> .gitattributes

# Files are automatically encrypted on commit
git add secrets/secrets.yaml
git commit -m "Add encrypted secrets"
```

### Best Practices

1. **Never commit unencrypted secrets** - Add `**/secrets.yaml` to `.gitignore`
2. **Use environment-specific secrets** - Separate files for dev/staging/prod
3. **Rotate secrets regularly** - Especially for production environments
4. **Audit access** - Track who has access to encryption keys
5. **Use managed identity where possible** - Prefer workload identity over static credentials
6. **Limit secret scope** - Only include secrets needed for each environment

### Preserving Database Passwords on Upgrade

When upgrading an existing deployment, the database password must remain consistent. If using `secrets.create: true`, ensure the same password is provided on each upgrade.

For automated deployments, you can extract and reuse the existing password:

```bash
# Extract existing password
PASSWORD=$(kubectl get secret platform-database -n governance \
  -o jsonpath="{.data.password}" | base64 -d)

# Use in upgrade (both parameters required for Bitnami PostgreSQL chart)
helm upgrade governance-platform ./charts/governance-platform \
  --namespace governance \
  --values ./configs/values.yaml \
  --values ./secrets/secrets.yaml \
  --set global.secrets.database.values.password=$PASSWORD \
  --set global.postgresql.auth.postgresPassword=$PASSWORD
```

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- Persistent Volume Provisioner for database storage
- Container Registry Access (GitHub Container Registry credentials)
- Ingress controller (NGINX, Traefik, etc.)
- TLS certificate management (cert-manager or manual)

### Infrastructure Dependencies

#### Ingress Controller (Required)

```bash
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

#### TLS Certificate Management (Required for Production)

**Option A: cert-manager (Recommended)**

```bash
helm install cert-manager cert-manager \
  --repo https://charts.jetstack.io \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

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

**Option B: Manual TLS Secrets**

```bash
kubectl create secret tls platform-tls \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  --namespace governance
```

## Installing the Chart

### From Local Directory

```bash
helm dependency update ./charts/governance-platform

helm install governance-platform ./charts/governance-platform \
  --create-namespace \
  --namespace governance \
  --values values.yaml
```

### From OCI Registry

```bash
helm install governance-platform oci://ghcr.io/eqtylab/charts/governance-platform \
  --version 0.1.0 \
  --create-namespace \
  --namespace governance \
  --values values.yaml
```

## Uninstalling the Chart

```bash
helm uninstall governance-platform --namespace governance
```

> ⚠️ **Warning**: This deletes all resources including persistent volumes. Backup your database before uninstalling.

## Values

### Global Parameters

These global values are automatically inherited by all subcharts:

| Key                    | Type   | Default                    | Description                                       |
| ---------------------- | ------ | -------------------------- | ------------------------------------------------- |
| global.domain          | string | `"governance.example.com"` | Base domain for all services (**MUST override**)  |
| global.environmentType | string | `"production"`             | Environment type (development/staging/production) |
| global.imagePullPolicy | string | `"IfNotPresent"`           | Default image pull policy for all containers      |

### Global Secret Configuration

Centralized secret configuration for all platform components:

| Key                                                     | Type   | Default                            | Description                                    |
| ------------------------------------------------------- | ------ | ---------------------------------- | ---------------------------------------------- |
| global.secrets.create                                   | bool   | `false`                            | Auto-create secrets from values (dev only)     |
| global.secrets.database.secretName                      | string | `"platform-database"`              | Database credentials secret name               |
| global.secrets.auth.provider                            | string | `"auth0"`                          | Auth provider (auth0 or keycloak)              |
| global.secrets.auth.auth0.secretName                    | string | `"platform-auth0"`                 | Auth0 credentials secret name                  |
| global.secrets.auth.keycloak.secretName                 | string | `"platform-keycloak-credentials"`  | Keycloak credentials secret name               |
| global.secrets.storage.gcs.secretName                   | string | `"platform-gcs"`                   | GCS credentials secret name                    |
| global.secrets.storage.azure_blob.secretName            | string | `"platform-azure-blob"`            | Azure Blob credentials secret name             |
| global.secrets.storage.aws_s3.secretName                | string | `"platform-aws-s3"`                | AWS S3 credentials secret name                 |
| global.secrets.secretManager.provider                   | string | `"azure_key_vault"`                | Secret manager provider for credential signing |
| global.secrets.secretManager.azure_key_vault.secretName | string | `"platform-azure-key-vault"`       | Azure Key Vault credentials secret name        |
| global.secrets.encryption.secretName                    | string | `"platform-encryption-key"`        | Platform encryption key secret name            |
| global.secrets.governanceWorker.secretName              | string | `"platform-governance-worker"`     | Governance worker credentials secret name      |
| global.secrets.governanceServiceAI.secretName           | string | `"platform-governance-service-ai"` | AI API key secret name                         |
| global.secrets.imageRegistry.secretName                 | string | `"platform-image-pull-secret"`     | Container registry credentials secret name     |

### Global Database Configuration

Shared PostgreSQL connection settings:

| Key                        | Type   | Default        | Description                             |
| -------------------------- | ------ | -------------- | --------------------------------------- |
| global.postgresql.host     | string | `""`           | Database host (auto-generated if empty) |
| global.postgresql.port     | int    | `5432`         | Database port                           |
| global.postgresql.database | string | `"governance"` | Default database name                   |
| global.postgresql.username | string | `"postgres"`   | Database username                       |

### Governance Studio Configuration

Frontend application settings. See [governance-studio/README.md](../governance-studio/README.md) for complete documentation.

| Key                                   | Type   | Default               | Description                          |
| ------------------------------------- | ------ | --------------------- | ------------------------------------ |
| governance-studio.enabled             | bool   | `true`                | Enable Governance Studio             |
| governance-studio.replicaCount        | int    | `1`                   | Number of replicas                   |
| governance-studio.ingress.enabled     | bool   | `false`               | Enable ingress                       |
| governance-studio.config.authProvider | string | `""`                  | Auth provider (auto-set from global) |
| governance-studio.config.appTitle     | string | `"Governance Studio"` | Application title                    |
| governance-studio.autoscaling.enabled | bool   | `false`               | Enable horizontal pod autoscaling    |

### Governance Service Configuration

Backend API service settings. See [governance-service/README.md](../governance-service/README.md) for complete documentation.

| Key                                       | Type   | Default | Description                                       |
| ----------------------------------------- | ------ | ------- | ------------------------------------------------- |
| governance-service.enabled                | bool   | `true`  | Enable Governance Service                         |
| governance-service.replicaCount           | int    | `1`     | Number of replicas                                |
| governance-service.ingress.enabled        | bool   | `false` | Enable ingress                                    |
| governance-service.config.storageProvider | string | `""`    | Storage provider (**REQUIRED**: gcs/azure/aws_s3) |
| governance-service.config.gcsBucketName   | string | `""`    | GCS bucket name (required if provider is gcs)     |
| governance-service.config.ai.enabled      | bool   | `true`  | Enable AI features                                |
| governance-service.autoscaling.enabled    | bool   | `false` | Enable horizontal pod autoscaling                 |

### Integrity Service Configuration

Credential and lineage service settings. See [integrity-service/README.md](../integrity-service/README.md) for complete documentation.

| Key                                             | Type   | Default | Description                                        |
| ----------------------------------------------- | ------ | ------- | -------------------------------------------------- |
| integrity-service.enabled                       | bool   | `true`  | Enable Integrity Service                           |
| integrity-service.replicaCount                  | int    | `1`     | Number of replicas                                 |
| integrity-service.ingress.enabled               | bool   | `false` | Enable ingress                                     |
| integrity-service.env.integrityAppBlobStoreType | string | `""`    | Storage provider (**REQUIRED**: aws_s3/azure_blob) |
| integrity-service.autoscaling.enabled           | bool   | `false` | Enable horizontal pod autoscaling                  |

### Auth Service Configuration

Authentication and authorization service settings. See [auth-service/README.md](../auth-service/README.md) for complete documentation.

| Key                                   | Type   | Default | Description                               |
| ------------------------------------- | ------ | ------- | ----------------------------------------- |
| auth-service.enabled                  | bool   | `true`  | Enable Auth Service                       |
| auth-service.replicaCount             | int    | `2`     | Number of replicas                        |
| auth-service.config.idp.provider      | string | `""`    | IDP provider (auto-set from global)       |
| auth-service.config.keyVault.provider | string | `""`    | Key Vault provider (auto-set from global) |
| auth-service.ingress.enabled          | bool   | `false` | Enable ingress                            |
| auth-service.autoscaling.enabled      | bool   | `false` | Enable horizontal pod autoscaling         |

### PostgreSQL Configuration

Bitnami PostgreSQL chart configuration:

| Key                                                           | Type   | Default                              | Description                                       |
| ------------------------------------------------------------- | ------ | ------------------------------------ | ------------------------------------------------- |
| postgresql.enabled                                            | bool   | `true`                               | Enable PostgreSQL database                        |
| postgresql.global.postgresql.auth.database                    | string | `"governance"`                       | Database name                                     |
| postgresql.global.postgresql.auth.username                    | string | `"postgres"`                         | Database username                                 |
| postgresql.global.postgresql.auth.postgresPassword            | string | `"placeholder-overridden-by-secret"` | Placeholder for validation (overridden by secret) |
| postgresql.global.postgresql.auth.existingSecret              | string | `"platform-database"`                | Secret name for credentials                       |
| postgresql.global.postgresql.auth.secretKeys.adminPasswordKey | string | `"password"`                         | Key for admin password in secret                  |
| postgresql.global.postgresql.auth.secretKeys.userPasswordKey  | string | `"password"`                         | Key for user password in secret                   |
| postgresql.primary.persistence.enabled                        | bool   | `true`                               | Enable persistent storage                         |
| postgresql.primary.persistence.size                           | string | `"10Gi"`                             | Storage size                                      |

> **Note:** The `postgresPassword` is a placeholder that satisfies Bitnami chart validation during upgrades. The actual password is read from `existingSecret` at runtime. The secret is created via `global.secrets.database` when `global.secrets.create: true`.

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level values** - Explicitly set in subchart config (e.g., `governance-service.config.logLevel`)
2. **Global values** - Set in `global.*` (e.g., `global.environmentType`)
3. **Chart defaults** - Default values from subchart `values.yaml`

### What Gets Auto-Configured

When services are deployed via the umbrella chart, they automatically inherit:

- ✅ Domain and environment type
- ✅ Database connection details and credentials
- ✅ Authentication provider configuration
- ✅ Storage credentials (credentials only, not provider/bucket selection)
- ✅ Encryption keys and secret manager credentials
- ✅ Service-to-service URLs
- ✅ Image pull secrets
- ✅ Worker authentication credentials
- ✅ AI API credentials

### What Must Be Explicitly Configured

Services require explicit configuration for:

- ⚠️ Storage provider type (`storageProvider`, `integrityAppBlobStoreType`)
- ⚠️ Storage bucket/container names (`gcsBucketName`, `azureStorageContainerName`, etc.)
- ⚠️ Feature flags (governance-studio)
- ⚠️ Service-specific settings (AI config, indicator settings, etc.)

### Example Configuration Flow

```yaml
global:
  domain: "governance.prod.company.com"
  environmentType: "production"
  secrets:
    auth:
      provider: "auth0"
      auth0:
        secretName: "platform-auth0"
    storage:
      gcs:
        secretName: "platform-gcs"

governance-studio:
  enabled: true
  # config.environment automatically becomes: production
  # config.authProvider automatically becomes: auth0

  config:
    # Auth0 settings must be explicitly set (SPA client ID is public, not a secret)
    auth0Domain: "mycompany.us.auth0.com"
    auth0ClientId: "my-spa-client-id"
    auth0Audience: "https://mycompany.us.auth0.com/api/v2/"
    # Override specific settings
    appTitle: "My Company Governance"
    branding:
      companyName: "My Company"

governance-service:
  enabled: true
  # config.appEnv automatically becomes: production
  # Database credentials auto-populated from global secrets
  # Storage credentials auto-populated from global secrets

  config:
    # Must explicitly set storage provider and bucket
    storageProvider: "gcs"
    gcsBucketName: "my-company-governance"

integrity-service:
  enabled: true
  # rustEnv automatically becomes: production
  # Database credentials auto-populated from global secrets
  # Storage credentials auto-populated from global secrets

  env:
    # Must explicitly set storage provider and container
    integrityAppBlobStoreType: "azure_blob"
    integrityAppBlobStoreAccount: "mystorageacct"
    integrityAppBlobStoreContainer: "integrity-data"
```

## Storage Provider Configuration

Each service can independently choose its storage provider. Credentials are inherited from global configuration, but provider type and bucket/container names must be explicitly set.

### Google Cloud Storage

```yaml
global:
  secrets:
    storage:
      gcs:
        secretName: "platform-gcs"

governance-service:
  config:
    storageProvider: "gcs"
    gcsBucketName: "governance-attachments"
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
    storageProvider: "azure_blob"
    azureStorageContainerName: "governance-data"

integrity-service:
  env:
    integrityAppBlobStoreType: "azure_blob"
    integrityAppBlobStoreAccount: "mystorageacct"
    integrityAppBlobStoreContainer: "integrity-data"
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
    storageProvider: "aws_s3"
    awsS3Region: "us-east-1"
    awsS3BucketName: "governance-bucket"

integrity-service:
  env:
    integrityAppBlobStoreType: "aws_s3"
    integrityAppBlobStoreRegion: "us-east-1"
    integrityAppBlobStoreBucket: "integrity-bucket"
```

## Authentication Provider Configuration

### Auth0 Configuration

Auth0 requires two M2M (Machine-to-Machine) applications plus a SPA application:

1. **EQTYLab Platform API** (M2M) - For token validation (`auth0.values.clientId/clientSecret`)
2. **Auth Service Backend** (M2M) - For Management API calls (`auth0.values.mgmtClientId/mgmtClientSecret`)
3. **Governance Studio** (SPA) - For frontend authentication (configured via `governance-studio.config`)

```yaml
global:
  secrets:
    auth:
      provider: "auth0"
      auth0:
        secretName: "platform-auth0"
        # M2M credentials are stored in the secret (see Quick Start for creation)

    governanceWorker:
      secretName: "platform-governance-worker"

governance-studio:
  config:
    # SPA settings must be explicitly set (public, not secrets)
    auth0Domain: "your-tenant.us.auth0.com"
    auth0ClientId: "your-spa-client-id"
    auth0Audience: "https://your-tenant.us.auth0.com/api/v2/"

auth-service:
  config:
    idp:
      auth0:
        domain: "your-tenant.us.auth0.com"
        managementAudience: "https://your-tenant.us.auth0.com/api/v2/"
        apiIdentifier: "https://your-tenant.us.auth0.com/api/v2/"
```

### Keycloak Configuration

```yaml
global:
  secrets:
    auth:
      provider: "keycloak"
      keycloak:
        secretName: "platform-keycloak-credentials"

    governanceWorker:
      secretName: "platform-governance-worker"

keycloak:
  createOrganization: true
  realmName: "governance"
  displayName: "Governance Platform"
```

## Environment-Specific Configurations

### Development

```yaml
global:
  domain: "governance.dev.local"
  environmentType: "development"
  imagePullPolicy: "Always"
  secrets:
    create: true

governance-studio:
  replicaCount: 1

governance-service:
  replicaCount: 1
  config:
    logLevel: "debug"

integrity-service:
  replicaCount: 1
  env:
    integrityAppLoggingLogLevelDefault: "debug"

postgresql:
  primary:
    persistence:
      size: 5Gi
```

### Production

```yaml
global:
  domain: "governance.company.com"
  environmentType: "production"
  imagePullPolicy: "IfNotPresent"
  secrets:
    create: false

governance-studio:
  replicaCount: 3
  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

governance-service:
  replicaCount: 3
  config:
    logLevel: "warn"
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 20
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2Gi

integrity-service:
  replicaCount: 3
  env:
    integrityAppLoggingLogLevelDefault: "warn"
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 15
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi

postgresql:
  primary:
    persistence:
      size: 100Gi
      storageClass: "fast-ssd"
    resources:
      requests:
        cpu: 2000m
        memory: 4Gi
      limits:
        cpu: 4000m
        memory: 8Gi
```

## Upgrading

### Pre-Upgrade Checklist

1. **Backup Database**

   ```bash
   kubectl exec -it deployment/governance-platform-postgresql -n governance -- \
     pg_dump -U postgres governance > backup-$(date +%Y%m%d).sql
   ```

2. **Review Changes**
   ```bash
   helm diff upgrade governance-platform ./charts/governance-platform \
     --namespace governance \
     --values values.yaml
   ```

### Perform Upgrade

```bash
helm upgrade governance-platform ./charts/governance-platform \
  --namespace governance \
  --values values.yaml
```

### Verify Upgrade

```bash
kubectl get pods -n governance -w
kubectl rollout status deployment/governance-platform-governance-service -n governance
kubectl rollout status deployment/governance-platform-governance-studio -n governance
kubectl rollout status deployment/governance-platform-integrity-service -n governance
```

### Rolling Back

```bash
# View release history
helm history governance-platform -n governance

# Rollback to previous version
helm rollback governance-platform -n governance

# Rollback to specific revision
helm rollback governance-platform 3 -n governance
```

## Troubleshooting

### Viewing Logs

```bash
# Governance Service
kubectl logs -f deployment/governance-platform-governance-service -n governance

# Integrity Service
kubectl logs -f deployment/governance-platform-integrity-service -n governance

# Governance Studio
kubectl logs -f deployment/governance-platform-governance-studio -n governance

# Auth Service
kubectl logs -f deployment/governance-platform-auth-service -n governance
```

### Checking Pod Status

```bash
kubectl get pods -n governance
kubectl describe pod <pod-name> -n governance
```

### Testing Configuration

View environment variables in running pod:

```bash
kubectl exec -it deployment/governance-platform-governance-service -n governance -- env | sort
```

### Common Issues

**Application not accessible**

- Verify ingress is enabled and configured correctly
- Check DNS points to your ingress controller
- Verify TLS certificates are valid
- Ensure `global.domain` matches your DNS configuration

**Database connection errors**

- Verify PostgreSQL is running: `kubectl get pods -n governance -l app.kubernetes.io/name=postgresql`
- Check database credentials in secret
- Ensure databases exist (governance, IntegrityServiceDB)
- Verify network policies allow traffic between services

**Storage errors**

- Verify storage provider is explicitly set (`storageProvider`, `integrityAppBlobStoreType`)
- Check storage credentials in secret
- Ensure bucket/container names are set
- For GCS: verify service account JSON is valid
- For Azure: verify account name, key, and container exist
- For AWS: verify access keys are valid and bucket exists

**Authentication failures**

- Verify auth provider matches `global.secrets.auth.provider`
- For Auth0: check domain, client ID, and client secret
- For Keycloak: check URL, realm, and client credentials
- Ensure auth service is running and accessible

**Configuration not applying**

- Remember: service-level config overrides global config
- Check for typos in configuration keys
- Restart pods: `kubectl rollout restart deployment/<deployment-name> -n governance`

### Debug Mode

Enable debug logging for troubleshooting:

```yaml
governance-service:
  config:
    logLevel: "debug"

integrity-service:
  env:
    integrityAppLoggingLogLevelDefault: "debug"

auth-service:
  config:
    logging:
      level: "debug"
```

## Health Check Endpoints

| Service            | Endpoint                          |
| ------------------ | --------------------------------- |
| Governance Studio  | `GET /`                           |
| Governance Service | `GET /governanceService/health`   |
| Integrity Service  | `GET /integrityService/health/v1` |
| Auth Service       | `GET /authService/health`         |

## API Documentation

Each backend service exposes Swagger/OpenAPI documentation:

| Service            | Swagger UI                                  |
| ------------------ | ------------------------------------------- |
| Governance Service | `GET /governanceService/swagger/index.html` |
| Integrity Service  | `GET /integrityService/swagger/index.html`  |
| Auth Service       | `GET /authService/swagger/index.html`       |

## Support

For issues and questions:

- **Email**: support@eqtylab.io
- **Documentation**: https://docs.eqtylab.io
- **GitHub Issues**: https://github.com/eqtylab/governance-studio-infrastructure/issues
- **Security Issues**: security@eqtylab.io

When requesting support, please include:

1. Chart version: `helm list -n governance`
2. Kubernetes version: `kubectl version`
3. Pod status: `kubectl get pods -n governance`
4. Relevant log snippets
5. Sanitized values file (remove secrets)
