# Governance Platform Deployment

> Helm charts, deployment guides, and helper tooling for deploying the **EQTY Lab Governance Platform** on Kubernetes. Supports Microsoft Entra ID, Keycloak, and Auth0 as identity providers, with cloud-agnostic storage and key vault integration (Azure, AWS, GCP).

## 📁 Repository Structure

- **`charts/`**
  Umbrella chart (`governance-platform`) and subcharts for each service (auth, governance, integrity, studio), plus bootstrap charts for Entra ID and Keycloak identity provider setup.
  ➡️ [View Charts README](./charts/README.md)

- **`docs/`**
  Step-by-step deployment guides for each identity provider ([Entra ID](./docs/deployment-guide-entra.md), [Keycloak](./docs/deployment-guide-keycloak.md)).

- **`govctl/`**
  CLI tool that interactively generates bootstrap, values, and secrets files for your environment.
  ➡️ [View govctl README](./govctl/README.md)

- **`scripts/`**
  Helper scripts for NGINX ingress setup, cert-manager installation, IdP bootstrap, and post-install database seeding.
  ➡️ [View Scripts README](./scripts/README.md)

## 🚀 Usage

Refer to the READMEs in each subdirectory for details on setup, environment structure, and deployment instructions.
