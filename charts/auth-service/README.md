# Auth Service

A Helm chart for deploying the EQTY Lab Auth Service on Kubernetes.

## Description

The Auth Service provides centralized authentication, authorization, and identity management for the Governance Platform. It acts as the security gateway for all platform services, handling user authentication, RBAC permissions, and service-to-service authentication. This chart can be deployed standalone or as part of the Governance Platform umbrella chart.

Key capabilities:

- **Identity Provider Integration**: Native support for Auth0 and Keycloak
- **RBAC Authorization**: Fine-grained permission management with caching
- **Service Accounts**: Machine-to-machine authentication for platform workers
- **DID Key Management**: Integration with Azure Key Vault for credential signing
- **Token Exchange**: Keycloak token exchange support for federated authentication

## Configuration Model

Auth Service uses runtime configuration injection via environment variables. Application configuration is provided through Helm values and injected into the container at startup.

This allows:

- A single immutable container image across environments
- Configuration changes without rebuilding images
- Clear separation of infrastructure and application settings
- Automatic configuration inheritance from umbrella chart globals

## Deployment Options

### Option 1: As Part of Governance Platform (Recommended)

When deployed via the `governance-platform` umbrella chart, Auth Service automatically inherits configuration from global values with zero additional configuration required.

**Example umbrella chart configuration:**

```yaml
global:
  domain: "governance.yourcompany.com"
  environmentType: "production"

  postgresql:
    host: ""
    port: 5432
    database: "governance"
    username: "postgres"

  secrets:
    database:
      secretName: "platform-database"
      keys:
        password: "password"

    auth:
      provider: "auth0"
      auth0:
        secretName: "platform-auth0"
        management:
          audience: "https://yourcompany.us.auth0.com/api/v2/"

    authService:
      secretName: "platform-auth-service"
      keys:
        apiSecret: "api-secret"
        jwtSecret: "jwt-secret"
        sessionSecret: "session-secret"

    secretManager:
      provider: "azure_key_vault"
      azure_key_vault:
        secretName: "platform-azure-key-vault"
        values:
          vaultUrl: "https://your-vault.vault.azure.net/"
          tenantId: "your-tenant-id"

    governanceWorker:
      secretName: "platform-governance-worker"

auth-service:
  enabled: true
  replicaCount: 2

  config:
    idp:
      auth0:
        domain: "yourcompany.us.auth0.com"
        managementAudience: "https://yourcompany.us.auth0.com/api/v2/"
        apiIdentifier: "https://governance.yourcompany.com"

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

- Database connection (host, port, credentials)
- Identity provider configuration (Auth0 or Keycloak)
- Security secrets (API, JWT, session)
- Key Vault credentials (for DID signing)
- Worker credentials
- Environment type
- Image pull secrets
- Integration service URLs

### Option 2: Standalone Deployment

For standalone deployments outside the umbrella chart:

```yaml
enabled: true

externalDatabase:
  host: "postgresql.default.svc.cluster.local"
  name: "governance"
  user: "postgres"
  password: "YOUR_PASSWORD" # Or use secret reference

config:
  server:
    environment: "production"
  logging:
    level: "info"

  idp:
    provider: "auth0"
    issuer: "https://yourcompany.us.auth0.com/"
    auth0:
      domain: "yourcompany.us.auth0.com"
      enableManagementAPI: true
      managementAudience: "https://yourcompany.us.auth0.com/api/v2/"
      apiIdentifier: "https://governance.yourcompany.com"

  keyVault:
    provider: "azure"
    azure:
      vaultUrl: "https://your-vault.vault.azure.net/"
      tenantId: "your-tenant-id"

  integrations:
    governanceServiceUrl: "http://governance-service:10001"

secrets:
  auth:
    auth0:
      name: "auth0-credentials"
  authService:
    name: "auth-service-security"
  secretManager:
    azure_key_vault:
      name: "azure-key-vault-credentials"
  governanceWorker:
    name: "governance-worker-credentials"

service:
  enabled: true
  type: ClusterIP
  port: 8080

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/rewrite-target: /$2
  hosts:
    - host: governance.yourcompany.com
      paths:
        - path: "/authService(/|$)(.*)"
          pathType: ImplementationSpecific
  tls:
    - secretName: auth-service-tls
      hosts:
        - governance.yourcompany.com

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- PostgreSQL database (provided by umbrella chart or external)
- Authentication provider (Auth0 or Keycloak)
- Azure Key Vault (for DID key signing)
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
# Create required secrets first
kubectl create secret generic platform-auth0 \
  --from-literal=client-id=YOUR_CLIENT_ID \
  --from-literal=client-secret=YOUR_CLIENT_SECRET \
  --namespace governance

kubectl create secret generic platform-database \
  --from-literal=password=YOUR_DB_PASSWORD \
  --namespace governance

kubectl create secret generic platform-auth-service \
  --from-literal=api-secret=$(openssl rand -base64 32) \
  --from-literal=jwt-secret=$(openssl rand -base64 32) \
  --from-literal=session-secret=$(openssl rand -base64 32) \
  --namespace governance

# Install the chart
helm install auth-service eqtylab/auth-service \
  -f values.yaml \
  --namespace governance \
  --create-namespace
```

## Uninstalling the Chart

```bash
helm uninstall auth-service --namespace governance
```

This removes all Kubernetes components associated with the chart and deletes the release.

## Values

### Global Parameters (Umbrella Chart)

When deployed via the umbrella chart, these global values are automatically used:

| Key                                                     | Type   | Description                                       |
| ------------------------------------------------------- | ------ | ------------------------------------------------- |
| global.domain                                           | string | Base domain for all services                      |
| global.environmentType                                  | string | Environment type (development/staging/production) |
| global.postgresql.host                                  | string | PostgreSQL host                                   |
| global.postgresql.port                                  | int    | PostgreSQL port                                   |
| global.postgresql.database                              | string | PostgreSQL database name                          |
| global.postgresql.username                              | string | PostgreSQL username                               |
| global.secrets.database.secretName                      | string | Name of database credentials secret               |
| global.secrets.auth.provider                            | string | Auth provider (auth0 or keycloak)                 |
| global.secrets.auth.auth0.secretName                    | string | Auth0 credentials secret name                     |
| global.secrets.auth.keycloak.secretName                 | string | Keycloak credentials secret name                  |
| global.secrets.authService.secretName                   | string | Auth service security secrets name                |
| global.secrets.secretManager.provider                   | string | Secret manager provider (azure_key_vault)         |
| global.secrets.secretManager.azure_key_vault.secretName | string | Azure Key Vault credentials secret name           |
| global.secrets.governanceWorker.secretName              | string | Worker credentials secret name                    |

### Chart-Specific Parameters

| Key              | Type   | Default                          | Description                                           |
| ---------------- | ------ | -------------------------------- | ----------------------------------------------------- |
| enabled          | bool   | `true`                           | Enable this subchart (umbrella chart only)            |
| replicaCount     | int    | `2`                              | Number of replicas to deploy                          |
| image.repository | string | `"ghcr.io/eqtylab/auth-service"` | Container image repository                            |
| image.pullPolicy | string | `"IfNotPresent"`                 | Image pull policy                                     |
| image.tag        | string | `""`                             | Overrides the image tag (default is chart appVersion) |
| imagePullSecrets | list   | `[]`                             | Additional image pull secrets (beyond global)         |

### Service Account

| Key                        | Type   | Default | Description                                              |
| -------------------------- | ------ | ------- | -------------------------------------------------------- |
| serviceAccount.create      | bool   | `true`  | Specifies whether a service account should be created    |
| serviceAccount.automount   | bool   | `true`  | Automatically mount the ServiceAccount's API credentials |
| serviceAccount.annotations | object | `{}`    | Annotations to add to the service account                |
| serviceAccount.name        | string | `""`    | The name of the service account (generated if not set)   |

### Security

| Key                                      | Type   | Default | Description                    |
| ---------------------------------------- | ------ | ------- | ------------------------------ |
| podAnnotations                           | object | `{}`    | Annotations to add to pods     |
| podLabels                                | object | `{}`    | Labels to add to pods          |
| podSecurityContext.runAsNonRoot          | bool   | `true`  | Run container as non-root user |
| podSecurityContext.runAsUser             | int    | `1000`  | User ID to run container       |
| podSecurityContext.fsGroup               | int    | `1000`  | Filesystem group               |
| securityContext.allowPrivilegeEscalation | bool   | `false` | Prevent privilege escalation   |
| securityContext.capabilities.drop        | list   | `[ALL]` | Drop all capabilities          |
| securityContext.readOnlyRootFilesystem   | bool   | `true`  | Read-only root filesystem      |
| securityContext.runAsNonRoot             | bool   | `true`  | Run as non-root user           |
| securityContext.runAsUser                | int    | `1000`  | User ID to run container       |

### Service

| Key             | Type   | Default       | Description               |
| --------------- | ------ | ------------- | ------------------------- |
| service.enabled | bool   | `true`        | Create a Service resource |
| service.type    | string | `"ClusterIP"` | Kubernetes service type   |
| service.port    | int    | `8080`        | Service port              |

### Ingress

| Key                 | Type   | Default                                                                                                         | Description                 |
| ------------------- | ------ | --------------------------------------------------------------------------------------------------------------- | --------------------------- |
| ingress.enabled     | bool   | `false`                                                                                                         | Enable ingress              |
| ingress.className   | string | `""`                                                                                                            | Ingress class name          |
| ingress.annotations | object | `{}`                                                                                                            | Ingress annotations         |
| ingress.hosts       | list   | `[{"host":"auth.example.com","paths":[{"path":"/authService(/\|$)(.*)","pathType":"ImplementationSpecific"}]}]` | Ingress hosts configuration |
| ingress.tls         | list   | `[]`                                                                                                            | Ingress TLS configuration   |

### Resources

| Key                                           | Type   | Default | Description                          |
| --------------------------------------------- | ------ | ------- | ------------------------------------ |
| resources.limits.cpu                          | string | `500m`  | CPU limit                            |
| resources.limits.memory                       | string | `512Mi` | Memory limit                         |
| resources.requests.cpu                        | string | `100m`  | CPU request                          |
| resources.requests.memory                     | string | `128Mi` | Memory request                       |
| autoscaling.enabled                           | bool   | `false` | Enable horizontal pod autoscaling    |
| autoscaling.minReplicas                       | int    | `2`     | Minimum number of replicas           |
| autoscaling.maxReplicas                       | int    | `10`    | Maximum number of replicas           |
| autoscaling.targetCPUUtilizationPercentage    | int    | `80`    | Target CPU utilization percentage    |
| autoscaling.targetMemoryUtilizationPercentage | int    | `80`    | Target memory utilization percentage |

### High Availability

| Key                              | Type | Default | Description                                                                                           |
| -------------------------------- | ---- | ------- | ----------------------------------------------------------------------------------------------------- |
| podDisruptionBudget.enabled      | bool | `true`  | Enable Pod Disruption Budget                                                                          |
| podDisruptionBudget.minAvailable | int  | `1`     | Minimum available pods during disruptions (only applied when replicaCount > 1 or autoscaling.enabled) |

### Node Scheduling

| Key          | Type   | Default           | Description                                   |
| ------------ | ------ | ----------------- | --------------------------------------------- |
| nodeSelector | object | `{}`              | Node labels for pod assignment                |
| tolerations  | list   | `[]`              | Tolerations for pod assignment                |
| affinity     | object | Pod anti-affinity | Affinity rules (default spreads across nodes) |

### Health Checks

| Key                                | Type   | Default     | Description                   |
| ---------------------------------- | ------ | ----------- | ----------------------------- |
| startupProbe.httpGet.path          | string | `"/health"` | Startup probe HTTP path       |
| startupProbe.httpGet.port          | string | `"http"`    | Startup probe port            |
| startupProbe.periodSeconds         | int    | `10`        | Startup probe period          |
| startupProbe.failureThreshold      | int    | `30`        | Startup failure threshold     |
| livenessProbe.httpGet.path         | string | `"/health"` | Liveness probe HTTP path      |
| livenessProbe.httpGet.port         | string | `"http"`    | Liveness probe port           |
| livenessProbe.initialDelaySeconds  | int    | `30`        | Liveness probe initial delay  |
| livenessProbe.periodSeconds        | int    | `10`        | Liveness probe period         |
| livenessProbe.timeoutSeconds       | int    | `5`         | Liveness probe timeout        |
| livenessProbe.failureThreshold     | int    | `3`         | Liveness failure threshold    |
| livenessProbe.successThreshold     | int    | `1`         | Liveness success threshold    |
| readinessProbe.httpGet.path        | string | `"/health"` | Readiness probe HTTP path     |
| readinessProbe.httpGet.port        | string | `"http"`    | Readiness probe port          |
| readinessProbe.initialDelaySeconds | int    | `10`        | Readiness probe initial delay |
| readinessProbe.periodSeconds       | int    | `5`         | Readiness probe period        |
| readinessProbe.timeoutSeconds      | int    | `3`         | Readiness probe timeout       |
| readinessProbe.failureThreshold    | int    | `3`         | Readiness failure threshold   |
| readinessProbe.successThreshold    | int    | `1`         | Readiness success threshold   |

### Database Configuration

| Key                                        | Type   | Default                           | Description                                                               |
| ------------------------------------------ | ------ | --------------------------------- | ------------------------------------------------------------------------- |
| externalDatabase.host                      | string | `""`                              | Database host (auto-set from global or generated as {Release}-postgresql) |
| externalDatabase.port                      | string | `""`                              | Database port (auto-set from global, default 5432)                        |
| externalDatabase.name                      | string | `""`                              | Database name (auto-set from global, default "governance")                |
| externalDatabase.user                      | string | `""`                              | Database user (auto-set from global, default "postgres")                  |
| externalDatabase.password                  | string | `""`                              | Database password (leave empty to use secret reference)                   |
| externalDatabase.sslMode                   | string | `"disable"`                       | SSL mode (disable/require/verify-ca/verify-full)                          |
| externalDatabase.maxOpenConns              | int    | `25`                              | Maximum open connections                                                  |
| externalDatabase.maxIdleConns              | int    | `5`                               | Maximum idle connections                                                  |
| externalDatabase.connMaxLifetime           | string | `"5m"`                            | Connection maximum lifetime                                               |
| externalDatabase.passwordSecretKeyRef.name | string | `""`                              | Secret name containing database password                                  |
| externalDatabase.passwordSecretKeyRef.key  | string | `""`                              | Secret key name for password                                              |
| migrations.runAtStartup                    | bool   | `true`                            | Run database migrations automatically at startup                          |
| migrations.path                            | string | `"/internal/database/migrations"` | Path to migration files                                                   |

### Secret Configuration

All secret references support global fallbacks when deployed via umbrella chart.

#### Secret Key Names

Secret key names (the keys within each Kubernetes Secret) follow this pattern:

- **Umbrella chart deployment**: Key names are defined in `global.secrets.*.keys` - this is the single source of truth
- **Standalone deployment**: Templates use hardcoded defaults (e.g., `client-id`, `client-secret`, `api-secret`)

When deploying standalone, create your secrets using the default key names:

```bash
# Example: Auth0 credentials with default key names
kubectl create secret generic auth-service-auth \
  --from-literal=client-id=YOUR_CLIENT_ID \
  --from-literal=client-secret=YOUR_CLIENT_SECRET \
  --from-literal=mgmt-client-id=YOUR_MGMT_CLIENT_ID \
  --from-literal=mgmt-client-secret=YOUR_MGMT_CLIENT_SECRET

# Example: Security secrets with default key names
kubectl create secret generic auth-service-security \
  --from-literal=api-secret=$(openssl rand -base64 32) \
  --from-literal=jwt-secret=$(openssl rand -base64 32) \
  --from-literal=session-secret=$(openssl rand -base64 32)
```

If your existing secrets use different key names, you can override them via `global.secrets.*.keys` in your values file.

**Default key names by secret type:**

| Secret Type  | Default Key Names                                                    |
| ------------ | -------------------------------------------------------------------- |
| Auth0        | `client-id`, `client-secret`, `mgmt-client-id`, `mgmt-client-secret` |
| Keycloak     | `backend-client-id`, `backend-client-secret`                         |
| Auth Service | `api-secret`, `jwt-secret`, `session-secret`                         |
| Key Vault    | `client-id`, `client-secret`, `tenant-id`, `vault-url`               |
| Worker       | `encryption-key`, `client-id`, `client-secret`                       |

#### Auth0 Secret (only used when auth provider is Auth0)

| Key                     | Type   | Description                              |
| ----------------------- | ------ | ---------------------------------------- |
| secrets.auth.auth0.name | string | Secret name (auto-populated from global) |

#### Keycloak Secret (only used when auth provider is Keycloak)

| Key                        | Type   | Description                              |
| -------------------------- | ------ | ---------------------------------------- |
| secrets.auth.keycloak.name | string | Secret name (auto-populated from global) |

#### Auth Service Secret

| Key                      | Type   | Description                                                              |
| ------------------------ | ------ | ------------------------------------------------------------------------ |
| secrets.authService.name | string | Secret name (auto-configured from global.secrets.authService.secretName) |

#### Secret Manager Secret

| Key                                        | Type   | Description                                                                                |
| ------------------------------------------ | ------ | ------------------------------------------------------------------------------------------ |
| secrets.secretManager.azure_key_vault.name | string | Secret name (auto-configured from global.secrets.secretManager.azure_key_vault.secretName) |

#### Governance Worker Secret

| Key                           | Type   | Description                                                                   |
| ----------------------------- | ------ | ----------------------------------------------------------------------------- |
| secrets.governanceWorker.name | string | Secret name (auto-configured from global.secrets.governanceWorker.secretName) |

### Application Configuration

#### Server Settings

| Key                          | Type   | Default     | Description                        |
| ---------------------------- | ------ | ----------- | ---------------------------------- |
| config.server.port           | int    | `8080`      | Server port                        |
| config.server.host           | string | `"0.0.0.0"` | Server host                        |
| config.server.readTimeout    | string | `"30s"`     | Read timeout                       |
| config.server.writeTimeout   | string | `"30s"`     | Write timeout                      |
| config.server.idleTimeout    | string | `"120s"`    | Idle timeout                       |
| config.server.environment    | string | `""`        | Environment (auto-set from global) |
| config.server.swaggerEnabled | bool   | `false`     | Enable Swagger documentation       |

#### Logging Configuration

| Key                      | Type   | Default                                         | Description                       |
| ------------------------ | ------ | ----------------------------------------------- | --------------------------------- |
| config.logging.level     | string | `"info"`                                        | Log level (debug/info/warn/error) |
| config.logging.format    | string | `"json"`                                        | Log format (json/text)            |
| config.logging.skipPaths | string | `"/health,/health/live,/health/ready,/metrics"` | Paths to skip in logs             |

#### CORS Configuration

| Key                 | Type   | Default | Description                              |
| ------------------- | ------ | ------- | ---------------------------------------- |
| config.cors.enabled | bool   | `false` | Enable CORS (usually handled by ingress) |
| config.cors.origins | string | `"*"`   | Allowed origins                          |

#### Identity Provider Configuration

| Key                               | Type   | Default | Description                         |
| --------------------------------- | ------ | ------- | ----------------------------------- |
| config.idp.provider               | string | `""`    | IDP type (auto-set from global)     |
| config.idp.issuer                 | string | `""`    | OIDC issuer URL                     |
| config.idp.skipIssuerVerification | bool   | `false` | Skip issuer verification (dev only) |

**Auth0 Configuration (only used when provider is "auth0"):**

| Key                                  | Type   | Default                              | Description                               |
| ------------------------------------ | ------ | ------------------------------------ | ----------------------------------------- |
| config.idp.auth0.domain              | string | `""`                                 | Auth0 tenant domain (**must be set**)     |
| config.idp.auth0.enableManagementAPI | bool   | `true`                               | Enable Management API                     |
| config.idp.auth0.managementAudience  | string | `""`                                 | Management API audience (**must be set**) |
| config.idp.auth0.apiIdentifier       | string | `""`                                 | API identifier (**must be set**)          |
| config.idp.auth0.defaultConnection   | string | `"Username-Password-Authentication"` | Default connection                        |
| config.idp.auth0.defaultRoles        | list   | `["user"]`                           | Default roles for new users               |
| config.idp.auth0.sendInvitationEmail | bool   | `true`                               | Send invitation email on user creation    |
| config.idp.auth0.syncAtStartup       | bool   | `false`                              | Sync organizations at startup             |
| config.idp.auth0.syncPageSize        | int    | `100`                                | Page size for Auth0 API calls             |

**Keycloak Configuration (only used when provider is "keycloak"):**

| Key                                      | Type   | Default | Description               |
| ---------------------------------------- | ------ | ------- | ------------------------- |
| config.idp.keycloak.realm                | string | `""`    | Keycloak realm (auto-set) |
| config.idp.keycloak.adminUrl             | string | `""`    | Admin URL for operations  |
| config.idp.keycloak.enableUserManagement | bool   | `false` | Enable user management    |
| config.idp.keycloak.enableGroupSync      | bool   | `false` | Enable group sync         |

#### Key Vault Configuration

| Key                               | Type   | Default | Description                                |
| --------------------------------- | ------ | ------- | ------------------------------------------ |
| config.keyVault.provider          | string | `""`    | Key Vault provider (auto-set from global)  |
| config.keyVault.cacheTTLMinutes   | int    | `15`    | DID key cache TTL                          |
| config.keyVault.azure.vaultUrl    | string | `""`    | Azure Key Vault URL (auto-set from global) |
| config.keyVault.azure.tenantId    | string | `""`    | Azure tenant ID (auto-set from global)     |
| config.keyVault.hashicorp.address | string | `""`    | HashiCorp Vault address                    |

#### Service Integration

| Key                                      | Type   | Default | Description                                               |
| ---------------------------------------- | ------ | ------- | --------------------------------------------------------- |
| config.integrations.governanceServiceUrl | string | `""`    | Governance Service URL (auto-generated from Release.Name) |

#### Service Account Configuration

| Key                                                 | Type   | Default                     | Description                      |
| --------------------------------------------------- | ------ | --------------------------- | -------------------------------- |
| config.serviceAccounts.autoCreate                   | bool   | `true`                      | Auto-create service accounts     |
| config.serviceAccounts.governanceWorker.enabled     | bool   | `true`                      | Enable governance worker account |
| config.serviceAccounts.governanceWorker.name        | string | `"governance-worker"`       | Worker account name              |
| config.serviceAccounts.governanceWorker.description | string | `"Automated governance..."` | Worker description               |
| config.serviceAccounts.governanceWorker.scopes      | list   | See values.yaml             | Worker scopes                    |
| config.serviceAccounts.governanceWorker.audience    | string | `""`                        | Auth0 API audience (auto-set)    |

#### Token Exchange Configuration

| Key                          | Type   | Default                   | Description                      |
| ---------------------------- | ------ | ------------------------- | -------------------------------- |
| config.tokenExchange.enabled | bool   | `false`                   | Enable token exchange (Keycloak) |
| config.tokenExchange.keyId   | string | `"auth-service-prod-001"` | Key identifier for signing key   |

#### RBAC Configuration

| Key                       | Type   | Default  | Description           |
| ------------------------- | ------ | -------- | --------------------- |
| config.rbac.cache.enabled | bool   | `true`   | Enable RBAC cache     |
| config.rbac.cache.ttl     | string | `"300s"` | Cache TTL             |
| config.rbac.cache.maxSize | int    | `1000`   | Maximum cache entries |

#### Rate Limiting Configuration

| Key                                | Type | Default | Description          |
| ---------------------------------- | ---- | ------- | -------------------- |
| config.rateLimit.enabled           | bool | `false` | Enable rate limiting |
| config.rateLimit.requestsPerMinute | int  | `60`    | Requests per minute  |

### Metrics Configuration

| Key                                  | Type   | Default      | Description                      |
| ------------------------------------ | ------ | ------------ | -------------------------------- |
| metrics.enabled                      | bool   | `false`      | Enable Prometheus metrics        |
| metrics.port                         | int    | `9090`       | Metrics port                     |
| metrics.path                         | string | `"/metrics"` | Metrics path                     |
| metrics.serviceMonitor.enabled       | bool   | `false`      | Enable ServiceMonitor            |
| metrics.serviceMonitor.interval      | string | `"30s"`      | Scrape interval                  |
| metrics.serviceMonitor.scrapeTimeout | string | `"10s"`      | Scrape timeout                   |
| metrics.serviceMonitor.labels        | object | `{}`         | Additional ServiceMonitor labels |

### Network Policy Configuration

| Key                   | Type | Default         | Description          |
| --------------------- | ---- | --------------- | -------------------- |
| networkPolicy.enabled | bool | `false`         | Enable NetworkPolicy |
| networkPolicy.ingress | list | See values.yaml | Ingress rules        |
| networkPolicy.egress  | list | See values.yaml | Egress rules         |

### Migration Job Configuration

| Key                                 | Type   | Default | Description                   |
| ----------------------------------- | ------ | ------- | ----------------------------- |
| migration.enabled                   | bool   | `false` | Enable migration as Helm hook |
| migration.backoffLimit              | int    | `3`     | Job backoff limit             |
| migration.activeDeadlineSeconds     | int    | `300`   | Job active deadline           |
| migration.ttlSecondsAfterFinished   | int    | `300`   | TTL for completed jobs        |
| migration.resources.limits.cpu      | string | `200m`  | Migration job CPU limit       |
| migration.resources.limits.memory   | string | `256Mi` | Migration job memory limit    |
| migration.resources.requests.cpu    | string | `100m`  | Migration job CPU request     |
| migration.resources.requests.memory | string | `128Mi` | Migration job memory request  |

### Extra Configuration

| Key                   | Type   | Default | Description                               |
| --------------------- | ------ | ------- | ----------------------------------------- |
| volumes               | list   | `[]`    | Additional volumes on the Deployment      |
| volumeMounts          | list   | `[]`    | Additional volumeMounts on the Deployment |
| extraEnvVars          | list   | `[]`    | Extra environment variables               |
| extraEnvVarsSecret    | string | `""`    | Secret containing extra env vars          |
| extraEnvVarsConfigMap | string | `""`    | ConfigMap containing extra env vars       |
| extraContainers       | list   | `[]`    | Extra containers to add to the pod        |
| extraInitContainers   | list   | `[]`    | Extra init containers to add to the pod   |
| extraManifests        | list   | `[]`    | Extra manifests to deploy                 |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level config values** - Explicitly set in `auth-service.config.*`
2. **Global values** - Set in `global.*` (umbrella chart)
3. **Chart defaults** - Default values from `values.yaml`

### Example Configuration Flow

```yaml
# Umbrella chart values.yaml
global:
  domain: "governance.prod.company.com"
  environmentType: "production"
  postgresql:
    database: "governance"
    username: "postgres"
  secrets:
    auth:
      provider: "auth0"
      auth0:
        secretName: "platform-auth0"

auth-service:
  enabled: true
  # config.server.environment automatically becomes: production
  # config.idp.provider automatically becomes: auth0
  # externalDatabase.name automatically becomes: governance
  # externalDatabase.user automatically becomes: postgres

  # Must explicitly set:
  config:
    idp:
      auth0:
        domain: "company.us.auth0.com"
        managementAudience: "https://company.us.auth0.com/api/v2/"
        apiIdentifier: "https://governance.company.com"
```

## Auth0 Configuration

### Required Auth0 Setup

1. **Create a Regular Web Application** for user authentication
2. **Create a Machine-to-Machine Application** for Management API access
3. **Enable Management API** permissions for the M2M application
4. **Create an API** for the governance platform

### Example Configuration

```yaml
config:
  idp:
    provider: "auth0"
    issuer: "https://your-tenant.us.auth0.com/"
    auth0:
      domain: "your-tenant.us.auth0.com"
      enableManagementAPI: true
      managementAudience: "https://your-tenant.us.auth0.com/api/v2/"
      apiIdentifier: "https://governance.yourcompany.com"
      defaultConnection: "Username-Password-Authentication"
      defaultRoles: ["user"]
      syncAtStartup: true

secrets:
  auth:
    name: "platform-auth0"
    keys:
      clientId: "client-id"
      clientSecret: "client-secret"
```

### Secret Creation

```bash
kubectl create secret generic platform-auth0 \
  --from-literal=client-id=YOUR_AUTH0_CLIENT_ID \
  --from-literal=client-secret=YOUR_AUTH0_CLIENT_SECRET \
  --namespace governance
```

## Keycloak Configuration

### Required Keycloak Setup

1. **Create a Realm** for the governance platform
2. **Create a Confidential Client** for backend authentication
3. **Create a Public Client** for frontend authentication
4. **Configure Token Exchange** (if using federated auth)

### Example Configuration

```yaml
config:
  idp:
    provider: "keycloak"
    issuer: "https://keycloak.example.com/realms/governance"
    keycloak:
      realm: "governance"
      adminUrl: "https://keycloak.example.com"
      enableUserManagement: true

  tokenExchange:
    enabled: true
    keyId: "auth-service-prod-001"

secrets:
  auth:
    name: "platform-keycloak"
    keys:
      clientId: "client-id"
      clientSecret: "client-secret"
```

## Azure Key Vault Configuration

### Required Azure Setup

1. **Create an Azure Key Vault**
2. **Create a Service Principal** with Key Vault access
3. **Grant Key permissions** (Get, Sign, Verify)

### Example Configuration

```yaml
config:
  keyVault:
    provider: "azure"
    cacheTTLMinutes: 15
    azure:
      vaultUrl: "https://your-vault.vault.azure.net/"
      tenantId: "your-azure-tenant-id"

secrets:
  secretManager:
    azure_key_vault:
      name: "platform-azure-key-vault"
```

### Secret Creation

```bash
kubectl create secret generic platform-azure-key-vault \
  --from-literal=client-id=YOUR_AZURE_CLIENT_ID \
  --from-literal=client-secret=YOUR_AZURE_CLIENT_SECRET \
  --from-literal=tenant-id=YOUR_AZURE_TENANT_ID \
  --from-literal=vault-url=https://your-vault.vault.azure.net/ \
  --namespace governance
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
helm upgrade auth-service eqtylab/auth-service \
  -f values.yaml \
  --namespace governance
```

## Troubleshooting

### Viewing Logs

```bash
kubectl logs -f deployment/auth-service -n governance
```

### Checking Pod Status

```bash
kubectl get pods -n governance -l app.kubernetes.io/name=auth-service
kubectl describe pod <pod-name> -n governance
```

### Testing Configuration

View environment variables in running pod:

```bash
kubectl exec -it deployment/auth-service -n governance -- env | sort
```

Test health endpoint:

```bash
kubectl exec -it deployment/auth-service -n governance -- curl localhost:8080/health
```

### Common Issues

**Authentication failures**

- Verify `config.idp.provider` matches your identity provider
- Check Auth0/Keycloak domain and client credentials
- Ensure `config.idp.issuer` is correct
- For development, try `config.idp.skipIssuerVerification: true`

**Database connection errors**

- Verify database host is correct (should be PostgreSQL service name)
- Check database credentials in secret
- Ensure database name matches `externalDatabase.name`
- Verify migrations completed successfully
- Check network policies allow traffic between services

**Key Vault errors**

- Verify Azure Key Vault URL and credentials
- Check service principal has required permissions
- Ensure tenant ID is correct

**Service account issues**

- Verify worker credentials secret exists
- Check Auth0 M2M application permissions
- Ensure audience matches Auth0 API identifier

**Configuration not applying**

- Remember: service-level config overrides global config
- Check for typos in global value paths
- Restart pods if configuration was updated: `kubectl rollout restart deployment/auth-service -n governance`

## Health Endpoints

| Endpoint            | Description          |
| ------------------- | -------------------- |
| `GET /health`       | Overall health check |
| `GET /health/live`  | Liveness probe       |
| `GET /health/ready` | Readiness probe      |

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://docs.eqtylab.io
- GitHub: https://github.com/eqtylab/governance-studio-infrastructure
