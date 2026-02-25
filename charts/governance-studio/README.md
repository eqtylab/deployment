# Governance Studio

A Helm chart for deploying the EQTY Lab Governance Studio frontend application on Kubernetes.

## Description

Governance Studio provides a web-based interface for managing governance, compliance, and data lineage workflows.

Key capabilities:

- **Governance Management**: Create, review, and manage governance policies and workflows
- **Data Lineage**: Visualize provenance and transformation history of data assets
- **Multi-Provider Auth**: Native support for Auth0, Keycloak, and Microsoft Entra ID authentication
- **Feature Flags**: Configurable feature toggles for governance and lineage
- **Runtime Configuration**: Single immutable image with environment-driven configuration

## Configuration Model

Governance Studio uses runtime configuration injected via environment variables. Application configuration is provided through Helm values and injected into the container at startup.

This allows:

- A single immutable container image across environments
- Configuration changes without rebuilding images
- Clear separation of infrastructure and application settings
- Automatic configuration inheritance from umbrella chart globals

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- Authentication provider (Auth0, Keycloak, or Microsoft Entra ID)
- Ingress controller (NGINX, Traefik, etc.)
- TLS certificates (manual or via cert-manager)

## Deployment

When deployed via the `governance-platform` umbrella chart, Governance Studio automatically inherits configuration from global values with no additional configuration required.

### Quick Start

Minimum configuration required in your umbrella chart values:

**Auth0:**

```yaml
governance-studio:
  image:
    tag: ""
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/proxy-body-size: "64m"
    hosts:
      - host: "governance.yourcompany.com"
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: "governance-studio-tls"
        hosts:
          - "governance.yourcompany.com"
  config:
    authProvider: "auth0"
    auth0Domain: "your-tenant.us.auth0.com"
    auth0ClientId: "your-spa-client-id"
    auth0Audience: "https://your-tenant.us.auth0.com/api/v2/"
```

**Keycloak:**

```yaml
governance-studio:
  image:
    tag: ""
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/proxy-body-size: "64m"
    hosts:
      - host: "governance.yourcompany.com"
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: "governance-studio-tls"
        hosts:
          - "governance.yourcompany.com"
  config:
    authProvider: "keycloak"
    keycloakUrl: "https://keycloak.yourcompany.com"
    keycloakRealm: "governance"
    keycloakClientId: "governance-platform-frontend"
```

**Microsoft Entra ID:**

```yaml
governance-studio:
  image:
    tag: ""
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/proxy-body-size: "64m"
    hosts:
      - host: "governance.yourcompany.com"
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: "governance-studio-tls"
        hosts:
          - "governance.yourcompany.com"
  config:
    authProvider: "entra"
    entraClientId: "your-entra-client-id"
    entraTenantId: "your-tenant-id"
    # entraAuthority: "https://login.microsoftonline.com/your-tenant-id"  # optional
```

### Required Configuration

Beyond what is auto-configured, these values **must** be explicitly set:

**Auth0:**

- `config.auth0Domain` - Auth0 tenant domain (e.g., `your-tenant.us.auth0.com`)
- `config.auth0ClientId` - Auth0 SPA client ID (public, not a secret)
- `config.auth0Audience` - Auth0 API audience (e.g., `https://your-tenant.us.auth0.com/api/v2/`)

**Keycloak:**

- `config.keycloakUrl` - Keycloak server URL (e.g., `https://keycloak.yourcompany.com`)
- `config.keycloakClientId` - Keycloak SPA client ID (public, e.g., `governance-platform-frontend`)
- `config.keycloakRealm` - Keycloak realm name (e.g., `governance`)

**Microsoft Entra ID:**

- `config.entraClientId` - Application (client) ID from Azure app registration (public, not a secret)
- `config.entraTenantId` - Directory (tenant) ID from Azure
- `config.entraAuthority` - (Optional) Authority URL override, defaults to `https://login.microsoftonline.com/<tenantId>`

**What gets auto-configured:**

From global values:

- All service URLs (API, Auth, Integrity) from `global.domain`
- Environment type from `global.environmentType`
- App hostname from `global.domain`
- Auth provider from `global.secrets.auth.provider`
- Image pull secrets from `global.secrets.imageRegistry`

Generated defaults:

- `config.apiUrl` defaults to `https://{global.domain}/governanceService`
- `config.authServiceUrl` defaults to `https://{global.domain}/authService`
- `config.integrityServiceUrl` defaults to `https://{global.domain}/integrityService`

## Values

### Global Parameters (Umbrella Chart)

When deployed via the umbrella chart, these global values are automatically used:

| Key                                     | Type   | Description                                       |
| --------------------------------------- | ------ | ------------------------------------------------- |
| global.domain                           | string | Base domain for all services                      |
| global.environmentType                  | string | Environment type (development/staging/production) |
| global.secrets.imageRegistry.secretName | string | Name of image pull secret                         |
| global.secrets.auth.provider            | string | Auth provider (auth0, keycloak, or entra)         |
| global.secrets.auth.auth0.secretName    | string | Auth0 credentials secret name                     |
| global.secrets.auth.keycloak.secretName | string | Keycloak credentials secret name                  |
| global.secrets.auth.entra.secretName    | string | Entra ID credentials secret name                  |

### Chart-Specific Parameters

| Key              | Type   | Default                               | Description                                           |
| ---------------- | ------ | ------------------------------------- | ----------------------------------------------------- |
| enabled          | bool   | `true`                                | Enable this subchart (umbrella chart only)            |
| replicaCount     | int    | `1`                                   | Number of replicas to deploy                          |
| image.repository | string | `"ghcr.io/eqtylab/governance-studio"` | Container image repository                            |
| image.pullPolicy | string | `"IfNotPresent"`                      | Image pull policy                                     |
| image.tag        | string | `""`                                  | Overrides the image tag (default is chart appVersion) |
| imagePullSecrets | list   | `[]`                                  | Additional image pull secrets (beyond global)         |

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
| service.port    | int    | `80`          | Service port              |

### Ingress

| Key                 | Type   | Default                                                                          | Description                 |
| ------------------- | ------ | -------------------------------------------------------------------------------- | --------------------------- |
| ingress.enabled     | bool   | `false`                                                                          | Enable ingress              |
| ingress.className   | string | `""`                                                                             | Ingress class name          |
| ingress.annotations | object | `{}`                                                                             | Ingress annotations         |
| ingress.hosts       | list   | `[{"host":"governance.example.com","paths":[{"path":"/","pathType":"Prefix"}]}]` | Ingress hosts configuration |
| ingress.tls         | list   | `[]`                                                                             | Ingress TLS configuration   |

### Resources

| Key                                           | Type   | Default | Description                          |
| --------------------------------------------- | ------ | ------- | ------------------------------------ |
| resources                                     | object | `{}`    | CPU/Memory resource requests/limits  |
| autoscaling.enabled                           | bool   | `false` | Enable horizontal pod autoscaling    |
| autoscaling.minReplicas                       | int    | `1`     | Minimum number of replicas           |
| autoscaling.maxReplicas                       | int    | `100`   | Maximum number of replicas           |
| autoscaling.targetCPUUtilizationPercentage    | int    | `80`    | Target CPU utilization percentage    |
| autoscaling.targetMemoryUtilizationPercentage | int    | `80`    | Target memory utilization percentage |

> **Note:** Resources are empty by default. For production, set appropriate requests and limits (recommended: cpu 100m-500m, memory 128Mi-256Mi).

### High Availability

| Key                                | Type | Default | Description                                                                        |
| ---------------------------------- | ---- | ------- | ---------------------------------------------------------------------------------- |
| podDisruptionBudget.enabled        | bool | `false` | Enable Pod Disruption Budget                                                       |
| podDisruptionBudget.minAvailable   | int  | `1`     | Minimum available pods during disruptions (only rendered when replicaCount > 1)    |
| podDisruptionBudget.maxUnavailable | int  | `1`     | Maximum unavailable pods during disruptions (only rendered when replicaCount <= 1) |

### Node Scheduling

| Key          | Type   | Default | Description                       |
| ------------ | ------ | ------- | --------------------------------- |
| nodeSelector | object | `{}`    | Node labels for pod assignment    |
| tolerations  | list   | `[]`    | Tolerations for pod assignment    |
| affinity     | object | `{}`    | Affinity rules for pod assignment |

### Health Checks

| Key                                | Type   | Default  | Description                          |
| ---------------------------------- | ------ | -------- | ------------------------------------ |
| startupProbe.httpGet.path          | string | `"/"`    | Startup probe HTTP path              |
| startupProbe.httpGet.port          | string | `"http"` | Startup probe port                   |
| startupProbe.failureThreshold      | int    | `30`     | Startup failure threshold            |
| startupProbe.periodSeconds         | int    | `10`     | How often to perform startup probe   |
| livenessProbe.httpGet.path         | string | `"/"`    | Liveness probe HTTP path             |
| livenessProbe.httpGet.port         | string | `"http"` | Liveness probe port                  |
| livenessProbe.initialDelaySeconds  | int    | `10`     | Initial delay before liveness probe  |
| livenessProbe.periodSeconds        | int    | `10`     | How often to perform liveness probe  |
| livenessProbe.failureThreshold     | int    | `3`      | Liveness failure threshold           |
| readinessProbe.httpGet.path        | string | `"/"`    | Readiness probe HTTP path            |
| readinessProbe.httpGet.port        | string | `"http"` | Readiness probe port                 |
| readinessProbe.initialDelaySeconds | int    | `5`      | Initial delay before readiness probe |
| readinessProbe.periodSeconds       | int    | `5`      | How often to perform readiness probe |
| readinessProbe.failureThreshold    | int    | `2`      | Readiness failure threshold          |

### Application Configuration

All config values support global fallbacks when deployed via umbrella chart.

| Key                        | Type   | Default               | Description                                               |
| -------------------------- | ------ | --------------------- | --------------------------------------------------------- |
| config.basePath            | string | `"/"`                 | Base path for application routing                         |
| config.apiUrl              | string | `""`                  | Backend API URL (auto-generated from global.domain)       |
| config.authServiceUrl      | string | `""`                  | Auth service URL (auto-generated from global.domain)      |
| config.integrityServiceUrl | string | `""`                  | Integrity service URL (auto-generated from global.domain) |
| config.environment         | string | `""`                  | Environment (auto-configured from global.environmentType) |
| config.appTitle            | string | `"Governance Studio"` | Application title displayed in browser                    |

### Authentication

Authentication is automatically configured from global values in umbrella deployments. Only one authentication provider should be configured at a time, set via `global.secrets.auth.provider` in the umbrella chart.

#### Required Configuration

**Auth0:**

- `config.auth0Domain` - Auth0 tenant domain (e.g., `your-tenant.us.auth0.com`)
- `config.auth0ClientId` - Auth0 SPA client ID (public, not a secret)
- `config.auth0Audience` - Auth0 API audience (e.g., `https://your-tenant.us.auth0.com/api/v2/`)

**Keycloak:**

- `config.keycloakUrl` - Keycloak server URL (e.g., `https://keycloak.yourcompany.com`)
- `config.keycloakClientId` - Keycloak SPA client ID (public, e.g., `governance-platform-frontend`)
- `config.keycloakRealm` - Keycloak realm name (e.g., `governance`)

**Microsoft Entra ID:**

- `config.entraClientId` - Application (client) ID from Azure app registration (public, not a secret)
- `config.entraTenantId` - Directory (tenant) ID from Azure
- `config.entraAuthority` - (Optional) Authority URL override, defaults to `https://login.microsoftonline.com/<tenantId>`

#### All Authentication Values

| Key                     | Type   | Default | Description                                                                                |
| ----------------------- | ------ | ------- | ------------------------------------------------------------------------------------------ |
| config.authProvider     | string | `""`    | Auth provider (auto-configured from global.secrets.auth.provider)                          |
| config.auth0Domain      | string | `""`    | Auth0 tenant domain (**must be set**)                                                      |
| config.auth0ClientId    | string | `""`    | Auth0 SPA client ID (**must be set**, public)                                              |
| config.auth0Audience    | string | `""`    | Auth0 API audience (**must be set**)                                                       |
| config.keycloakUrl      | string | `""`    | Keycloak server URL (**must be set**, e.g., "https://keycloak.example.com")                |
| config.keycloakClientId | string | `""`    | Keycloak SPA client ID (**must be set**, public, e.g., "governance-platform-frontend")     |
| config.keycloakRealm    | string | `""`    | Keycloak realm name (**must be set**, e.g., "governance")                                  |
| config.entraClientId    | string | `""`    | Entra application (client) ID (**must be set**, public)                                    |
| config.entraTenantId    | string | `""`    | Entra directory (tenant) ID (**must be set**)                                              |
| config.entraAuthority   | string | `""`    | Entra authority URL (optional, defaults to `https://login.microsoftonline.com/<tenantId>`) |

### Feature Flags

| Key                        | Type | Default | Description                |
| -------------------------- | ---- | ------- | -------------------------- |
| config.features.governance | bool | `true`  | Enable governance features |
| config.features.lineage    | bool | `true`  | Enable lineage features    |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level config values** - Explicitly set in `governance-studio.config.*`
2. **Global values** - Set in `global.*` (umbrella chart)
3. **Chart defaults** - Default values from `values.yaml`

## Troubleshooting

### Viewing Logs

```bash
kubectl logs -f deployment/governance-studio -n governance
```

### Checking Pod Status

```bash
kubectl get pods -n governance -l app.kubernetes.io/name=governance-studio
kubectl describe pod <pod-name> -n governance
```

### Verifying Configuration

View the generated ConfigMap to see actual runtime configuration:

```bash
kubectl get configmap governance-studio-config -n governance -o yaml
```

View all environment variables:

```bash
kubectl exec -it deployment/governance-studio -n governance -- env | sort
```

Test health endpoint:

```bash
kubectl exec -it deployment/governance-studio -n governance -- curl -s localhost:80/
```

### Common Issues

**Application not accessible**

- Verify ingress is enabled and configured correctly
- Check DNS points to your ingress controller
- Verify TLS certificates are valid
- Ensure `global.domain` matches your DNS configuration

**Authentication fails**

- Verify `global.domain` matches ingress hosts
- Check Auth0/Keycloak/Entra redirect URIs include your domain
- Ensure auth provider credentials are correct in `global.secrets.auth`
- Verify `config.authProvider` matches configured auth system

**API connection errors**

- Check that service URLs are generated correctly from `global.domain`
- Verify backend services are running and accessible
- Check CORS configuration on backend APIs
- Ensure network policies allow traffic between services

**Configuration not applying**

- Remember: service-level config overrides global config
- Check for typos in global value paths
- Verify the ConfigMap was regenerated after changes
- Restart pods if ConfigMap was updated: `kubectl rollout restart deployment/governance-studio -n governance`

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://docs.eqtylab.io
- GitHub: https://github.com/eqtylab/governance-studio-infrastructure
