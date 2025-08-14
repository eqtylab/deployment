# Governance Service

This Helm chart deploys the Governance Service API service, which provides assurance validation and analysis capabilities for the Governance Studio platform.

## Overview

The Governance Service is a core component of the Governance Studio platform that handles:

- Assurance validation and processing
- API endpoints for assurance-related operations
- Integration with the broader governance ecosystem

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- PostgreSQL database (provided by umbrella chart or external)
- Persistent volume provisioner support in the underlying infrastructure

## Installation

### Standalone Installation

```bash
# Install the chart
helm install governance-service ./charts/governance-service \
  --create-namespace \
  --namespace governance \
  --values values.yaml
```

### As Part of Governance Studio (Recommended)

This chart is typically deployed as part of the Governance Studio umbrella chart:

```bash
# Install complete platform
helm install governance-studio ./charts/governance-studio \
  --create-namespace \
  --namespace governance \
  --values values.yaml
```

## Configuration

### Core Parameters

| Parameter          | Description                | Default                                |
| ------------------ | -------------------------- | -------------------------------------- |
| `image.repository` | Container image repository | `"ghcr.io/eqtylab/governance-service"` |
| `image.tag`        | Container image tag        | `"2.0.0"`                              |
| `image.pullPolicy` | Image pull policy          | `"IfNotPresent"`                       |
| `replicaCount`     | Number of pod replicas     | `1`                                    |

### Database Configuration

| Parameter                 | Description                               | Default        |
| ------------------------- | ----------------------------------------- | -------------- |
| `database.host`           | Database hostname                         | `"postgresql"` |
| `database.port`           | Database port                             | `5432`         |
| `database.name`           | Database name                             | `"assurance"`  |
| `database.existingSecret` | Existing secret with database credentials | `""`           |

### Service Configuration

| Parameter            | Description             | Default       |
| -------------------- | ----------------------- | ------------- |
| `service.type`       | Kubernetes service type | `"ClusterIP"` |
| `service.port`       | Service port            | `8080`        |
| `service.targetPort` | Container target port   | `8080`        |

### Ingress Configuration

| Parameter           | Description        | Default   |
| ------------------- | ------------------ | --------- |
| `ingress.enabled`   | Enable ingress     | `false`   |
| `ingress.className` | Ingress class name | `"nginx"` |
| `ingress.hosts`     | Ingress hostnames  | `[]`      |
| `ingress.tls`       | TLS configuration  | `[]`      |

### Resource Limits

| Parameter                   | Description    | Default   |
| --------------------------- | -------------- | --------- |
| `resources.limits.cpu`      | CPU limit      | `"1000m"` |
| `resources.limits.memory`   | Memory limit   | `"1Gi"`   |
| `resources.requests.cpu`    | CPU request    | `"100m"`  |
| `resources.requests.memory` | Memory request | `"128Mi"` |

### Horizontal Pod Autoscaler

| Parameter                                    | Description            | Default |
| -------------------------------------------- | ---------------------- | ------- |
| `autoscaling.enabled`                        | Enable HPA             | `false` |
| `autoscaling.minReplicas`                    | Minimum replicas       | `1`     |
| `autoscaling.maxReplicas`                    | Maximum replicas       | `100`   |
| `autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization | `80`    |

## Upgrading

### Standalone Upgrade

```bash
helm upgrade governance-service ./charts/governance-service \
  --namespace governance \
  --values values.yaml
```

### As Part of Governance Studio

```bash
helm upgrade governance-studio ./charts/governance-studio \
  --namespace governance \
  --values values.yaml
```

## Uninstallation

### Standalone Uninstall

```bash
helm uninstall governance-service -n governance
```

### Full Platform Uninstall

```bash
helm uninstall governance-studio -n governance
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n governance -l app.kubernetes.io/name=governance-service
kubectl logs -f deployment/governance-service -n governance
```

### Verify Configuration

```bash
kubectl get configmap -n governance | grep governance-service
kubectl describe deployment governance-service -n governance
```

### Common Issues

1. **Database Connection**: Verify database credentials and connectivity
2. **Image Pull**: Ensure image pull secrets are configured if using private registry
3. **Resource Limits**: Check if pods are being OOMKilled due to memory limits

## API Endpoints

When deployed, the Governance Service provides the following API endpoints:

- `GET /health` - Health check endpoint
- Additional endpoints as documented in the API specification

## Integration

The Governance Service API integrates with:

- **PostgreSQL**: For data persistence
- **Governance UI**: Frontend interface
- **Compliance Garage**: For compliance-related assurance data
- **Integrity Service**: For data integrity validation

## Support

For support and documentation:

- GitHub Repository: https://github.com/eqtylab/governance-service
- Email: support@eqtylab.io
