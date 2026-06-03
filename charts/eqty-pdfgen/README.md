# EQTY PDFGen

A Helm chart for deploying the EQTY Lab PDF generation service on Kubernetes.

## Description

EQTY PDFGen renders governance manifests into PDF files or ZIP bundles for the Governance Platform. When a request includes an authorization bearer token, the service can delegate PDF signing to Auth Service.

Key capabilities:

- **Manifest Rendering**: Render governance manifests through `POST /manifest`
- **ZIP Bundles**: Return `report.pdf`, `manifest.json`, parsed manifest data, and attachments in a single archive
- **Plain PDF Output**: Return a standalone PDF with `POST /manifest?format=pdf`
- **Remote Signing**: Optionally delegate PDF signing to Auth Service

## Configuration Model

EQTY PDFGen uses runtime configuration injected via environment variables. Application configuration is provided through Helm values and injected into the container at startup.

This allows:

- A single immutable container image across environments
- Configuration changes without rebuilding images
- Clear separation of infrastructure and application settings
- Automatic configuration inheritance from umbrella chart globals

## Prerequisites

- Kubernetes 1.29+
- Helm 4.0+
- Container registry access to `ghcr.io/eqtylab/eqty-pdfgen`
- Auth Service (only required when signed PDFs are needed)

## Deployment

When deployed via the `governance-platform` umbrella chart, EQTY PDFGen automatically inherits image registry settings and the default signing URL from global values. The service is **disabled by default** and is enabled environment-by-environment.

The chart creates only an internal ClusterIP Service and intentionally does not render an Ingress; PDF generation is an internal capability consumed by other platform services.

### Quick Start

Minimum configuration required in your umbrella chart values:

```yaml
eqty-pdfgen:
  enabled: true
  image:
    tag: ""
  service:
    type: ClusterIP
    port: 8080
```

The default signing URL is generated as:

```text
http://{Release.Name}-auth-service:8080/api/v1/protected/sign-pdf
```

### Required Configuration

Beyond what is auto-configured, no values are strictly required to start the service. Set the following only when the defaults do not fit your environment:

- `config.signingUrl` - Override the signing endpoint, only needed when Auth Service is exposed under a different internal address than the generated default
- `config.timestampUrl` - Override the timestamp authority (defaults to `http://timestamp.digicert.com`)

**What gets auto-configured:**

From global values (umbrella chart):

- Image repository/registry (from `global.imageRegistryOverride` and `global.imageRepositoryPrefixOverride`)
- Image pull policy (from `global.imagePullPolicy`)
- Image pull secrets (from `global.secrets.imageRegistry`)

Generated defaults:

- Signing URL defaults to `http://{Release.Name}-auth-service:8080/api/v1/protected/sign-pdf` (co-deployed Auth Service)
- Image tag defaults to the chart `appVersion`

## Values

### Global Parameters (Umbrella Chart)

When deployed via the umbrella chart, these global values are automatically used:

| Key                                     | Type   | Description                                                                   |
| --------------------------------------- | ------ | ----------------------------------------------------------------------------- |
| global.imageRegistryOverride            | string | Replace only the image registry host (e.g., `registry.customer.example`)      |
| global.imageRepositoryPrefixOverride    | string | Replace the full EQTY image repository prefix (e.g., `registry.example/eqty`) |
| global.imagePullPolicy                  | string | Default image pull policy for platform installs                               |
| global.secrets.imageRegistry.secretName | string | Name of image pull secret                                                     |

### Chart-Specific Parameters

| Key              | Type   | Default                         | Description                                           |
| ---------------- | ------ | ------------------------------- | ----------------------------------------------------- |
| enabled          | bool   | `true`                          | Enable this subchart (umbrella chart only)            |
| replicaCount     | int    | `2`                             | Number of replicas to deploy                          |
| image.repository | string | `"ghcr.io/eqtylab/eqty-pdfgen"` | Container image repository                            |
| image.pullPolicy | string | `"IfNotPresent"`                | Image pull policy                                     |
| image.tag        | string | `""`                            | Overrides the image tag (default is chart appVersion) |
| imagePullSecrets | list   | `[]`                            | Additional image pull secrets (beyond global)         |
| nameOverride     | string | `""`                            | Override the chart name used for resource naming      |
| fullnameOverride | string | `""`                            | Override the fully qualified resource name            |

### Service Account

| Key                        | Type   | Default | Description                                                                  |
| -------------------------- | ------ | ------- | ---------------------------------------------------------------------------- |
| serviceAccount.create      | bool   | `false` | Specifies whether a service account should be created                        |
| serviceAccount.automount   | bool   | `true`  | Automatically mount the ServiceAccount's API credentials                     |
| serviceAccount.annotations | object | `{}`    | Annotations to add to the service account                                    |
| serviceAccount.name        | string | `""`    | The name of the service account (generated if serviceAccount.create is true) |

### Security

| Key                                      | Type   | Default          | Description                    |
| ---------------------------------------- | ------ | ---------------- | ------------------------------ |
| podAnnotations                           | object | `{}`             | Annotations to add to pods     |
| podLabels                                | object | `{}`             | Labels to add to pods          |
| podSecurityContext.runAsNonRoot          | bool   | `true`           | Run pod as non-root user       |
| podSecurityContext.runAsUser             | int    | `1001`           | User ID to run the pod         |
| podSecurityContext.runAsGroup            | int    | `0`              | Group ID to run the pod        |
| podSecurityContext.fsGroup               | int    | `0`              | Filesystem group               |
| podSecurityContext.fsGroupChangePolicy   | string | `OnRootMismatch` | Filesystem group change policy |
| securityContext.runAsNonRoot             | bool   | `true`           | Run container as non-root user |
| securityContext.allowPrivilegeEscalation | bool   | `false`          | Prevent privilege escalation   |
| securityContext.readOnlyRootFilesystem   | bool   | `true`           | Read-only root filesystem      |
| securityContext.capabilities.drop        | list   | `[ALL]`          | Drop all capabilities          |

### Service

| Key             | Type   | Default       | Description                                    |
| --------------- | ------ | ------------- | ---------------------------------------------- |
| service.enabled | bool   | `true`        | Create a Service resource                      |
| service.type    | string | `"ClusterIP"` | Kubernetes service type                        |
| service.port    | int    | `8080`        | Service port exposed by the Kubernetes Service |

### Resources

| Key                                           | Type   | Default | Description                          |
| --------------------------------------------- | ------ | ------- | ------------------------------------ |
| resources                                     | object | `{}`    | CPU/Memory resource requests/limits  |
| autoscaling.enabled                           | bool   | `false` | Enable horizontal pod autoscaling    |
| autoscaling.minReplicas                       | int    | `1`     | Minimum number of replicas           |
| autoscaling.maxReplicas                       | int    | `10`    | Maximum number of replicas           |
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

| Key          | Type   | Default | Description                       |
| ------------ | ------ | ------- | --------------------------------- |
| nodeSelector | object | `{}`    | Node labels for pod assignment    |
| tolerations  | list   | `[]`    | Tolerations for pod assignment    |
| affinity     | object | `{}`    | Affinity rules for pod assignment |

### Health Checks

| Key                                | Type   | Default           | Description                   |
| ---------------------------------- | ------ | ----------------- | ----------------------------- |
| startupProbe.httpGet.path          | string | `"/health/ready"` | Startup probe HTTP path       |
| startupProbe.httpGet.port          | string | `"http"`          | Startup probe port            |
| startupProbe.periodSeconds         | int    | `10`              | Startup probe period          |
| startupProbe.failureThreshold      | int    | `30`              | Startup failure threshold     |
| livenessProbe.httpGet.path         | string | `"/health/live"`  | Liveness probe HTTP path      |
| livenessProbe.httpGet.port         | string | `"http"`          | Liveness probe port           |
| livenessProbe.initialDelaySeconds  | int    | `10`              | Liveness probe initial delay  |
| livenessProbe.periodSeconds        | int    | `10`              | Liveness probe period         |
| livenessProbe.failureThreshold     | int    | `3`               | Liveness failure threshold    |
| readinessProbe.httpGet.path        | string | `"/health/ready"` | Readiness probe HTTP path     |
| readinessProbe.httpGet.port        | string | `"http"`          | Readiness probe port          |
| readinessProbe.initialDelaySeconds | int    | `5`               | Readiness probe initial delay |
| readinessProbe.periodSeconds       | int    | `5`               | Readiness probe period        |
| readinessProbe.failureThreshold    | int    | `2`               | Readiness failure threshold   |

### Application Configuration

| Key                          | Type   | Default                                     | Description                                                                                                       |
| ---------------------------- | ------ | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| config.host                  | string | `"0.0.0.0"`                                 | Bind address for the HTTP server                                                                                  |
| config.port                  | int    | `8080`                                      | Container port for the HTTP server (defaults to service.port when unset)                                          |
| config.tmpDir                | string | `"tmp"`                                     | Writable render directory under the app working directory                                                         |
| config.typstFontPaths        | string | `"/usr/share/fonts"`                        | Font search paths for the Typst renderer                                                                          |
| config.typstPackageCachePath | string | `"/opt/app-root/src/.cache/typst/packages"` | Typst package cache directory                                                                                     |
| config.timestampUrl          | string | `"http://timestamp.digicert.com"`           | Timestamp authority URL                                                                                           |
| config.signingUrl            | string | `""`                                        | Signing endpoint override (auto-generated as `http://{Release.Name}-auth-service:8080/api/v1/protected/sign-pdf`) |

### Advanced: Network Policy Configuration

| Key                   | Type | Default | Description          |
| --------------------- | ---- | ------- | -------------------- |
| networkPolicy.enabled | bool | `false` | Enable NetworkPolicy |
| networkPolicy.ingress | list | `[]`    | Ingress rules        |
| networkPolicy.egress  | list | `[]`    | Egress rules         |

### Advanced: Extra Configuration

| Key                   | Type   | Default | Description                                |
| --------------------- | ------ | ------- | ------------------------------------------ |
| extraEnvVars          | list   | `[]`    | Additional container environment variables |
| extraEnvVarsSecret    | string | `""`    | Secret referenced with `envFrom`           |
| extraEnvVarsConfigMap | string | `""`    | ConfigMap referenced with `envFrom`        |

## Configuration Inheritance

When deployed via the umbrella chart, configuration follows this precedence (highest to lowest):

1. **Service-level config values** - Explicitly set in `eqty-pdfgen.config.*`
2. **Global values** - Set in `global.*` (umbrella chart)
3. **Chart defaults** - Default values from `values.yaml`

## Troubleshooting

### Viewing Logs

```bash
kubectl logs -f deployment/eqty-pdfgen -n governance
```

### Checking Pod Status

```bash
kubectl get pods -n governance -l app.kubernetes.io/name=eqty-pdfgen
kubectl describe pod <pod-name> -n governance
```

### Verifying Configuration

View key environment variables in the running pod:

```bash
kubectl exec -it deployment/eqty-pdfgen -n governance -- env | grep -E 'PDFGEN|TYPST|EQTY_'
```

View all environment variables:

```bash
kubectl exec -it deployment/eqty-pdfgen -n governance -- env | sort
```

Test health endpoint:

```bash
kubectl exec -it deployment/eqty-pdfgen -n governance -- curl -s localhost:8080/health/ready
```

### Common Issues

**Pods not starting**

- Verify the image is pullable and `global.secrets.imageRegistry.secretName` references a valid pull secret
- Check pod events with `kubectl describe pod`
- Confirm the readiness probe path `/health/ready` is responding

**Signing failures**

- Verify Auth Service is running and reachable from PDFGen pods
- Check `config.signingUrl` resolves to the correct internal Auth Service address
- Confirm requests include a valid authorization bearer token (signing is skipped without one)

**Rendering errors**

- Confirm fonts are available under `config.typstFontPaths`
- Verify the render directory `config.tmpDir` is writable (mounted as an `emptyDir`)
- Check that the Typst package cache path is accessible

**Configuration not applying**

- Remember: service-level config overrides global config
- Check for typos in global value paths
- Restart pods if configuration was updated: `kubectl rollout restart deployment/eqty-pdfgen -n governance`

## Health Endpoints

| Endpoint            | Description                       |
| ------------------- | --------------------------------- |
| `GET /health/live`  | Liveness                          |
| `GET /health/ready` | Readiness                         |
| `GET /health`       | Readiness-compatible health check |

### API Documentation

The FastAPI Swagger UI is available at:

```
http://{service}:8080/docs
```

### API Endpoints

| Endpoint                    | Description         |
| --------------------------- | ------------------- |
| `POST /manifest`            | Render a ZIP bundle |
| `POST /manifest?format=pdf` | Render a plain PDF  |
| `GET /docs`                 | FastAPI Swagger UI  |

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://docs.eqtylab.io
- GitHub: https://github.com/eqtylab/governance-studio-infrastructure
  </content>
  </invoke>
