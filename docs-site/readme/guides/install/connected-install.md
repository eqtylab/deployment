# Connected Install

Connected installs pull public Helm charts from GHCR and private runtime images
from GHCR using customer-specific image pull credentials.

## Prerequisites

- Kubernetes 1.29 or newer
- Helm 3.20 or newer
- External Postgres
- Ingress and TLS configured for the customer domain
- Image pull credentials for `ghcr.io/eqtylab`

## Install

Use the platform version from the release manifest:

```bash
helm upgrade --install governance-platform oci://ghcr.io/eqtylab/charts/governance-platform \
  --version 0.1.0 \
  --namespace governance \
  --create-namespace \
  --values values.yaml
```

After install, verify pods are ready and then validate the Studio login path and
backend health endpoints.
