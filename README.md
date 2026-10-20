# Guardian Platform Deployment

[![Helm CI](https://github.com/eqtylab/deployment/actions/workflows/helm-ci.yaml/badge.svg)](https://github.com/eqtylab/deployment/actions/workflows/helm-ci.yaml)
[![Release Platform Package](https://github.com/eqtylab/deployment/actions/workflows/release-platform-package.yaml/badge.svg)](https://github.com/eqtylab/deployment/actions/workflows/release-platform-package.yaml)

> Helm charts and helper tooling for deploying the **Guardian Platform** on Kubernetes. Supports Auth0, Microsoft Entra ID, and Keycloak as identity providers, with cloud-agnostic storage and key vault integration (AWS, Azure, GCP).

## 🚀 Quick Start

1. Review the [prerequisites](#-prerequisites). Use the existing GHCR installation path until your version has a verified `cloudsmith-delivery.json`; then follow [Cloudsmith setup](./docs/cloudsmith.md).
2. Follow [Deployment Process](https://guardian.docs.eqtylab.io/deployment/deployment-process/) on the docs site, including your identity provider's page:
   - [Auth0](https://guardian.docs.eqtylab.io/deployment/auth0/) · [Microsoft Entra ID](https://guardian.docs.eqtylab.io/deployment/microsoft-entra-id/) · [Keycloak](https://guardian.docs.eqtylab.io/deployment/keycloak/)
3. Use [`govctl`](./govctl/README.md) to generate Helm values and secrets (`--artifact-source github` for GHCR; the Cloudsmith default only for verified deliveries), then install the [`governance-platform`](./charts/governance-platform/) umbrella chart.

## ✅ Prerequisites

- Kubernetes **1.29+**
- Helm **3.20+**
- `kubectl` configured for your target cluster
- GitHub package read credentials for GHCR, or an EQTY-issued Cloudsmith prod entitlement for a version with verified delivery
- A configured identity provider (Auth0, Microsoft Entra ID, or Keycloak)
- A cloud account (AWS, Azure, or GCP) with object storage and a key/secret vault provisioned for the platform

## 📁 Repository Structure

- **[`charts/`](./charts/README.md)** — Helm charts for the Guardian Platform services (auth, governance, integrity, Guardian) plus per-IdP bootstrap charts.
- **[`docs/`](./docs/)** — [Cloudsmith setup](./docs/cloudsmith.md), the [Cloudsmith release runbook](./docs/cloudsmith-release.md), and the optional [OpenBao custody delivery](./docs/openbao-delivery.md) notes. Deployment guides are on the [docs site](https://guardian.docs.eqtylab.io/deployment/deployment-process/).
- **[`govctl/`](./govctl/README.md)** — CLI tool for generating Helm values, bootstrap configs, and secrets files interactively.
- **[`scripts/`](./scripts/README.md)** — Helper scripts for NGINX ingress setup, cert-manager installation, IdP bootstrap, post-install database seeding, OpenBao operator setup, and release packaging checks.
- **[`releases/`](./releases/)** — Per-version release manifests pinning chart versions, image digests, and source refs for each platform release.
- **[`containers/`](./containers/)** — Custom container image builds (e.g. patched PostgreSQL) used by the platform.
- **[`schemas/`](./schemas/)** — JSON schemas for release manifests and other structured artifacts in this repo.

## 📦 Versioning

Each platform release has a manifest under [`releases/`](./releases/) that pins the exact chart versions, image digests, and source refs that make up that release. Match the release version to the chart and image versions you deploy — do not mix versions across releases.

The docs site's deployment pages describe the latest release; earlier releases are archived on the site under `/v<version>/`. Releases from before the guides moved to the docs site also have them in this repository at their `platform/v<version>` tag.

The optional [`openbao-custody` delivery](./docs/openbao-delivery.md) has its own
wrapper version and Kubernetes 1.30+ minimum. It is published and packaged only
when explicitly selected in the release manifest; it is never an umbrella
dependency. OpenBao application use remains development-only.

## 💬 Support

For questions, deployment assistance, or issues, contact your EQTY Lab representative or open an issue in this repository.

Release operators: [Cloudsmith mirroring and activation](./docs/cloudsmith-release.md).
Internal infrastructure continues to use GHCR; use `govctl init --artifact-source github`.
