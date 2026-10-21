# Guardian Platform Helm Charts

This repository contains Helm charts for deploying the Guardian Platform on Kubernetes.

## Chart Catalog

| Chart                                     | Type     | Description                                                  |
| ----------------------------------------- | -------- | ------------------------------------------------------------ |
| [auth-service](auth-service/)             | Subchart | Go-based authentication and authorization service            |
| [auth0-bootstrap](auth0-bootstrap/)       | Utility  | Auth0 application, API, and user configuration job           |
| [entra-bootstrap](entra-bootstrap/)       | Utility  | Microsoft Entra ID app registration configuration job        |
| [eqty-pdfgen](eqty-pdfgen/)               | Subchart | PDF and ZIP rendering service for governance manifests       |
| [gateway-stack](gateway-stack/)           | Subchart | LLM Gateway and Control Plane                                |
| [governance-ops](governance-ops/)         | Ops      | Operational monitoring (dashboards, alerts, endpoint probes) |
| [guardian-platform](guardian-platform/)   | Umbrella | Complete platform deployment (recommended)                   |
| [governance-service](governance-service/) | Subchart | Go-based backend API and workflow engine                     |
| [guardian](guardian/)                     | Subchart | React-based frontend application                             |
| [integrity-service](integrity-service/)   | Subchart | Rust-based verifiable credentials and lineage service        |
| [keycloak-bootstrap](keycloak-bootstrap/) | Utility  | Keycloak realm and client configuration job                  |
| [openbao-custody](openbao-custody/)       | Custody  | Separately managed OpenBao release for Auth signing keys     |

## Architecture

The chart repository is organized using an **umbrella chart pattern**:

```
charts/
├── auth-service/            # Authentication subchart
├── auth0-bootstrap/         # Auth0 configuration utility
├── entra-bootstrap/         # Entra ID configuration utility
├── eqty-pdfgen/             # Manifest PDF rendering subchart
├── gateway-stack/           # Gateway and control plane subchart
├── governance-ops/          # Operational monitoring (dashboards, alerts)
├── guardian-platform/       # Umbrella chart (deploy this for full platform)
│   ├── Chart.yaml           # Dependencies on all subcharts
│   ├── values.yaml          # Global configuration + subchart overrides
│   └── templates/           # Shared resources (secrets, configmaps)
├── governance-service/      # Backend API subchart
├── guardian/                # Frontend subchart
├── integrity-service/       # Credentials/lineage subchart
├── keycloak-bootstrap/      # Keycloak configuration utility
└── openbao-custody/         # Separate OpenBao release for Auth signing keys (not in the umbrella)
```

**Recommended approach**: Deploy using the `guardian-platform` umbrella chart. This provides:

- Centralized configuration through global values
- Automatic service discovery and integration
- Coordinated secret management
- Consistent versioning across components

**Alternative**: Subcharts can be deployed individually for advanced use cases.

## Quick Start

### Prerequisites

- Kubernetes 1.29+
- Helm 3.20+
- kubectl configured for your cluster
- Registry access: Cloudsmith prod entitlement for verified deliveries; existing GHCR credentials otherwise

The optional development `openbao-custody` release requires Kubernetes 1.30+
because its pinned upstream chart 0.29.5 does. The platform minimum remains
1.29; using an external OpenBao does not require installing this chart.

### Deploy the Platform

**1. Set up an identity provider**

The platform requires an identity provider for authentication. Choose one and configure it before proceeding:

| Provider | What You Need                                                     |
| -------- | ----------------------------------------------------------------- |
| Auth0    | An Auth0 tenant with API and SPA applications                     |
| Entra ID | Azure tenant with admin access to create app registrations        |
| Keycloak | A running Keycloak instance (can be deployed in the same cluster) |

**2. Provision cloud infrastructure**

The platform requires object storage (for artifacts) and a key vault (for DID keys):

| Provider | Storage                          | Key Vault       |
| -------- | -------------------------------- | --------------- |
| AWS      | S3 Bucket                        | Secrets Manager |
| Azure    | Storage Account + Blob Container | Azure Key Vault |
| GCP      | GCS Bucket                       | Cloud KMS       |

**3. Configure networking and TLS**

Set up ingress, DNS, and certificate management:

- Install the [NGINX Ingress Controller](../scripts/services/nginx.sh) as the default ingress class
- Create a DNS A-record pointing your domain to the ingress external IP
- Install [cert-manager](../scripts/services/cert-manager.sh) and create a Let's Encrypt Issuer for automatic TLS

**4. Create namespace**

```bash
kubectl create namespace guardian
```

**5. Generate bootstrap, values, and secrets files**

Use [govctl](../govctl/) to generate all three interactively, or copy examples and customize manually:

```bash
# Option A: govctl (recommended)
govctl init

# Option B: Copy examples
# Values:
cp guardian-platform/examples/values-<provider>.yaml values.yaml

# Bootstrap (Auth0, Entra, or Keycloak):
cp <provider>-bootstrap/examples/values.yaml bootstrap-values.yaml

# Secrets:
cp guardian-platform/examples/secrets-sample.yaml secrets.yaml
```

Edit each file with your environment-specific settings. See [Chart Values](https://guardian.docs.eqtylab.io/deployment/chart-values/) for field-by-field details.

**6. Create Kubernetes secrets**

Either pass `secrets.yaml` during helm install (`--values secrets.yaml`), or create them manually with `kubectl`. See [guardian-platform/README.md](guardian-platform/README.md) for the full list of required secrets.

**7. Run IdP bootstrap**

This creates the required identity provider configuration (apps/API/users for Auth0, app registrations for Entra, realm/clients for Keycloak):

```bash
# Auth0
helm upgrade --install auth0-bootstrap ./auth0-bootstrap \
  --namespace guardian \
  --values bootstrap-values.yaml \
  --wait --timeout 10m

# Entra
helm upgrade --install entra-bootstrap ./entra-bootstrap \
  --namespace guardian \
  --values bootstrap-values.yaml \
  --wait --timeout 10m

# Keycloak
helm upgrade --install keycloak-bootstrap ./keycloak-bootstrap \
  --namespace guardian \
  --values bootstrap-values.yaml \
  --wait --timeout 10m
```

Helper scripts are also available in `scripts/auth0/`, `scripts/entra/`, and `scripts/keycloak/` — see the identity provider pages on the [docs site](https://guardian.docs.eqtylab.io/deployment/authentication/) for details.

**8. Deploy**

```bash
helm dependency update ./guardian-platform
helm upgrade --install guardian-platform ./guardian-platform \
  --namespace guardian \
  --values values.yaml
```

The Agent Gateway is opt-in for upgrade safety. Add
`guardian-platform/examples/values-gateway.yaml` to the Helm command to enable
it, and provide the `gateway-dsn` key in `platform-database` when using an
externally managed Secret.

**9. Verify**

```bash
kubectl get pods -n guardian
```

For complete documentation, see [Deployment Process](https://guardian.docs.eqtylab.io/deployment/deployment-process/) and [guardian-platform/README.md](guardian-platform/README.md).

## Installation Methods

### From Local Directory

```bash
# Update dependencies
helm dependency update ./guardian-platform

# Install
helm upgrade --install guardian-platform ./guardian-platform \
  --namespace guardian \
  --create-namespace \
  --values values.yaml
```

### From a hosted chart repository

Until your version has a verified Cloudsmith delivery, use the GHCR command below.
For a stable version with `cloudsmith-delivery.json`, follow [Cloudsmith setup](../docs/cloudsmith.md)
and use the delivered chart with its overlay. With Helm 3.20 or later, load your
prod entitlement into `CLOUDSMITH_ENTITLEMENT_TOKEN` through your secret manager:

```bash
printf '%s' "$CLOUDSMITH_ENTITLEMENT_TOKEN" | helm repo add cloudsmith-prod \
  https://dl.cloudsmith.io/basic/eqtylab/prod/helm/charts/ \
  --username token --password-stdin
helm repo update cloudsmith-prod
helm upgrade --install guardian-platform cloudsmith-prod/guardian-platform \
  --version <released-version> --namespace guardian --create-namespace \
  --values values.yaml --values values-cloudsmith.yaml
```

Existing GHCR installation:

```bash
# Authenticate with GitHub Container Registry
echo $GITHUB_PAT | helm registry login ghcr.io -u USERNAME --password-stdin

# Install from registry
helm upgrade --install guardian-platform oci://ghcr.io/eqtylab/charts/guardian-platform \
  --version 0.1.0 \
  --namespace guardian \
  --create-namespace \
  --values values.yaml
```

## Deployment Examples

The `guardian-platform/examples/` directory contains complete deployment examples:

| Example                                                                         | Description                                                                                                 |
| ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| [secrets-sample.yaml](guardian-platform/examples/secrets-sample.yaml)           | Complete secrets configuration template                                                                     |
| [values-cloudsmith.yaml](guardian-platform/examples/values-cloudsmith.yaml)     | Registry overlay for verified Cloudsmith deliveries                                                         |
| [values-auth0.yaml](guardian-platform/examples/values-auth0.yaml)               | Platform deployment using Auth0 as the identity provider                                                    |
| [values-entra.yaml](guardian-platform/examples/values-entra.yaml)               | Platform deployment using Entra ID as the identity provider                                                 |
| [values-keycloak.yaml](guardian-platform/examples/values-keycloak.yaml)         | Platform deployment using Keycloak as the identity provider                                                 |
| [values-openbao.yaml](guardian-platform/examples/values-openbao.yaml)           | Optional development OpenBao Transit overlay for Auth signing keys                                          |
| [values-openbao-kind.yaml](guardian-platform/examples/values-openbao-kind.yaml) | Disposable local-kind OpenBao diagnostic profile (not standalone; needs launcher-supplied publisher values) |

## Deployment Documentation

The deployment guides are on the docs site. [Deployment Process](https://guardian.docs.eqtylab.io/deployment/deployment-process/) is the full checklist; its steps in order:

1. [Prerequisites](https://guardian.docs.eqtylab.io/deployment/prerequisites/)
2. [Domain and TLS](https://guardian.docs.eqtylab.io/deployment/domain-and-tls/)
3. [Object storage](https://guardian.docs.eqtylab.io/deployment/object-storage/) and [key management](https://guardian.docs.eqtylab.io/deployment/key-management/)
4. [govctl](https://guardian.docs.eqtylab.io/deployment/govctl/) or [Chart Values](https://guardian.docs.eqtylab.io/deployment/chart-values/)
5. The identity provider: [Auth0](https://guardian.docs.eqtylab.io/deployment/auth0/), [Microsoft Entra ID](https://guardian.docs.eqtylab.io/deployment/microsoft-entra-id/), or [Keycloak](https://guardian.docs.eqtylab.io/deployment/keycloak/)
6. [Helm Deployment](https://guardian.docs.eqtylab.io/deployment/helm-deployment/)

## Development

### Working with Charts Locally

```bash
# Lint a chart
helm lint ./guardian-platform

# Template a chart (preview rendered manifests)
helm template guardian-platform ./guardian-platform \
  --values values.yaml \
  --debug

# Dry-run installation
helm upgrade --install guardian-platform ./guardian-platform \
  --namespace guardian \
  --values values.yaml \
  --dry-run --debug

# Diff against existing release (requires helm-diff plugin)
helm diff upgrade guardian-platform ./guardian-platform \
  --namespace guardian \
  --values values.yaml
```

### Updating Dependencies

```bash
# Update all subchart dependencies
helm dependency update ./guardian-platform

# List dependencies
helm dependency list ./guardian-platform
```

### Testing Changes

```bash
# Run helm unittest (if configured)
helm unittest ./guardian-platform

# Validate against Kubernetes API
helm upgrade --install guardian-platform ./guardian-platform \
  --namespace guardian \
  --values values.yaml \
  --dry-run=server
```

## Publishing Charts

Charts are published to GitHub Container Registry (GHCR) as OCI artifacts.

### Manual Publishing

```bash
# Authenticate
export CR_PAT="YOUR-GITHUB-PERSONAL-ACCESS-TOKEN"
echo $CR_PAT | helm registry login ghcr.io -u USERNAME --password-stdin

# Package chart
helm package ./guardian-platform

# Push to registry
helm push guardian-platform-0.1.0.tgz oci://ghcr.io/eqtylab/charts
```

### Automated Publishing

Chart changes are validated on PRs and main. Infrastructure publication requires
an explicit `workflow_dispatch` with `publish: true`; customer platform releases
publish from deployment. See [publish.yaml](../.github/workflows/publish.yaml).

Locally, `just publish openbao-custody` builds its locked dependency, packages,
and pushes `oci://ghcr.io/eqtylab/charts/openbao-custody` at its own chart version.
`just publish-all` deliberately includes this independent chart. Neither command
adds custody to `guardian-platform` or installs it. README and example profiles
are included in the custody archive for offline operator use.

## Chart Versioning

Charts follow [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes to values schema or removed features
- **MINOR**: New features, new configuration options
- **PATCH**: Bug fixes, documentation updates

The umbrella chart (`guardian-platform`) version is incremented when:

- Any subchart version changes
- Global configuration schema changes
- New subcharts are added

`openbao-custody` is an explicit exception to platform version alignment: chart
`version: 0.1.0` tracks the custody wrapper and `appVersion: 2.6.2` tracks OpenBao.
Its upstream chart is separately pinned to 0.29.5 in `Chart.yaml` and `Chart.lock`.
Changing it does not require a platform version bump. See the
[release-policy exception and downstream requirements](../docs/formal-release-process.md#independent-openbao-custody-release).

## Documentation

| Document                                                     | Description                                                 |
| ------------------------------------------------------------ | ----------------------------------------------------------- |
| [auth-service/README.md](auth-service/README.md)             | Authentication service configuration                        |
| [auth0-bootstrap/README.md](auth0-bootstrap/README.md)       | Auth0 application/API/user setup                            |
| [entra-bootstrap/README.md](entra-bootstrap/README.md)       | Entra ID app registration setup                             |
| [eqty-pdfgen/README.md](eqty-pdfgen/README.md)               | PDF generation service configuration                        |
| [governance-ops/README.md](governance-ops/README.md)         | Operational monitoring setup                                |
| [guardian-platform/README.md](guardian-platform/README.md)   | Complete platform deployment guide                          |
| [governance-service/README.md](governance-service/README.md) | Backend API configuration                                   |
| [guardian/README.md](guardian/README.md)                     | Frontend configuration                                      |
| [integrity-service/README.md](integrity-service/README.md)   | Credentials service configuration                           |
| [keycloak-bootstrap/README.md](keycloak-bootstrap/README.md) | Keycloak realm/client configuration                         |
| [openbao-custody/README.md](openbao-custody/README.md)       | Optional OpenBao custody configuration and operator runbook |

## Support

- **Email**: support@eqtylab.io
- **Documentation**: https://guardian.docs.eqtylab.io
- **GitHub Issues**: https://github.com/eqtylab/guardian-infrastructure/issues
