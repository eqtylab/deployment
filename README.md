# Governance Platform Helm Charts

This repository contains Helm charts for deploying the EQTY Lab Governance Platform on Kubernetes.

## Chart Catalog

| Chart                                              | Type     | Description                                           |
| -------------------------------------------------- | -------- | ----------------------------------------------------- |
| [governance-platform](charts/governance-platform/) | Umbrella | Complete platform deployment (recommended)            |
| [governance-studio](charts/governance-studio/)     | Subchart | React-based frontend application                      |
| [governance-service](charts/governance-service/)   | Subchart | Go-based backend API and workflow engine              |
| [integrity-service](charts/integrity-service/)     | Subchart | Rust-based verifiable credentials and lineage service |
| [auth-service](charts/auth-service/)               | Subchart | Go-based authentication and authorization service     |
| [keycloak-bootstrap](charts/keycloak-bootstrap/)   | Utility  | Keycloak realm and client configuration job           |

## Architecture

The chart repository is organized using an **umbrella chart pattern**:

```
charts/
├── governance-platform/     # Umbrella chart (deploy this for full platform)
│   ├── Chart.yaml           # Dependencies on all subcharts
│   ├── values.yaml          # Global configuration + subchart overrides
│   └── templates/           # Shared resources (secrets, configmaps)
├── governance-studio/       # Frontend subchart
├── governance-service/      # Backend API subchart
├── integrity-service/       # Credentials/lineage subchart
├── auth-service/            # Authentication subchart
└── keycloak-bootstrap/      # Keycloak configuration utility
```

**Recommended approach**: Deploy using the `governance-platform` umbrella chart. This provides:

- Centralized configuration through global values
- Automatic service discovery and integration
- Coordinated secret management
- Consistent versioning across components

**Alternative**: Subcharts can be deployed individually for advanced use cases.

## Quick Start

### Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- kubectl configured for your cluster
- Container registry access (GitHub Container Registry)

### Deploy the Platform

```bash
# 1. Create namespace
kubectl create namespace governance

# 2. Create required secrets (see charts/governance-platform/README.md for full list)
kubectl create secret generic platform-database \
  --from-literal=username=postgres \
  --from-literal=password="$(openssl rand -base64 24)" \
  --namespace governance

kubectl create secret generic platform-auth0 \
  --from-literal=domain=your-tenant.us.auth0.com \
  --from-literal=client-id=YOUR_CLIENT_ID \
  --from-literal=client-secret=YOUR_CLIENT_SECRET \
  --namespace governance

# ... additional secrets as documented in charts/governance-platform/README.md

# 3. Create values file
cat > values.yaml <<EOF
global:
  domain: "governance.yourcompany.com"
  environmentType: "production"
  secrets:
    create: false

governance-studio:
  enabled: true
  ingress:
    enabled: true
    className: nginx

governance-service:
  enabled: true
  config:
    storageProvider: "gcs"
    gcsBucketName: "your-bucket"

integrity-service:
  enabled: true
  env:
    integrityAppBlobStoreType: "azure_blob"
    integrityAppBlobStoreAccount: "youraccount"
    integrityAppBlobStoreContainer: "integrity-data"

auth-service:
  enabled: true

postgresql:
  enabled: true
EOF

# 4. Deploy
helm dependency update ./charts/governance-platform
helm install governance-platform ./charts/governance-platform \
  --namespace governance \
  --values values.yaml

# 5. Verify
kubectl get pods -n governance
```

For complete documentation, see [governance-platform/README.md](charts/governance-platform/README.md).

## Installation Methods

### From Local Directory

```bash
# Update dependencies
helm dependency update ./charts/governance-platform

# Install
helm install governance-platform ./charts/governance-platform \
  --namespace governance \
  --create-namespace \
  --values values.yaml
```

### From OCI Registry

```bash
# Authenticate with GitHub Container Registry
echo $GITHUB_PAT | helm registry login ghcr.io -u USERNAME --password-stdin

# Install from registry
helm install governance-platform oci://ghcr.io/eqtylab/charts/governance-platform \
  --version 0.1.0 \
  --namespace governance \
  --create-namespace \
  --values values.yaml
```

## Cloud-Specific Examples

The `charts/governance-platform/examples/` directory contains complete deployment examples:

| Example                                                                                    | Description                             |
| ------------------------------------------------------------------------------------------ | --------------------------------------- |
| [values-aws-example.yaml](charts/governance-platform/examples/values-aws-example.yaml)     | AWS EKS with S3 storage                 |
| [values-azure-example.yaml](charts/governance-platform/examples/values-azure-example.yaml) | Azure AKS with Blob storage             |
| [values-gcp-example.yaml](charts/governance-platform/examples/values-gcp-example.yaml)     | GCP GKE with GCS storage                |
| [secrets-sample.yaml](charts/governance-platform/examples/secrets-sample.yaml)             | Complete secrets configuration template |

## Development

### Working with Charts Locally

```bash
# Lint a chart
helm lint ./charts/governance-platform

# Template a chart (preview rendered manifests)
helm template governance-platform ./charts/governance-platform \
  --values values.yaml \
  --debug

# Dry-run installation
helm install governance-platform ./charts/governance-platform \
  --namespace governance \
  --values values.yaml \
  --dry-run

# Diff against existing release (requires helm-diff plugin)
helm diff upgrade governance-platform ./charts/governance-platform \
  --namespace governance \
  --values values.yaml
```

### Updating Dependencies

```bash
# Update all subchart dependencies
helm dependency update ./charts/governance-platform

# List dependencies
helm dependency list ./charts/governance-platform
```

### Testing Changes

```bash
# Run helm unittest (if configured)
helm unittest ./charts/governance-platform

# Validate against Kubernetes API
helm install governance-platform ./charts/governance-platform \
  --namespace governance \
  --values values.yaml \
  --dry-run \
  --validate
```

## Publishing Charts

Charts are published to GitHub Container Registry (GHCR) as OCI artifacts.

### Manual Publishing

```bash
# Authenticate
export CR_PAT="YOUR-GITHUB-PERSONAL-ACCESS-TOKEN"
echo $CR_PAT | helm registry login ghcr.io -u USERNAME --password-stdin

# Package chart
helm package ./charts/governance-platform

# Push to registry
helm push governance-platform-0.1.0.tgz oci://ghcr.io/eqtylab/charts
```

### Automated Publishing

Charts are automatically published via GitHub Actions when changes are merged to main. See `.github/workflows/publish.yaml` for details.

## Chart Versioning

Charts follow [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes to values schema or removed features
- **MINOR**: New features, new configuration options
- **PATCH**: Bug fixes, documentation updates

The umbrella chart (`governance-platform`) version is incremented when:

- Any subchart version changes
- Global configuration schema changes
- New subcharts are added

## Documentation

| Document                                                              | Description                          |
| --------------------------------------------------------------------- | ------------------------------------ |
| [governance-platform/README.md](charts/governance-platform/README.md) | Complete platform deployment guide   |
| [governance-studio/README.md](charts/governance-studio/README.md)     | Frontend configuration               |
| [governance-service/README.md](charts/governance-service/README.md)   | Backend API configuration            |
| [integrity-service/README.md](charts/integrity-service/README.md)     | Credentials service configuration    |
| [auth-service/README.md](charts/auth-service/README.md)               | Authentication service configuration |
| [keycloak-bootstrap/README.md](charts/keycloak-bootstrap/README.md)   | Keycloak realm/client configuration  |

## Support

- **Email**: support@eqtylab.io
- **Documentation**: https://docs.eqtylab.io
- **GitHub Issues**: https://github.com/eqtylab/governance-studio-infrastructure/issues
