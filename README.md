# Governance Platform Deployment

[![Docsite CI](https://github.com/eqtylab/deployment/actions/workflows/docsite-ci.yaml/badge.svg)](https://github.com/eqtylab/deployment/actions/workflows/docsite-ci.yaml)
[![Helm CI](https://github.com/eqtylab/deployment/actions/workflows/helm-ci.yaml/badge.svg)](https://github.com/eqtylab/deployment/actions/workflows/helm-ci.yaml)
[![Release Platform Package](https://github.com/eqtylab/deployment/actions/workflows/release-platform-package.yaml/badge.svg)](https://github.com/eqtylab/deployment/actions/workflows/release-platform-package.yaml)

> Helm charts, deployment guides, and helper tooling for deploying the **EQTY Lab Governance Platform** on Kubernetes. Supports Auth0, Microsoft Entra ID, and Keycloak as identity providers, with cloud-agnostic storage and key vault integration (AWS, Azure, GCP).

## 🚀 Quick Start

1. Review the [prerequisites](#-prerequisites) below.
2. Pick your identity provider and follow the matching guide in [`docs/`](./docs/):
   - [Auth0](./docs/auth0/) · [Microsoft Entra ID](./docs/entra/) · [Keycloak](./docs/keycloak/)
3. Use [`govctl`](./govctl/README.md) to generate Helm values and secrets, then install the [`governance-platform`](./charts/governance-platform/) umbrella chart.

## ✅ Prerequisites

- Kubernetes **1.29+**
- Helm **4.0+**
- `kubectl` configured for your target cluster
- Pull access to the EQTY Lab container registry (GitHub Container Registry)
- A configured identity provider (Auth0, Microsoft Entra ID, or Keycloak)
- A cloud account (AWS, Azure, or GCP) with object storage and a key/secret vault provisioned for the platform

## 📁 Repository Structure

- **[`charts/`](./charts/README.md)** — Helm charts for the Governance Platform services (auth, governance, integrity, studio) plus per-IdP bootstrap charts.
- **[`docs/`](./docs/)** — Step-by-step deployment guides for each identity provider, with per-cloud variants (AWS, Azure, GCP).
- **[`govctl/`](./govctl/README.md)** — CLI tool for generating Helm values, bootstrap configs, and secrets files interactively.
- **[`scripts/`](./scripts/README.md)** — Helper scripts for NGINX ingress setup, cert-manager installation, IdP bootstrap, and post-install database seeding.
- **[`releases/`](./releases/)** — Per-version release manifests pinning chart versions, image digests, and source refs for each platform release.
- **[`containers/`](./containers/)** — Custom container image builds (e.g. patched PostgreSQL) used by the platform.
- **[`schemas/`](./schemas/)** — JSON schemas for release manifests and other structured artifacts in this repo.
- **[`docs-site/`](./docs-site/)** — Source for the hosted customer documentation site.

## 📦 Versioning

Each platform release has a manifest under [`releases/`](./releases/) that pins the exact chart versions, image digests, and source refs that make up that release. Match the release version to the chart and image versions you deploy — do not mix versions across releases.

## 💬 Support

For questions, deployment assistance, or issues, contact your EQTY Lab representative or open an issue in this repository.
