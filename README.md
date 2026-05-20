# Governance Platform Deployment

> Helm charts, deployment guides, and helper tooling for deploying the **EQTY Lab Governance Platform** on Kubernetes. Supports Auth0, Microsoft Entra ID, and Keycloak as identity providers, with cloud-agnostic storage and key vault integration (AWS, Azure, GCP).

## 📁 Repository Structure

- **`charts/`**
  Helm charts for the Governance Platform services (auth, governance, integrity, studio) plus per-IdP bootstrap charts.
  ➡️ [View Charts README](./charts/README.md)

- **`docs/`**
  Step-by-step deployment guides for each identity provider (Auth0, Entra ID, Keycloak).
  ➡️ [View Docs](./docs/)

- **`govctl/`**
  CLI tool for generating Helm values, bootstrap configs, and secrets files interactively.
  ➡️ [View govctl README](./govctl/README.md)

- **`scripts/`**
  Helper scripts for NGINX ingress setup, cert-manager installation, IdP bootstrap, and post-install database seeding.
  ➡️ [View Scripts README](./scripts/README.md)

## 🚀 Usage

Refer to the READMEs in each subdirectory for details on setup, environment structure, and deployment instructions.
