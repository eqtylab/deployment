# Auth Service

A Helm chart for deploying the EQTY Lab Auth Service on Kubernetes.

## Description

The Auth Service provides centralized authentication, authorization, and identity management for the Governance Platform. It acts as the security gateway for all platform services, handling user authentication, RBAC permissions, and service-to-service authentication.

Key capabilities:

- **Identity Provider Integration**: Native support for Auth0, Keycloak, and Microsoft Entra ID
- **RBAC Authorization**: Fine-grained permission management with caching
- **Service Accounts**: Machine-to-machine authentication for platform workers
- **DID Key Management**: Integration with Azure Key Vault for credential signing
- **Token Exchange**: Keycloak token exchange support for federated authentication

## Configuration Model

Auth Service uses runtime configuration injected via environment variables. Application configuration is provided through Helm values and injected into the container at startup.

This allows:

- A single immutable container image across environments
- Configuration changes without rebuilding images
- Clear separation of infrastructure and application settings
- Automatic configuration inheritance from umbrella chart globals

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- PostgreSQL database (provided by umbrella chart or external)
- Authentication provider (Auth0, Keycloak, or Entra ID)
- Azure Key Vault (for DID key signing)
- Ingress controller (NGINX, Traefik, etc.)
- TLS certificates (manual or via cert-manager)

## Deployment

When deployed via the `governance-platform` umbrella chart, Auth Service automatically inherits configuration from global values with no additional configuration required.

### Quick Start

Minimum configuration required in your umbrella chart values:

**Auth0:**

```yaml
auth-service:
  image:
    tag: ""
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/rewrite-target: "/$2"
      nginx.ingress.kubernetes.io/enable-cors: "true"
      nginx.ingress.kubernetes.io/proxy-body-size: "64m"
      nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
      nginx.ingress.kubernetes.io/client-header-buffer-size: "16k"
      nginx.ingress.kubernetes.io/large-client-header-buffers: "4 16k"
    hosts:
      - host: "governance.yourcompany.com"
        paths:
          - path: "/authService(/|$)(.*)"
            pathType: "ImplementationSpecific"
    tls:
      - secretName: "auth-service-tls"
        hosts:
          - "governance.yourcompany.com"
  config:
    idp:
      provider: "auth0"
      issuer: "https://your-tenant.us.auth0.com/"
      auth0:
        domain: "your-tenant.us.auth0.com"
        managementAudience: "https://your-tenant.us.auth0.com/api/v2/"
        apiIdentifier: "https://governance.yourcompany.com"
    # Key Vault Configuration (for DID keys)
    keyVault:
      provider: "azure_key_vault"
      azure:
        vaultUrl: "https://your-vault.vault.azure.net/"
        tenantId: "your-azure-tenant-id"
    # Service Account Configuration
    serviceAccounts:
      governanceWorker:
        audience: "https://governance.yourcompany.com"
```

**Keycloak:**

```yaml
auth-service:
  image:
    tag: ""
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/rewrite-target: "/$2"
      nginx.ingress.kubernetes.io/enable-cors: "true"
      nginx.ingress.kubernetes.io/proxy-body-size: "64m"
      nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
      nginx.ingress.kubernetes.io/client-header-buffer-size: "16k"
      nginx.ingress.kubernetes.io/large-client-header-buffers: "4 16k"
    hosts:
      - host: "governance.yourcompany.com"
        paths:
          - path: "/authService(/|$)(.*)"
            pathType: "ImplementationSpecific"
    tls:
      - secretName: "auth-service-tls"
        hosts:
          - "governance.yourcompany.com"
  config:
    idp:
      provider: "keycloak"
      issuer: "https://keycloak.yourcompany.com/realms/governance"
      keycloak:
        realm: "governance"
        adminUrl: "https://keycloak.yourcompany.com"
        clientId: "governance-platform-frontend"
        enableUserManagement: true
        enableGroupSync: false
    # Key Vault Configuration (for DID keys)
    keyVault:
      provider: "azure_key_vault"
      azure:
        vaultUrl: "https://your-vault.vault.azure.net/"
        tenantId: "your-azure-tenant-id"
    # Service Account Configuration
    serviceAccounts:
      governanceWorker:
        audience: "https://keycloak.yourcompany.com/realms/governance"
    tokenExchange:
      enabled: true
      keyId: "auth-service-prod-001"
```

**Microsoft Entra ID:**

```yaml
auth-service:
  image:
    tag: ""
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/rewrite-target: "/$2"
      nginx.ingress.kubernetes.io/enable-cors: "true"
      nginx.ingress.kubernetes.io/proxy-body-size: "64m"
      nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
      nginx.ingress.kubernetes.io/client-header-buffer-size: "16k"
      nginx.ingress.kubernetes.io/large-client-header-buffers: "4 16k"
    hosts:
      - host: "governance.yourcompany.com"
        paths:
          - path: "/authService(/|$)(.*)"
            pathType: "ImplementationSpecific"
    tls:
      - secretName: "auth-service-tls"
        hosts:
          - "governance.yourcompany.com"
  config:
    idp:
      provider: "entra"
      issuer: "https://login.microsoftonline.com/your-tenant-id/v2.0"
      entra:
        tenantId: "your-tenant-id"
        defaultRoles: "user"
    # Key Vault Configuration (for DID keys)
    keyVault:
      provider: "azure_key_vault"
      azure:
        vaultUrl: "https://your-vault.vault.azure.net/"
        tenantId: "your-azure-tenant-id"
```

### Required Configuration

Beyond what is auto-configured, these values **must** be explicitly set:

**Auth0:**

- `config.idp.auth0.domain` - Auth0 tenant domain (e.g., `your-tenant.us.auth0.com`)
- `config.idp.auth0.managementAudience` - Management API audience, the URL of your Auth0 tenant's Management API (e.g., `https://your-tenant.us.auth0.com/api/v2/`)
- `config.idp.auth0.apiIdentifier` - API identifier, the logical identifier for your governance platform API registered in Auth0 (e.g., `https://governance.yourcompany.com`). This is distinct from `managementAudience`; it identifies _your_ API, not Auth0's Management API.

**Keycloak:**

- `config.idp.keycloak.realm` - Realm name (e.g., `governance`)
- `config.idp.keycloak.adminUrl` - Keycloak server URL (e.g., `https://keycloak.example.com`)
- `config.idp.keycloak.clientId` - Frontend SPA client ID (public, e.g., `governance-platform-frontend`)
- `config.idp.issuer` - Recommended: OIDC issuer URL (e.g., `https://keycloak.example.com/realms/governance`)

**Microsoft Entra ID:**

- `config.idp.entra.tenantId` - Microsoft Entra ID tenant ID
- `config.idp.issuer` - OIDC issuer URL (e.g., `https://login.microsoftonline.com/{tenant-id}/v2.0`)
- Client ID, client secret, Graph API client ID, and Graph API client secret are auto-configured from the `global.secrets.auth.entra` secret
- `config.idp.entra.defaultRoles` - Optional: comma-separated default roles for new users

**Azure Key Vault:**

- `config.keyVault.azure.vaultUrl` - Vault URL (e.g., `https://your-vault.vault.azure.net/`)
- `config.keyVault.azure.tenantId` - Azure tenant ID
- Client ID and secret are auto-configured from the `global.secrets.secretManager.azure_key_vault` secret

**What gets auto-configured:**

From global values:

- Database connection (host, port, credentials from `global.postgresql.*` and `global.secrets.database`)
- Identity provider type and credentials (from `global.secrets.auth.provider` and provider-specific secrets)
- Security secrets - API and JWT keys (from `global.secrets.authService`)
- Key Vault credentials for DID signing (from `global.secrets.secretManager`)
- Worker credentials (from `global.secrets.governanceWorker`)
- Environment type (from `global.environmentType`)
- Image pull secrets (from `global.secrets.imageRegistry`)

Generated defaults:

- Database host defaults to `{Release.Name}-postgresql` (co-deployed PostgreSQL)
- Swagger host defaults to `global.domain`
- Integration service URLs use internal cluster DNS (e.g., `http://{Release.Name}-integrity-service:3050`)

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
| global.secrets.auth.provider                            | string | Auth provider (auth0, keycloak, or entra)         |
| global.secrets.auth.auth0.secretName                    | string | Auth0 credentials secret name                     |
| global.secrets.auth.keycloak.secretName                 | string | Keycloak credentials secret name                  |
| global.secrets.auth.entra.secretName                    | string | Entra ID credentials secret name                  |
| global.secrets.authService.secretName                   | string | Auth service security secrets name                |
| global.secrets.secretManager.provider                   | string | Secret manager provider (azure_key_vault)         |
| global.secrets.secretManager.azure_key_vault.secretName | string | Azure Key Vault credentials secret name           |
| global.secrets.governanceWorker.secretName              | string | Worker credentials secret name                    |
| global.secrets.imageRegistry.secretName                 | string | Registry pull secret name                         |

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

| Key                                | Type | Default | Description                                                                        |
| ---------------------------------- | ---- | ------- | ---------------------------------------------------------------------------------- |
| podDisruptionBudget.enabled        | bool | `true`  | Enable Pod Disruption Budget                                                       |
| podDisruptionBudget.minAvailable   | int  | `1`     | Minimum available pods during disruptions (only rendered when replicaCount > 1)    |
| podDisruptionBudget.maxUnavailable | int  | `1`     | Maximum unavailable pods during disruptions (only rendered when replicaCount <= 1) |

### Node Scheduling

| Key            | Type   | Default           | Description                                   |
| -------------- | ------ | ----------------- | --------------------------------------------- |
| nodeSelector   | object | `{}`              | Node labels for pod assignment                |
| tolerations    | list   | `[]`              | Tolerations for pod assignment                |
| affinity       | object | Pod anti-affinity | Affinity rules (default spreads across nodes) |
| initContainers | list   | `[]`              | Init containers to add to the pod             |

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

| Key                                        | Type   | Default                           | Description                                                                                           |
| ------------------------------------------ | ------ | --------------------------------- | ----------------------------------------------------------------------------------------------------- |
| externalDatabase.host                      | string | `""`                              | Database host (auto-configured from global.postgresql.host or generated as {Release.Name}-postgresql) |
| externalDatabase.port                      | string | `""`                              | Database port (auto-configured from global.postgresql.port; defaults to `5432` when empty)            |
| externalDatabase.name                      | string | `""`                              | Database name (auto-configured from global.postgresql.database, default "governance")                 |
| externalDatabase.user                      | string | `""`                              | Database user (auto-configured from global.postgresql.username, default "postgres")                   |
| externalDatabase.password                  | string | `""`                              | Database password (auto-configured from global.secrets.database)                                      |
| externalDatabase.sslMode                   | string | `"disable"`                       | SSL mode (disable/require/verify-ca/verify-full)                                                      |
| externalDatabase.passwordSecretKeyRef.name | string | `""`                              | Secret name containing database password                                                              |
| externalDatabase.passwordSecretKeyRef.key  | string | `""`                              | Secret key name for password                                                                          |
| migrations.runAtStartup                    | bool   | `true`                            | Run database migrations automatically at startup                                                      |
| migrations.path                            | string | `"/internal/database/migrations"` | Path to migration files                                                                               |

### Secret Configuration

All secret references support global fallbacks when deployed via umbrella chart.

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

| Key                           | Type   | Default          | Description                                                                                   |
| ----------------------------- | ------ | ---------------- | --------------------------------------------------------------------------------------------- |
| config.server.port            | int    | `8080`           | Server port                                                                                   |
| config.server.host            | string | `"0.0.0.0"`      | Server host                                                                                   |
| config.server.authServiceUrl  | string | `""`             | Internal URL for self-reference (auto-generated: `http://{Release.Name}-auth-service:{port}`) |
| config.server.environment     | string | `""`             | Environment (auto-configured from global.environmentType)                                     |
| config.server.swaggerEnabled  | bool   | `true`           | Enable Swagger documentation                                                                  |
| config.server.swaggerHost     | string | `""`             | Swagger host (auto-configured from global.domain)                                             |
| config.server.swaggerBasePath | string | `"/authService"` | Swagger base path (only used when swaggerEnabled is true)                                     |

#### Auth Service Secrets

| Key              | Type   | Default | Description                                                          |
| ---------------- | ------ | ------- | -------------------------------------------------------------------- |
| config.apiSecret | string | `""`    | API secret (auto-configured from global.secrets.authService)         |
| config.jwtSecret | string | `""`    | JWT signing secret (auto-configured from global.secrets.authService) |

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

| Key                               | Type   | Default | Description                                                  |
| --------------------------------- | ------ | ------- | ------------------------------------------------------------ |
| config.idp.provider               | string | `""`    | IDP type (auto-configured from global.secrets.auth.provider) |
| config.idp.issuer                 | string | `""`    | OIDC issuer URL                                              |
| config.idp.skipIssuerVerification | bool   | `false` | Skip issuer verification (dev only)                          |

**Auth0 Configuration (only used when provider is "auth0"):**

| Key                                     | Type   | Default                              | Description                                                                   |
| --------------------------------------- | ------ | ------------------------------------ | ----------------------------------------------------------------------------- |
| config.idp.auth0.domain                 | string | `""`                                 | Auth0 tenant domain (**must be set**)                                         |
| config.idp.auth0.managementAudience     | string | `""`                                 | Management API audience (**must be set**)                                     |
| config.idp.auth0.apiIdentifier          | string | `""`                                 | API identifier (**must be set**)                                              |
| config.idp.auth0.defaultConnection      | string | `"Username-Password-Authentication"` | Default connection                                                            |
| config.idp.auth0.defaultRoles           | list   | `["user"]`                           | Default roles for new users                                                   |
| config.idp.auth0.sendInvitationEmail    | bool   | `true`                               | Send invitation email on user creation                                        |
| config.idp.auth0.clientId               | string | `""`                                 | Auth0 client ID (auto-configured from global.secrets.auth.auth0)              |
| config.idp.auth0.clientSecret           | string | `""`                                 | Auth0 client secret (auto-configured from global.secrets.auth.auth0)          |
| config.idp.auth0.managementClientId     | string | `""`                                 | Management API client ID (auto-configured from global.secrets.auth.auth0)     |
| config.idp.auth0.managementClientSecret | string | `""`                                 | Management API client secret (auto-configured from global.secrets.auth.auth0) |

**Keycloak Configuration (only used when provider is "keycloak"):**

| Key                                            | Type   | Default | Description                                                                                                             |
| ---------------------------------------------- | ------ | ------- | ----------------------------------------------------------------------------------------------------------------------- |
| config.idp.keycloak.realm                      | string | `""`    | Realm name (**must be set**, e.g., "governance")                                                                        |
| config.idp.keycloak.adminUrl                   | string | `""`    | Admin URL (**must be set**, e.g., "https://keycloak.example.com")                                                       |
| config.idp.keycloak.clientId                   | string | `""`    | Frontend SPA client ID (**must be set**, public client used for user-facing auth, e.g., "governance-platform-frontend") |
| config.idp.keycloak.enableUserManagement       | bool   | `false` | Enable user management                                                                                                  |
| config.idp.keycloak.enableGroupSync            | bool   | `false` | Enable group sync                                                                                                       |
| config.idp.keycloak.serviceAccountClientId     | string | `""`    | Service account client ID (auto-configured from global.secrets.auth.keycloak)                                           |
| config.idp.keycloak.serviceAccountClientSecret | string | `""`    | Service account client secret (auto-configured from global.secrets.auth.keycloak)                                       |

**Entra ID Configuration (only used when provider is "entra"):**

| Key                                | Type   | Default | Description                                                              |
| ---------------------------------- | ------ | ------- | ------------------------------------------------------------------------ |
| config.idp.entra.tenantId          | string | `""`    | Microsoft Entra ID tenant ID (**must be set**)                           |
| config.idp.entra.clientId          | string | `""`    | OIDC client ID (auto-configured from global.secrets.auth.entra)          |
| config.idp.entra.clientSecret      | string | `""`    | OIDC client secret (auto-configured from global.secrets.auth.entra)      |
| config.idp.entra.graphClientId     | string | `""`    | Graph API client ID (auto-configured from global.secrets.auth.entra)     |
| config.idp.entra.graphClientSecret | string | `""`    | Graph API client secret (auto-configured from global.secrets.auth.entra) |
| config.idp.entra.defaultRoles      | string | `""`    | Comma-separated default roles for new users (optional)                   |

#### Key Vault Configuration

| Key                                | Type   | Default | Description                                                                                             |
| ---------------------------------- | ------ | ------- | ------------------------------------------------------------------------------------------------------- |
| config.keyVault.provider           | string | `""`    | Key Vault provider (`"azure_key_vault"`) (auto-configured from global.secrets.secretManager.provider)   |
| config.keyVault.cacheTTLMinutes    | int    | `15`    | DID key cache TTL                                                                                       |
| config.keyVault.azure.vaultUrl     | string | `""`    | Azure Key Vault URL (auto-configured from global.secrets.secretManager.azure_key_vault.values.vaultUrl) |
| config.keyVault.azure.tenantId     | string | `""`    | Azure tenant ID (auto-configured from global.secrets.secretManager.azure_key_vault.values.tenantId)     |
| config.keyVault.azure.clientId     | string | `""`    | Azure client ID (auto-configured from global.secrets.secretManager.azure_key_vault)                     |
| config.keyVault.azure.clientSecret | string | `""`    | Azure client secret (auto-configured from global.secrets.secretManager.azure_key_vault)                 |

#### Service Account Configuration

| Key                                                   | Type   | Default         | Description                                                                  |
| ----------------------------------------------------- | ------ | --------------- | ---------------------------------------------------------------------------- |
| config.serviceAccounts.governanceWorker.enabled       | bool   | `true`          | Enable governance worker account                                             |
| config.serviceAccounts.governanceWorker.scopes        | list   | See values.yaml | Worker scopes                                                                |
| config.serviceAccounts.governanceWorker.audience      | string | `""`            | Token audience (**must be set**; Auth0 API identifier or Keycloak realm URL) |
| config.serviceAccounts.governanceWorker.clientId      | string | `""`            | Worker client ID (auto-configured from global.secrets.governanceWorker)      |
| config.serviceAccounts.governanceWorker.clientSecret  | string | `""`            | Worker client secret (auto-configured from global.secrets.governanceWorker)  |
| config.serviceAccounts.governanceWorker.encryptionKey | string | `""`            | Encryption key (auto-configured from global.secrets.governanceWorker)        |

#### Token Exchange Configuration (Optional, Keycloak Only)

Token exchange is only relevant for Keycloak deployments using federated authentication. It is disabled by default.

| Key                             | Type   | Default                   | Description                                                                    |
| ------------------------------- | ------ | ------------------------- | ------------------------------------------------------------------------------ |
| config.tokenExchange.enabled    | bool   | `false`                   | Enable token exchange (Keycloak only)                                          |
| config.tokenExchange.keyId      | string | `"auth-service-prod-001"` | Key identifier for signing key                                                 |
| config.tokenExchange.privateKey | string | `""`                      | Token exchange private key (auto-configured from global.secrets.auth.keycloak) |

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

### Advanced: Network Policy Configuration

| Key                   | Type | Default         | Description          |
| --------------------- | ---- | --------------- | -------------------- |
| networkPolicy.enabled | bool | `false`         | Enable NetworkPolicy |
| networkPolicy.ingress | list | See values.yaml | Ingress rules        |
| networkPolicy.egress  | list | See values.yaml | Egress rules         |

### Advanced: Migration Job Configuration

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

### Advanced: Extra Configuration

| Key                   | Type   | Default | Description                               |
| --------------------- | ------ | ------- | ----------------------------------------- |
| volumes               | list   | `[]`    | Additional volumes on the Deployment      |
| volumeMounts          | list   | `[]`    | Additional volumeMounts on the Deployment |
| extraEnvVars          | list   | `[]`    | Extra environment variables               |
| extraEnvVarsSecret    | string | `""`    | Secret containing extra env vars          |
| extraEnvVarsConfigMap | string | `""`    | ConfigMap containing extra env vars       |
| extraContainers       | list   | `[]`    | Extra containers to add to the pod        |
| extraManifests        | list   | `[]`    | Extra manifests to deploy                 |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level config values** - Explicitly set in `auth-service.config.*`
2. **Global values** - Set in `global.*` (umbrella chart)
3. **Chart defaults** - Default values from `values.yaml`

## Auth0 Configuration

### Required Auth0 Setup

1. **Create a Regular Web Application** for user authentication
2. **Create a Machine-to-Machine Application** for Management API access
3. **Enable Management API** permissions for the M2M application. Required scopes: `read:users`, `update:users`, `create:users`, `read:roles`, `create:role_members`
4. **Create an API** for the governance platform (this becomes your `apiIdentifier`)

### Example Configuration

```yaml
config:
  idp:
    provider: "auth0"
    issuer: "https://your-tenant.us.auth0.com/"
    auth0:
      domain: "your-tenant.us.auth0.com"
      managementAudience: "https://your-tenant.us.auth0.com/api/v2/"
      apiIdentifier: "https://governance.yourcompany.com"
      defaultConnection: "Username-Password-Authentication"
      defaultRoles: ["user"]

secrets:
  auth:
    auth0:
      name: "platform-auth0"
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
      clientId: "governance-platform-frontend"
      enableUserManagement: true

  tokenExchange:
    enabled: true
    keyId: "auth-service-prod-001"

secrets:
  auth:
    keycloak:
      name: "platform-keycloak"
```

## Microsoft Entra ID Configuration

### Required Entra ID Setup

1. **Create an App Registration** for OIDC authentication (user-facing login)
2. **Create a second App Registration** (or reuse the first) with Microsoft Graph API permissions for user management
3. **Grant Graph API permissions**: `User.Read.All`, `User.ReadWrite.All`, or scopes required by your deployment
4. **Note your Tenant ID** from Azure Active Directory overview

### Example Configuration

```yaml
config:
  idp:
    provider: "entra"
    issuer: "https://login.microsoftonline.com/your-tenant-id/v2.0"
    entra:
      tenantId: "your-tenant-id"
      defaultRoles: "user"

secrets:
  auth:
    entra:
      name: "platform-entra"
```

### Secret Creation

The Entra secret should contain the OIDC client credentials and Graph API credentials:

```bash
kubectl create secret generic platform-entra \
  --from-literal=client-id=YOUR_OIDC_CLIENT_ID \
  --from-literal=client-secret=YOUR_OIDC_CLIENT_SECRET \
  --from-literal=graph-client-id=YOUR_GRAPH_API_CLIENT_ID \
  --from-literal=graph-client-secret=YOUR_GRAPH_API_CLIENT_SECRET \
  --namespace governance
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
    provider: "azure_key_vault"
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

### Verifying Configuration

View key environment variables in the running pod:

```bash
kubectl exec -it deployment/auth-service -n governance -- env | grep -E 'IDP|AUTH0|KEYCLOAK|ENTRA|VAULT|DATABASE|DB_'
```

View all environment variables:

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
- Check the Auth0/Keycloak/Entra domain and client credentials
- Ensure `config.idp.issuer` is correct
- For Entra, verify `config.idp.entra.tenantId` is set and the Graph API credentials are correct
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
- Ensure audience is set (Auth0 API identifier or Keycloak realm URL)
- Verify secret key names match expected values (e.g., `api-secret`, `jwt-secret`, `client-id`, `client-secret`)

**Configuration not applying**

- Remember: service-level config overrides global config
- Check for typos in global value paths
- Restart pods if configuration was updated: `kubectl rollout restart deployment/auth-service -n governance`

## Health Endpoints

| Endpoint      | Description          |
| ------------- | -------------------- |
| `GET /health` | Overall health check |

### API Documentation

When `config.server.swaggerEnabled` is `true` (default), Swagger UI is available at:

```
https://{domain}/authService/swagger/index.html
```

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://docs.eqtylab.io
- GitHub: https://github.com/eqtylab/governance-studio-infrastructure
