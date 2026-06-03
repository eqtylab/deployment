# Governance Platform

A comprehensive Helm umbrella chart for deploying the complete EQTY Lab Governance Platform on Kubernetes.

## Description

The Governance Platform is an enterprise-grade governance, compliance, and integrity management system. This umbrella chart orchestrates the deployment of all platform components including microservices, databases, and supporting infrastructure.

The platform provides:

- **Governance Management**: Policy management, compliance tracking, and governance workflows
- **Integrity & Lineage**: Verifiable credentials, data lineage, and audit trails
- **Multi-Tenancy**: Organization-based access control and isolation
- **Flexible Authentication**: Support for Auth0, Microsoft Entra ID, and Keycloak
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

## Prerequisites

- Kubernetes 1.29+
- Helm 4.0+
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
helm upgrade --install cert-manager cert-manager \
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

## Deployment

### Quick Start

The recommended way to generate configuration is with [`govctl`](../../govctl/README.md), the Governance Platform CLI:

```bash
# Install govctl (from the govctl/ directory)
uv pip install -e .

# Generate values and secrets files
govctl init

# Fill in any remaining secrets
# Review generated files for correctness

# Deploy
helm upgrade --install governance-platform ./charts/governance-platform \
  -f output/values-staging.yaml \
  -f output/secrets-staging.yaml \
  -n governance --create-namespace
```

See the [govctl README](../../govctl/README.md) for full usage and options.

### Required Configuration

Whether using `govctl` or manual configuration, these values **must** be set:

- **`global.domain`** - Base domain for all services
- **`global.secrets.auth.provider`** - Auth provider (`auth0`, `entra`, or `keycloak`)
- **Storage provider** per service (`governance-service.config.storageProvider`, `integrity-service.config.integrityAppBlobStoreType`)
- **Storage bucket/container names** per service
- **Auth provider public settings** - SPA client IDs, domains, tenant IDs (varies by provider)
- **All secret values** in the secrets file (database, auth, storage, encryption, registry)

See the [examples/](examples/) directory for complete configuration examples:

- [values-auth0.yaml](examples/values-auth0.yaml) - Auth0 deployment
- [values-entra.yaml](examples/values-entra.yaml) - Entra ID deployment
- [values-keycloak.yaml](examples/values-keycloak.yaml) - Keycloak deployment
- [secrets-sample.yaml](examples/secrets-sample.yaml) - Complete secrets template

### Verify

```bash
kubectl get pods -n governance
kubectl get ingress -n governance
```

### Installing from OCI Registry

```bash
helm upgrade --install governance-platform oci://ghcr.io/eqtylab/charts/governance-platform \
  --version 0.1.0 \
  --create-namespace \
  --namespace governance \
  --values values.yaml
```

### Uninstalling

```bash
helm uninstall governance-platform --namespace governance
```

> **Warning**: This deletes all resources including persistent volumes. Backup your database before uninstalling.

## Secrets Management

The platform supports two approaches for managing secrets:

### Option 1: Secrets Values File (Recommended)

Use `govctl init` to generate a secrets file, or create one manually. Secrets are passed to Helm as a separate values file.

```bash
helm upgrade --install governance-platform ./charts/governance-platform \
  --namespace governance \
  --values values.yaml \
  --values secrets.yaml
```

See [examples/secrets-sample.yaml](examples/secrets-sample.yaml) for a complete template.

### Option 2: Pre-Created Kubernetes Secrets

Create secrets manually in Kubernetes before deploying. This approach avoids secrets touching your filesystem.

```yaml
# values.yaml
global:
  secrets:
    create: false # Use pre-created secrets
```

### Encrypting Secrets for Version Control

If you need to store secrets in version control (for GitOps workflows), **always encrypt them first**. Several tools are available:

#### SOPS (Recommended)

[SOPS](https://github.com/getsops/sops) encrypts YAML values while keeping keys readable. Works with AWS KMS, Azure Key Vault, GCP KMS, and PGP.

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
  --set global.secrets.database.values.password=$PASSWORD
```

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

| Key                                                     | Type   | Default                        | Description                                                                           |
| ------------------------------------------------------- | ------ | ------------------------------ | ------------------------------------------------------------------------------------- |
| global.secrets.create                                   | bool   | `false`                        | Auto-create secrets from values (dev only)                                            |
| global.secrets.database.secretName                      | string | `"platform-database"`          | Database credentials secret name                                                      |
| global.secrets.auth.provider                            | string | `"auth0"`                      | Auth provider (auth0, entra, or keycloak)                                             |
| global.secrets.auth.auth0.secretName                    | string | `"platform-auth0"`             | Auth0 credentials secret name                                                         |
| global.secrets.auth.entra.secretName                    | string | `"platform-entra"`             | Microsoft Entra ID credentials secret name                                            |
| global.secrets.auth.keycloak.secretName                 | string | `"platform-keycloak"`          | Keycloak credentials secret name                                                      |
| global.secrets.storage.aws_s3.secretName                | string | `"platform-aws-s3"`            | AWS S3 credentials secret name                                                        |
| global.secrets.storage.azure_blob.secretName            | string | `"platform-azure-blob"`        | Azure Blob credentials secret name                                                    |
| global.secrets.storage.gcs.secretName                   | string | `"platform-gcs"`               | GCS credentials secret name                                                           |
| global.secrets.keyManagement.provider                   | string | `"azure_key_vault"`            | Key management provider for credential signing (aws_kms, azure_key_vault, or gcp_kms) |
| global.secrets.keyManagement.aws_kms.secretName         | string | `"platform-aws-kms"`           | AWS KMS credentials secret name                                                       |
| global.secrets.keyManagement.azure_key_vault.secretName | string | `"platform-azure-key-vault"`   | Azure Key Vault credentials secret name                                               |
| global.secrets.keyManagement.gcp_kms.secretName         | string | `"platform-gcp-kms"`           | GCP KMS credentials secret name                                                       |
| global.secrets.encryption.secretName                    | string | `"platform-encryption-key"`    | Platform encryption key secret name                                                   |
| global.secrets.authService.secretName                   | string | `"platform-auth-service"`      | Auth service secrets (session, JWT, API keys)                                         |
| global.secrets.governanceWorker.secretName              | string | `"platform-governance-worker"` | Governance worker credentials secret name                                             |
| global.secrets.imageRegistry.secretName                 | string | `"platform-image-pull-secret"` | Container registry credentials secret name                                            |

### Global Database Configuration

Shared PostgreSQL connection settings:

| Key                                         | Type   | Default        | Description                                                                                              |
| ------------------------------------------- | ------ | -------------- | -------------------------------------------------------------------------------------------------------- |
| global.postgresql.host                      | string | `""`           | Database host (auto-generated as {Release.Name}-postgresql when bundled; set explicitly for external DB) |
| global.postgresql.port                      | int    | `5432`         | Database port                                                                                            |
| global.postgresql.database                  | string | `"governance"` | Default database name                                                                                    |
| global.postgresql.username                  | string | `"postgres"`   | Database username                                                                                        |
| global.postgresql.sslMode                   | string | `"disable"`    | Shared SSL mode for all services. Options: disable, require, verify-ca, verify-full                      |
| global.postgresql.sslRootCert.secretName    | string | `""`           | Secret holding the CA bundle (mounted at `/etc/ssl/postgres/<key>` when set)                             |
| global.postgresql.sslRootCert.configMapName | string | `""`           | ConfigMap holding the CA bundle (alternative to secretName)                                              |
| global.postgresql.sslRootCert.key           | string | `"ca.crt"`     | Key within the Secret/ConfigMap holding the PEM-encoded CA bundle                                        |

### Auth Service Configuration

Authentication and authorization service settings. See [auth-service/README.md](../auth-service/README.md) for complete documentation.

| Key                                        | Type   | Default | Description                                                                          |
| ------------------------------------------ | ------ | ------- | ------------------------------------------------------------------------------------ |
| auth-service.enabled                       | bool   | `true`  | Enable Auth Service                                                                  |
| auth-service.replicaCount                  | int    | `2`     | Number of replicas                                                                   |
| auth-service.config.idp.provider           | string | `""`    | IDP provider (auto-configured from global.secrets.auth.provider)                     |
| auth-service.config.keyManagement.provider | string | `""`    | Key management provider (auto-configured from global.secrets.keyManagement.provider) |
| auth-service.ingress.enabled               | bool   | `false` | Enable ingress                                                                       |
| auth-service.autoscaling.enabled           | bool   | `false` | Enable horizontal pod autoscaling                                                    |

### Governance Service Configuration

Backend API service settings. See [governance-service/README.md](../governance-service/README.md) for complete documentation.

| Key                                       | Type   | Default | Description                                            |
| ----------------------------------------- | ------ | ------- | ------------------------------------------------------ |
| governance-service.enabled                | bool   | `true`  | Enable Governance Service                              |
| governance-service.replicaCount           | int    | `2`     | Number of replicas                                     |
| governance-service.ingress.enabled        | bool   | `false` | Enable ingress                                         |
| governance-service.config.storageProvider | string | `""`    | Storage provider (**REQUIRED**: aws_s3/azure_blob/gcs) |
| governance-service.autoscaling.enabled    | bool   | `false` | Enable horizontal pod autoscaling                      |

### Governance Studio Configuration

Frontend application settings. See [governance-studio/README.md](../governance-studio/README.md) for complete documentation.

| Key                                      | Type   | Default               | Description                                                               |
| ---------------------------------------- | ------ | --------------------- | ------------------------------------------------------------------------- |
| governance-studio.enabled                | bool   | `true`                | Enable Governance Studio                                                  |
| governance-studio.replicaCount           | int    | `1`                   | Number of replicas                                                        |
| governance-studio.ingress.enabled        | bool   | `false`               | Enable ingress                                                            |
| governance-studio.config.authProvider    | string | `""`                  | Auth provider (auto-configured from global.secrets.auth.provider)         |
| governance-studio.config.appTitle        | string | `"Governance Studio"` | Application title                                                         |
| governance-studio.config.displayTimezone | string | `"UTC"`               | Timezone used for displayed timestamps (IANA name, e.g. America/New_York) |
| governance-studio.autoscaling.enabled    | bool   | `false`               | Enable horizontal pod autoscaling                                         |

### Integrity Service Configuration

Credential and lineage service settings. See [integrity-service/README.md](../integrity-service/README.md) for complete documentation.

| Key                                                | Type   | Default | Description                                            |
| -------------------------------------------------- | ------ | ------- | ------------------------------------------------------ |
| integrity-service.enabled                          | bool   | `true`  | Enable Integrity Service                               |
| integrity-service.replicaCount                     | int    | `2`     | Number of replicas                                     |
| integrity-service.ingress.enabled                  | bool   | `false` | Enable ingress                                         |
| integrity-service.config.integrityAppBlobStoreType | string | `""`    | Storage provider (**REQUIRED**: aws_s3/azure_blob/gcs) |
| integrity-service.autoscaling.enabled              | bool   | `false` | Enable horizontal pod autoscaling                      |

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

### Auth0 Post-Install Hook

Optional post-install/post-upgrade hook that seeds the governance database with the initial organization and platform-admin user for Auth0 deployments:

| Key                       | Type   | Default               | Description                                                                                        |
| ------------------------- | ------ | --------------------- | -------------------------------------------------------------------------------------------------- |
| auth0.createOrganization  | bool   | `false`               | Enable the post-install hook to create the org                                                     |
| auth0.organizationName    | string | `"governance"`        | Organization identifier in the database                                                            |
| auth0.displayName         | string | `"Governance Studio"` | Display name for the organization                                                                  |
| auth0.createPlatformAdmin | bool   | `false`               | Also create the platform-admin user and membership                                                 |
| auth0.platformAdminEmail  | string | `""`                  | **Required** when `createPlatformAdmin` is true. Must exist in the Auth0 tenant                    |
| auth0.domain              | string | `""`                  | **Required** when `createPlatformAdmin` is true. Auth0 tenant domain (e.g., `tenant.us.auth0.com`) |

The hook authenticates against the Auth0 Management API using `mgmt-client-id` / `mgmt-client-secret` from the `platform-auth0` secret and resolves the admin's `user_id` via `/api/v2/users-by-email`.

### Entra ID Post-Install Hook

Optional post-install/post-upgrade hook that seeds the governance database with the initial organization and platform-admin user for Microsoft Entra ID deployments:

| Key                       | Type   | Default               | Description                                                                 |
| ------------------------- | ------ | --------------------- | --------------------------------------------------------------------------- |
| entra.createOrganization  | bool   | `false`               | Enable the post-install hook to create the org                              |
| entra.organizationName    | string | `"governance"`        | Organization identifier in the database                                     |
| entra.displayName         | string | `"Governance Studio"` | Display name for the organization                                           |
| entra.createPlatformAdmin | bool   | `false`               | Also create the platform-admin user and membership                          |
| entra.platformAdminEmail  | string | `""`                  | **Required** when `createPlatformAdmin` is true. Must exist in Entra tenant |
| entra.tenantId            | string | `""`                  | Microsoft Entra tenant ID (required for Graph API user lookup)              |

### Keycloak Post-Install Hook

Optional post-install/post-upgrade hook that seeds the governance database with the initial organization and platform-admin user:

| Key                          | Type   | Default                           | Description                                        |
| ---------------------------- | ------ | --------------------------------- | -------------------------------------------------- |
| keycloak.createOrganization  | bool   | `false`                           | Enable the post-install hook to create the org     |
| keycloak.realmName           | string | `"governance"`                    | Keycloak realm name (used as org name in database) |
| keycloak.displayName         | string | `"Governance Studio"`             | Display name for the organization                  |
| keycloak.createPlatformAdmin | bool   | `false`                           | Also create the platform-admin user and membership |
| keycloak.platformAdminEmail  | string | `""`                              | Admin email (defaults to admin@<global.domain>)    |
| keycloak.url                 | string | `"http://keycloak:8080/keycloak"` | Internal Keycloak URL for API lookups              |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level values** - Explicitly set in subchart config (e.g., `governance-service.config.logLevel`)
2. **Global values** - Set in `global.*` (e.g., `global.environmentType`)
3. **Chart defaults** - Default values from subchart `values.yaml`

### What Gets Auto-Configured

When services are deployed via the umbrella chart, they automatically inherit:

- Domain and environment type
- Database connection details and credentials
- Authentication provider configuration
- Storage credentials (credentials only, not provider/bucket selection)
- Encryption keys and key management credentials
- Service-to-service URLs
- Image pull secrets
- Worker authentication credentials
- AI API credentials

### What Must Be Explicitly Configured

Services require explicit configuration for:

- Storage provider type (`storageProvider`, `integrityAppBlobStoreType`)
- Storage account/bucket/container names (`awsS3BucketName`, `azureStorageAccountName`, `azureStorageContainerName`, `gcsBucketName`, etc.)
- Feature flags (governance-studio)
- Service-specific settings (AI config, indicator settings, etc.)

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

governance-service:
  enabled: true
  # config.environment automatically becomes: production
  # Database credentials auto-configured from global.secrets.database
  # Storage credentials auto-configured from global.secrets.storage

  config:
    # Must explicitly set storage provider and bucket
    storageProvider: "gcs"
    gcsBucketName: "your-governance-artifacts-bucket"

integrity-service:
  enabled: true
  # rustEnv automatically becomes: production
  # Database credentials auto-configured from global.secrets.database
  # Storage credentials auto-configured from global.secrets.storage

  config:
    # Must explicitly set storage provider and container
    integrityAppBlobStoreType: "azure_blob"
    integrityAppBlobStoreAccount: "your-storage-account"
    integrityAppBlobStoreContainer: "your-integrity-store-container"
```

## Cloud-Managed PostgreSQL Configuration

The platform can run against an external, cloud-managed PostgreSQL instance instead of the bundled Bitnami subchart. Supported providers: AWS RDS / Aurora PostgreSQL, Azure Database for PostgreSQL — Flexible Server, GCP Cloud SQL for PostgreSQL.

### How it works

- `postgresql.enabled: false` disables the bundled subchart.
- `global.postgresql.host`, `port`, `username`, `database` are shared by all platform services (auth-service, governance-service, integrity-service).
- `global.postgresql.sslMode` and `global.postgresql.sslRootCert` configure TLS to the managed instance.
- `global.secrets.database.secretName` is the Secret name all platform components use for the DB password. If `global.secrets.create: true`, the chart can create it from `global.secrets.database.values`; if `false`, pre-create it in the release namespace.

A pre-install guardrail aborts with a clear message if `postgresql.enabled=false` and `global.postgresql.host` is empty (no database configured). Setting `global.postgresql.host` alongside the bundled chart is allowed — it lets you point services at a renamed in-cluster Service (e.g., when also using `postgresql.fullnameOverride`); NOTES.txt will emit a soft warning to make sure the override is intentional.

### Prerequisites (all providers)

1. The managed Postgres instance is reachable from the cluster (VPC peering, private link, VNet integration, or a connection proxy as a sidecar — provider-specific).
2. Create the two databases the platform expects:
   ```sql
   CREATE DATABASE governance;
   CREATE DATABASE "IntegrityServiceDB";
   ```
3. If you are deploying with `global.secrets.create: false` (the default in this chart and in the example values files), create the password Secret in the release namespace:
   ```sh
   kubectl create secret generic platform-database \
     --from-literal=password='<your-db-password>' \
     --namespace governance
   ```
   If you are deploying with `global.secrets.create: true` instead, the chart can create `platform-database` for you from `global.secrets.database.values`.
4. (For `sslMode: verify-ca` or `verify-full`) create a Secret or ConfigMap holding the provider's CA bundle:
   ```sh
   kubectl create secret generic postgres-ca \
     --from-file=ca.crt=<bundle>.pem \
     --namespace governance
   ```

### Example values

A ready-to-use overlay lives at [examples/values-external-postgres.yaml](./examples/values-external-postgres.yaml). Combine it with one of the auth-flavored examples:

```sh
helm upgrade --install governance-platform ./charts/governance-platform \
  --namespace governance \
  --create-namespace \
  --values examples/values-auth0.yaml \
  --values examples/values-external-postgres.yaml
```

### Provider-specific notes

**AWS RDS / Aurora PostgreSQL**

- Host: `<instance>.<region>.rds.amazonaws.com` (or the Aurora cluster endpoint)
- CA bundle: <https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem>
- TLS: every RDS instance supports TLS; `verify-full` is recommended

**Azure Database for PostgreSQL — Flexible Server**

- Host: `<server>.postgres.database.azure.com`
- Username: plain `<username>` (NOT `<username>@<server>` — that's the older Single Server)
- CA bundle: DigiCert Global Root CA — see the Azure PostgreSQL TLS docs for the current CA URL
- TLS: required by default

**GCP Cloud SQL for PostgreSQL**

- Host: the private IP, or the Cloud SQL Auth Proxy sidecar address
- CA bundle: download the server CA from the Cloud SQL instance "Connections" tab
- TLS: optional but recommended

## Storage Provider Configuration

Each service can independently choose its storage provider. Credentials are inherited from global configuration, but provider type and bucket/container names must be explicitly set.

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
    awsS3BucketName: "your-governance-artifacts-bucket"

integrity-service:
  config:
    integrityAppBlobStoreType: "aws_s3"
    integrityAppBlobStoreAwsRegion: "us-east-1"
    integrityAppBlobStoreAwsBucket: "your-integrity-store-bucket"
    integrityAppBlobStoreAwsFolder: "your-integrity-store-folder"
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
    azureStorageAccountName: "your-storage-account"
    azureStorageContainerName: "your-governance-artifacts-container"

integrity-service:
  config:
    integrityAppBlobStoreType: "azure_blob"
    integrityAppBlobStoreAccount: "your-storage-account"
    integrityAppBlobStoreContainer: "your-integrity-store-container"
```

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
    gcsBucketName: "your-governance-artifacts-bucket"
```

## Key Management Provider Configuration

The auth-service uses a key management provider for credential signing. The provider is set globally and credentials are inherited automatically.

### AWS KMS

```yaml
global:
  secrets:
    keyManagement:
      provider: "aws_kms"
      aws_kms:
        secretName: "platform-aws-kms"

auth-service:
  config:
    keyManagement:
      aws_kms:
        region: "us-east-1"
```

### Azure Key Vault

```yaml
global:
  secrets:
    keyManagement:
      provider: "azure_key_vault"
      azure_key_vault:
        secretName: "platform-azure-key-vault"

auth-service:
  config:
    keyManagement:
      azure_key_vault:
        vaultUrl: "https://your-vault.vault.azure.net"
```

### GCP KMS

```yaml
global:
  secrets:
    keyManagement:
      provider: "gcp_kms"
      gcp_kms:
        secretName: "platform-gcp-kms"

auth-service:
  config:
    keyManagement:
      gcp_kms:
        projectId: "your-gcp-project-id"
        locationId: "us-east1"
        keyRingId: "eqtylab-did" # defaults to "eqtylab-did"
        scheduledDestroyDays: 24 # defaults to 24
```

> **Note:** When using GCP Workload Identity or Application Default Credentials, the `gcp_kms.secretName` secret is not required. Only provide it when using explicit service account JSON credentials.

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

### Microsoft Entra ID Configuration

Microsoft Entra ID requires an app registration with OIDC credentials and optional Microsoft Graph API access:

1. **OIDC App Registration** - For token validation (`entra.values.clientId/clientSecret/tenantId`)
2. **Graph API App Registration** (Optional) - For user management via Microsoft Graph (`entra.values.graphClientId/graphClientSecret`)

```yaml
global:
  secrets:
    auth:
      provider: "entra"
      entra:
        secretName: "platform-entra"
        # Credentials are stored in the secret (see below for creation)

governance-studio:
  config:
    authProvider: "entra"
    entraClientId: "your-entra-client-id"
    entraTenantId: "your-tenant-id"
    entraScopes: "openid profile email offline_access api://<backend-client-id>/access_as_user" # Replace <backend-client-id> with Governance Platform Backend app registration ID
    # entraAuthority: "https://login.microsoftonline.com/your-tenant-id"  # optional

auth-service:
  config:
    idp:
      issuer: "https://login.microsoftonline.com/your-tenant-id/v2.0"
      entra:
        tenantId: "your-tenant-id"
        defaultRoles: "user"

governance-service:
  config:
    # entraTenantId auto-configured from secret
```

**Create the Entra secret:**

```bash
kubectl create secret generic platform-entra \
  --from-literal=client-id=YOUR_ENTRA_CLIENT_ID \
  --from-literal=client-secret=YOUR_ENTRA_CLIENT_SECRET \
  --from-literal=tenant-id=YOUR_ENTRA_TENANT_ID \
  --from-literal=graph-client-id=YOUR_GRAPH_CLIENT_ID \
  --from-literal=graph-client-secret=YOUR_GRAPH_CLIENT_SECRET \
  --namespace governance
```

#### Post-Install Database Seed

When using Entra ID, the chart includes an optional post-install/post-upgrade hook that seeds the governance database with the initial organization and platform-admin user. Enable it by setting:

```yaml
entra:
  createOrganization: true # Creates the organization record in the database
  organizationName: "governance"
  displayName: "Governance Studio"
  tenantId: "your-tenant-id" # Required for Graph API user lookup

  createPlatformAdmin: true # Also create the platform-admin user
  platformAdminEmail: "admin@yourorg.onmicrosoft.com" # Must exist in your Entra tenant
```

The hook authenticates to Microsoft Graph API using credentials from the `platform-entra` secret to look up the admin user's Entra Object ID. It waits for database migrations to complete before running and is idempotent (safe to re-run on upgrades).

> **Note:** Unlike Keycloak, the `platformAdminEmail` must be explicitly set and must be an email that exists in your Microsoft Entra tenant (e.g., `user@yourorg.onmicrosoft.com` or `user@yourverifieddomain.com`).

### Keycloak Configuration

Keycloak requires a service account (confidential) client and a SPA (public) client:

1. **Service Account** (Confidential) - For backend API calls (`keycloak.values.serviceAccountClientId/serviceAccountClientSecret`)
2. **Governance Studio** (SPA/Public) - For frontend authentication (configured via `auth-service.config` and `governance-studio.config`)

```yaml
global:
  secrets:
    auth:
      provider: "keycloak"
      keycloak:
        secretName: "platform-keycloak"

    governanceWorker:
      secretName: "platform-governance-worker"

governance-studio:
  config:
    # SPA settings must be explicitly set (public, not secrets)
    keycloakUrl: "https://keycloak.your-domain.com"
    keycloakClientId: "governance-platform-frontend"
    keycloakRealm: "governance"

auth-service:
  config:
    idp:
      keycloak:
        realm: "governance"
        adminUrl: "https://keycloak.your-domain.com"
        clientId: "governance-platform-frontend"
```

#### Post-Install Database Seed

When using Keycloak, the chart includes an optional post-install/post-upgrade hook that seeds the governance database with the initial organization and platform-admin user. Enable it by setting:

```yaml
keycloak:
  createOrganization: true # Creates the organization record in the database
  realmName: "governance" # Must match your Keycloak realm name
  displayName: "Governance Studio"

  createPlatformAdmin: true # Also create the platform-admin user
  platformAdminEmail: "" # Defaults to admin@<global.domain>, looked up in Keycloak automatically
```

The hook waits for database migrations to complete before running and is idempotent (safe to re-run on upgrades).

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
  config:
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
      cert-manager.io/issuer: letsencrypt-prod
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
  config:
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
      # Uses cluster default StorageClass when set to "".
      # Override per CSP if needed: EKS="gp3", AKS="managed-csi", GKE="standard"
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
# Auth Service
kubectl logs -f deployment/governance-platform-auth-service -n governance

# Governance Service
kubectl logs -f deployment/governance-platform-governance-service -n governance

# Governance Studio
kubectl logs -f deployment/governance-platform-governance-studio -n governance

# Integrity Service
kubectl logs -f deployment/governance-platform-integrity-service -n governance
```

### Checking Pod Status

```bash
kubectl get pods -n governance
kubectl describe pod <pod-name> -n governance
```

### Verifying Configuration

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
- For Entra: check tenant ID, client ID, client secret, and issuer URL
- For Keycloak: check URL, realm, and client credentials
- Ensure auth service is running and accessible

**Configuration not applying**

- Remember: service-level config overrides global config
- Check for typos in configuration keys
- Restart pods: `kubectl rollout restart deployment/<deployment-name> -n governance`

### Debug Mode

Enable debug logging for troubleshooting:

```yaml
auth-service:
  config:
    logging:
      level: "debug"

governance-service:
  config:
    logLevel: "debug"

integrity-service:
  config:
    integrityAppLoggingLogLevelDefault: "debug"
```

## Health Endpoints

| Service            | Endpoint                          |
| ------------------ | --------------------------------- |
| Auth Service       | `GET /authService/health`         |
| Governance Service | `GET /governanceService/health`   |
| Governance Studio  | `GET /`                           |
| Integrity Service  | `GET /integrityService/health/v1` |

### API Documentation

Each backend service exposes Swagger/OpenAPI documentation:

| Service            | Swagger UI                                  |
| ------------------ | ------------------------------------------- |
| Auth Service       | `GET /authService/swagger/index.html`       |
| Governance Service | `GET /governanceService/swagger/index.html` |
| Integrity Service  | `GET /integrityService/swagger/index.html`  |

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
