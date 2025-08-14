# Integrity Service

This Helm chart deploys the Integrity Service, which provides data integrity and auditability capabilities for the Governance Studio platform.

## Overview

The Integrity Service is a core component of the Governance Studio platform that handles:
- Data integrity validation and verification
- Audit trail management
- Blockchain integration for immutable records
- Cryptographic proof generation and validation

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- PostgreSQL database (provided by umbrella chart or external)
- Persistent volume provisioner support in the underlying infrastructure

## Installation

### Standalone Installation

```bash
# Install the chart
helm install integrity ./charts/integrity \
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

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Container image repository | `"ghcr.io/eqtylab/integrity"` |
| `image.tag` | Container image tag | `"latest"` |
| `image.pullPolicy` | Image pull policy | `"IfNotPresent"` |
| `replicaCount` | Number of pod replicas | `1` |

### Database Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `database.host` | Database hostname | `"postgresql"` |
| `database.port` | Database port | `5432` |
| `database.name` | Database name | `"integrity"` |
| `database.existingSecret` | Existing secret with database credentials | `""` |

### Service Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Kubernetes service type | `"ClusterIP"` |
| `service.port` | Service port | `8080` |
| `service.targetPort` | Container target port | `8080` |

### Ingress Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | Ingress class name | `"nginx"` |
| `ingress.hosts` | Ingress hostnames | `[]` |
| `ingress.tls` | TLS configuration | `[]` |

### Blockchain Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `blockchain.enabled` | Enable blockchain integration | `true` |
| `blockchain.network` | Blockchain network to connect to | `"ethereum"` |
| `blockchain.providerUrl` | Blockchain provider URL | `""` |
| `blockchain.contractAddress` | Smart contract address | `""` |

### Resource Limits

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.limits.cpu` | CPU limit | `"1000m"` |
| `resources.limits.memory` | Memory limit | `"1Gi"` |
| `resources.requests.cpu` | CPU request | `"100m"` |
| `resources.requests.memory` | Memory request | `"128Mi"` |

## Upgrading

### Standalone Upgrade

```bash
helm upgrade integrity ./charts/integrity \
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
helm uninstall integrity -n governance
```

### Full Platform Uninstall

```bash
helm uninstall governance-studio -n governance
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n governance -l app.kubernetes.io/name=integrity
kubectl logs -f deployment/integrity -n governance
```

### Verify Configuration

```bash
kubectl get configmap -n governance | grep integrity
kubectl describe deployment integrity -n governance
```

### Common Issues

1. **Database Connection**: Verify database credentials and connectivity
2. **Blockchain Connection**: Check blockchain provider URL and network connectivity
3. **Image Pull**: Ensure image pull secrets are configured if using private registry
4. **Resource Limits**: Check if pods are being OOMKilled due to memory limits

## API Endpoints

When deployed, the Integrity Service provides the following API endpoints:

- `GET /health` - Health check endpoint
- `POST /api/v1/integrity/verify` - Verify data integrity
- `POST /api/v1/integrity/record` - Record data for integrity tracking
- `GET /api/v1/integrity/audit/{id}` - Get audit trail for specific record
- Additional endpoints as documented in the API specification

## Integration

The Integrity Service integrates with:
- **PostgreSQL**: For data persistence and audit trail storage
- **Blockchain Networks**: For immutable record keeping
- **Governance UI**: Frontend interface for integrity operations
- **Compliance Garage**: For compliance-related integrity validation
- **Assurance Engine**: For assurance data integrity verification

## Security Features

- **Cryptographic Hashing**: Uses industry-standard algorithms for data integrity
- **Digital Signatures**: Supports digital signature verification
- **Blockchain Anchoring**: Optionally anchors critical data to blockchain networks
- **Audit Trails**: Maintains comprehensive audit logs for all operations

## Support

For support and documentation:
- GitHub Repository: https://github.com/eqtylab/governance-studio
- Email: support@eqtylab.io