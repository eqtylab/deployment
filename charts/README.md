# Governance Platform Helm Charts

This repository contains Helm charts for deploying the EQTY Lab Governance Platform on Kubernetes.

## Chart Catalog

| Chart                                       | Type     | Description                                           |
| ------------------------------------------- | -------- | ----------------------------------------------------- |
| [auth-service](auth-service/)               | Subchart | Go-based authentication and authorization service     |
| [entra-bootstrap](entra-bootstrap/)         | Utility  | Microsoft Entra ID app registration configuration job |
| [governance-platform](governance-platform/) | Umbrella | Complete platform deployment (recommended)            |
| [governance-service](governance-service/)   | Subchart | Go-based backend API and workflow engine              |
| [governance-studio](governance-studio/)     | Subchart | React-based frontend application                      |
| [integrity-service](integrity-service/)     | Subchart | Rust-based verifiable credentials and lineage service |
| [keycloak-bootstrap](keycloak-bootstrap/)   | Utility  | Keycloak realm and client configuration job           |

## Architecture

The chart repository is organized using an **umbrella chart pattern**:

```
charts/
├── auth-service/            # Authentication subchart
├── entra-bootstrap/         # Entra ID configuration utility
├── governance-platform/     # Umbrella chart (deploy this for full platform)
│   ├── Chart.yaml           # Dependencies on all subcharts
│   ├── values.yaml          # Global configuration + subchart overrides
│   └── templates/           # Shared resources (secrets, configmaps)
├── governance-service/      # Backend API subchart
├── governance-studio/       # Frontend subchart
├── integrity-service/       # Credentials/lineage subchart
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

**1. Set up an identity provider**

The platform requires an identity provider for authentication. Choose one and configure it before proceeding:

| Provider | What You Need                                                     |
| -------- | ----------------------------------------------------------------- |
| Entra ID | Azure tenant with admin access to create app registrations        |
| Keycloak | A running Keycloak instance (can be deployed in the same cluster) |
| Auth0    | An Auth0 tenant with API and SPA applications                     |

**2. Provision cloud infrastructure**

The platform requires object storage (for artifacts) and a key vault (for DID keys):

| Provider | Storage                          | Key Vault       |
| -------- | -------------------------------- | --------------- |
| Azure    | Storage Account + Blob Container | Azure Key Vault |
| AWS      | S3 Bucket                        | Secrets Manager |
| GCP      | GCS Bucket                       | Cloud KMS       |

**3. Configure networking and TLS**

Set up ingress, DNS, and certificate management:

- Install the [NGINX Ingress Controller](../scripts/services/nginx.sh) as the default ingress class
- Create a DNS A-record pointing your domain to the ingress external IP
- Install [cert-manager](../scripts/services/cert-manager.sh) and create a Let's Encrypt Issuer for automatic TLS

**4. Create namespace**

```bash
kubectl create namespace governance
```

**5. Generate bootstrap, values, and secrets files**

Use [govctl](../govctl/) to generate all three interactively, or copy examples and customize manually:

```bash
# Option A: govctl (recommended)
govctl init

# Option B: Copy examples
# Values:
cp governance-platform/examples/values-<provider>.yaml values.yaml

# Bootstrap (Keycloak or Entra only):
cp <provider>-bootstrap/examples/values.yaml bootstrap-values.yaml

# Secrets:
cp governance-platform/examples/secrets-sample.yaml secrets.yaml
```

Edit each file with your environment-specific settings. See the [deployment guides](../docs/) for field-by-field details.

**6. Create Kubernetes secrets**

Either pass `secrets.yaml` during helm install (`--values secrets.yaml`), or create them manually with `kubectl`. See [governance-platform/README.md](governance-platform/README.md) for the full list of required secrets.

**7. Run IdP bootstrap** (Keycloak or Entra only)

This creates the required identity provider configuration (app registrations for Entra, realm/clients for Keycloak):

```bash
# Entra
helm upgrade --install entra-bootstrap ./entra-bootstrap \
  --namespace governance \
  --values bootstrap-values.yaml \
  --wait --timeout 10m

# Keycloak
helm upgrade --install keycloak-bootstrap ./keycloak-bootstrap \
  --namespace governance \
  --values bootstrap-values.yaml \
  --wait --timeout 10m
```

Helper scripts are also available in `scripts/entra/` and `scripts/keycloak/` — see the [deployment guides](../docs/) for details.

**8. Deploy**

```bash
helm dependency update ./governance-platform
helm upgrade --install governance-platform ./governance-platform \
  --namespace governance \
  --values values.yaml
```

**9. Verify**

```bash
kubectl get pods -n governance
```

For complete documentation, see the [deployment guides](../docs/) and [governance-platform/README.md](governance-platform/README.md).

## Installation Methods

### From Local Directory

```bash
# Update dependencies
helm dependency update ./governance-platform

# Install
helm upgrade --install governance-platform ./governance-platform \
  --namespace governance \
  --create-namespace \
  --values values.yaml
```

### From OCI Registry

```bash
# Authenticate with GitHub Container Registry
echo $GITHUB_PAT | helm registry login ghcr.io -u USERNAME --password-stdin

# Install from registry
helm upgrade --install governance-platform oci://ghcr.io/eqtylab/charts/governance-platform \
  --version 0.1.0 \
  --namespace governance \
  --create-namespace \
  --values values.yaml
```

## Deployment Examples

The `governance-platform/examples/` directory contains complete deployment examples:

| Example                                                                   | Description                                                 |
| ------------------------------------------------------------------------- | ----------------------------------------------------------- |
| [secrets-sample.yaml](governance-platform/examples/secrets-sample.yaml)   | Complete secrets configuration template                     |
| [values-auth0.yaml](governance-platform/examples/values-auth0.yaml)       | Platform deployment using Auth0 as the identity provider    |
| [values-entra.yaml](governance-platform/examples/values-entra.yaml)       | Platform deployment using Entra ID as the identity provider |
| [values-keycloak.yaml](governance-platform/examples/values-keycloak.yaml) | Platform deployment using Keycloak as the identity provider |

## Deployment Guides

The `docs/` directory contains step-by-step deployment guides:

| Guide                                                                | Description                                               |
| -------------------------------------------------------------------- | --------------------------------------------------------- |
| [deployment-guide-entra.md](../docs/deployment-guide-entra.md)       | End-to-end deployment using Entra ID as identity provider |
| [deployment-guide-keycloak.md](../docs/deployment-guide-keycloak.md) | End-to-end deployment using Keycloak as identity provider |

## Development

### Working with Charts Locally

```bash
# Lint a chart
helm lint ./governance-platform

# Template a chart (preview rendered manifests)
helm template governance-platform ./governance-platform \
  --values values.yaml \
  --debug

# Dry-run installation
helm upgrade --install governance-platform ./governance-platform \
  --namespace governance \
  --values values.yaml \
  --dry-run --debug

# Diff against existing release (requires helm-diff plugin)
helm diff upgrade governance-platform ./governance-platform \
  --namespace governance \
  --values values.yaml
```

### Updating Dependencies

```bash
# Update all subchart dependencies
helm dependency update ./governance-platform

# List dependencies
helm dependency list ./governance-platform
```

### Testing Changes

```bash
# Run helm unittest (if configured)
helm unittest ./governance-platform

# Validate against Kubernetes API
helm upgrade --install governance-platform ./governance-platform \
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
helm package ./governance-platform

# Push to registry
helm push governance-platform-0.1.0.tgz oci://ghcr.io/eqtylab/charts
```

### Automated Publishing

Charts are automatically published via GitHub Actions when changes are merged to main. See [publish.yaml](../.github/workflows/publish.yaml) for details.

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

| Document                                                       | Description                          |
| -------------------------------------------------------------- | ------------------------------------ |
| [auth-service/README.md](auth-service/README.md)               | Authentication service configuration |
| [entra-bootstrap/README.md](entra-bootstrap/README.md)         | Entra ID app registration setup      |
| [governance-platform/README.md](governance-platform/README.md) | Complete platform deployment guide   |
| [governance-service/README.md](governance-service/README.md)   | Backend API configuration            |
| [governance-studio/README.md](governance-studio/README.md)     | Frontend configuration               |
| [integrity-service/README.md](integrity-service/README.md)     | Credentials service configuration    |
| [keycloak-bootstrap/README.md](keycloak-bootstrap/README.md)   | Keycloak realm/client configuration  |

## Support

- **Email**: support@eqtylab.io
- **Documentation**: https://docs.eqtylab.io
- **GitHub Issues**: https://github.com/eqtylab/governance-studio-infrastructure/issues
