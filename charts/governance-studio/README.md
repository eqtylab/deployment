# Governance Studio

A Helm chart for deploying the EQTY Lab Governance Studio frontend application on Kubernetes.

## Description

Governance Studio provides a web-based interface for managing governance, compliance, and data lineage workflows. This chart can be deployed standalone or as part of the Governance Platform umbrella chart.

## Configuration Model

Governance Studio uses runtime configuration injection. Application configuration is provided via environment variables generated from Helm values and injected into the container at startup.

This allows:

- A single immutable container image across environments
- Configuration changes without rebuilding images
- Clear separation of infrastructure and application settings
- Automatic configuration inheritance from umbrella chart globals

## Deployment Options

### Option 1: As Part of Governance Platform (Recommended)

When deployed via the `governance-platform` umbrella chart, Governance Studio automatically inherits configuration from global values with zero additional configuration required.

**Example umbrella chart configuration:**

```yaml
global:
  domain: "governance.yourcompany.com"
  environmentType: "production"

  secrets:
    auth:
      provider: "auth0"
      auth0:
        secretName: "platform-auth0"

governance-studio:
  enabled: true
  replicaCount: 3

  config:
    auth0Domain: "yourcompany.us.auth0.com"
    auth0ClientId: "your-spa-client-id" # SPA client ID (public, not a secret)
    auth0Audience: "https://yourcompany.us.auth0.com/api/v2/"

  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10

  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
```

**What gets auto-configured:**

- ✅ All service URLs (API, Auth, Integrity) from `global.domain`
- ✅ Environment type from `global.environmentType`
- ✅ App hostname from `global.domain`
- ✅ Auth provider from `global.secrets.auth.provider`
- ✅ Image pull secrets from `global.secrets.imageRegistry`

**Must be explicitly set:**

- ⚠️ `config.auth0Domain` - Auth0 tenant domain
- ⚠️ `config.auth0ClientId` - Auth0 SPA client ID (public, not a secret)
- ⚠️ `config.auth0Audience` - Auth0 API audience

### Option 2: Standalone Deployment

For standalone deployments outside the umbrella chart:

```yaml
enabled: true

config:
  apiUrl: https://governance.yourcompany.com/governanceService
  authServiceUrl: https://governance.yourcompany.com/authService
  integrityServiceUrl: https://governance.yourcompany.com/integrityService
  environment: production

  authProvider: auth0
  auth0Domain: yourcompany.auth0.com
  auth0ClientId: YOUR_CLIENT_ID
  auth0Audience: https://api.governance.yourcompany.com

  features:
    governance: true
    lineage: true

service:
  enabled: true
  type: ClusterIP
  port: 80

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: governance.yourcompany.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: governance-tls
      hosts:
        - governance.yourcompany.com
```

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
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
helm install governance-studio eqtylab/governance-studio \
  -f values.yaml \
  --namespace governance \
  --create-namespace
```

## Uninstalling the Chart

```bash
helm uninstall governance-studio --namespace governance
```

This removes all Kubernetes components associated with the chart and deletes the release.

## Values

### Global Parameters (Umbrella Chart)

When deployed via the umbrella chart, these global values are automatically used:

| Key                                     | Type   | Description                                       |
| --------------------------------------- | ------ | ------------------------------------------------- |
| global.domain                           | string | Base domain for all services                      |
| global.environmentType                  | string | Environment type (development/staging/production) |
| global.secrets.imageRegistry.secretName | string | Name of image pull secret                         |
| global.secrets.auth.provider            | string | Auth provider (auth0 or keycloak)                 |
| global.secrets.auth.auth0.values.\*     | object | Auth0 configuration values                        |
| global.secrets.auth.keycloak.values.\*  | object | Keycloak configuration values                     |

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
| config.garageServiceUrl    | string | `""`                  | Garage service URL (auto-generated from global.domain)    |
| config.environment         | string | `""`                  | Environment (auto-configured from global.environmentType) |
| config.appTitle            | string | `"Governance Studio"` | Application title displayed in browser                    |

### Authentication

Authentication is automatically configured from global values in umbrella deployments.

| Key                     | Type   | Default | Description                                                                                    |
| ----------------------- | ------ | ------- | ---------------------------------------------------------------------------------------------- |
| config.authProvider     | string | `""`    | Auth provider (auto-configured from global.secrets.auth.provider)                              |
| config.auth0Domain      | string | `""`    | Auth0 domain (**must be set**)                                                                 |
| config.auth0ClientId    | string | `""`    | Auth0 SPA client ID (**must be set**, public)                                                  |
| config.auth0Audience    | string | `""`    | Auth0 audience (**must be set**)                                                               |
| config.keycloakUrl      | string | `""`    | Keycloak URL (auto-configured from global.secrets.auth.keycloak.values.url)                    |
| config.keycloakRealm    | string | `""`    | Keycloak realm (auto-configured from global.secrets.auth.keycloak.values.realm)                |
| config.keycloakClientId | string | `""`    | Keycloak client ID (auto-configured from global.secrets.auth.keycloak.values.frontendClientId) |

> ⚠️ Only one authentication provider should be configured at a time.
> Set via `global.secrets.auth.provider` in umbrella chart.

### Feature Flags

| Key                                  | Type | Default | Description                   |
| ------------------------------------ | ---- | ------- | ----------------------------- |
| config.features.governance           | bool | `true`  | Enable governance features    |
| config.features.lineage              | bool | `true`  | Enable lineage features       |
| config.features.guardianEnabled      | bool | `false` | Enable Guardian platform      |
| config.features.guardianGarage       | bool | `false` | Enable Guardian Garage UI     |
| config.features.guardianRulebooks    | bool | `false` | Enable Guardian Rulebooks     |
| config.features.guardianOsFunctions  | bool | `false` | Enable Guardian OS functions  |
| config.features.guardianSdkFunctions | bool | `false` | Enable Guardian SDK functions |
| config.features.agentManagement      | bool | `false` | Enable agent management       |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level config values** - Explicitly set in `governance-studio.config.*`
2. **Global values** - Set in `global.*` (umbrella chart)
3. **Chart defaults** - Default values from `values.yaml`

### Example Configuration Flow

```yaml
# Umbrella chart values.yaml
global:
  domain: "governance.prod.company.com"
  secrets:
    auth:
      provider: "auth0"
      auth0:
        secretName: "platform-auth0"

governance-studio:
  enabled: true
  # config.apiUrl automatically becomes: https://governance.prod.company.com/governanceService
  # config.authProvider automatically becomes: auth0

  # Must explicitly set:
  config:
    auth0Domain: "company.us.auth0.com"
    auth0Audience: "https://company.us.auth0.com/api/v2/"
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
helm upgrade governance-studio eqtylab/governance-studio \
  -f values.yaml \
  --namespace governance
```

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
kubectl get configmap -n governance -l app.kubernetes.io/name=governance-studio
kubectl describe configmap governance-studio-config -n governance
```

### Testing Configuration Inheritance

When deployed via umbrella chart, verify global values are being used:

```bash
# Get the ConfigMap
kubectl get configmap governance-studio-config -n governance -o yaml

# Check environment variables in running pod
kubectl exec -it deployment/governance-studio -n governance -- env | grep -E 'API_URL|AUTH|ENVIRONMENT'
```

### Common Issues

**Application not accessible**

- Verify ingress is enabled and configured correctly
- Check DNS points to your ingress controller
- Verify TLS certificates are valid
- Ensure `global.domain` matches your DNS configuration

**Authentication fails**

- Verify `global.domain` matches ingress hosts
- Check Auth0/Keycloak redirect URIs include your domain
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
