# Governance Platform CLI (govctl)

CLI tool for generating Governance Platform Helm values and secrets files.

> **Note:** This tool generates the minimum viable configuration to get up and running. For advanced or service-specific options, refer to the individual chart READMEs under `charts/`.

## Installation

Requires Python 3.10+. Run from the `govctl/` directory:

```bash
# With uv (recommended)
uv pip install -e .

# Or with pip
python3 -m venv env && source env/bin/activate
pip install -e .
```

Verify the installation:

```bash
govctl --help
```

## Prerequisites

Before running `govctl init`, you'll need the following in place:

### Infrastructure

- **Kubernetes cluster** — a running cluster on GCP (GKE), AWS (EKS), or Azure (AKS)
- **Helm** — installed locally
- **NGINX Ingress Controller** — deployed to the cluster
- **cert-manager** — deployed with a `letsencrypt-prod` ClusterIssuer configured
- **Domain** — with DNS pointing to the cluster's ingress load balancer

### Storage

- **Object storage** — for governance artifacts and integrity data
  - GCP: GCS bucket
  - AWS: S3 bucket
  - Azure: Blob Storage account and container
- **Azure Key Vault** — for DID key management (required regardless of cloud provider)

### Auth Provider

Set up one of the following before deployment:

- **Auth0** — tenant with M2M and SPA applications configured
- **Keycloak** — instance accessible at your domain (e.g. `https://{domain}/keycloak`)
- **Microsoft Entra ID** — app registration with appropriate API permissions

### Container Registry

- Access to a container registry (default: `ghcr.io`) with the platform images
- A personal access token or service account with `read:packages` scope

## Usage

```bash
govctl init

╭──────────────────────────────────────────╮
│ Governance Studio Platform Configuration │
│ Generate Helm values for your deployment │
╰──────────────────────────────────────────╯

Cloud provider [gcp/aws/azure] (gcp): azure
Domain (governance.example.com): governance.example.com
Environment (staging): staging
Auth provider [auth0/keycloak/entra] (keycloak): keycloak

Provider-specific configuration:

  Configure Azure Key Vault for DID keys? [y/n] (y): y
  Azure Key Vault URL (https://your-keyvault.vault.azure.net/): https://my-keyvault.vault.azure.net/
  Azure Tenant ID (): 00000000-0000-0000-0000-000000000000
  Keycloak URL (https://governance.example.com/keycloak):
  Keycloak realm (governance):

Image registry configuration:
  Registry URL (ghcr.io):
  Registry username (): my-username
  Registry email ():

                        Configuration Summary
┏━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Setting           ┃ Value                                          ┃
┡━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ Cloud Provider    │ AZURE                                          │
│ Domain            │ governance.example.com                         │
│ Environment       │ staging                                        │
│ Auth Provider     │ keycloak                                       │
│ Storage Provider  │ azure_blob                                     │
│ Key Vault URL     │ https://my-keyvault.vault.azure.net/           │
│ Keycloak URL      │ https://governance.example.com/keycloak        │
│ Keycloak Realm    │ governance                                     │
│ Image Registry    │ ghcr.io                                        │
│ Registry Username │ my-username                                    │
└───────────────────┴────────────────────────────────────────────────┘

Generate files with this configuration? [y/n]: y

Files generated successfully!

  output/values-staging.yaml
  output/secrets-staging.yaml
  output/bootstrap-staging.yaml

Next steps:

  1. Fill in any remaining secrets in output/secrets-staging.yaml

  2. Review output/values-staging.yaml and output/bootstrap-staging.yaml for correctness

  3. Follow the deployment guide for your auth provider before deploying
     See: https://github.com/eqtylab/deployment/tree/main/docs

  4. Run the Keycloak bootstrap:

     helm upgrade --install keycloak-bootstrap ./charts/keycloak-bootstrap \
       -f output/bootstrap-staging.yaml \
       -n governance --wait

  5. Deploy the platform:

     helm upgrade --install governance-platform ./charts/governance-platform \
       -f output/values-staging.yaml \
       -f output/secrets-staging.yaml \
       -n governance --create-namespace
```

The interactive wizard walks you through:

1. **Cloud provider** — GCP, AWS, or Azure
2. **Domain** — your deployment domain
3. **Environment** — freeform (e.g. `dev`, `staging`, `prod`)
4. **Auth provider** — Auth0, Keycloak, or Microsoft Entra ID
5. **Provider-specific settings** — Key Vault, auth config, etc.
6. **Image registry** — container registry credentials

Generated files:

| File                   | Contents                                           | When               |
| ---------------------- | -------------------------------------------------- | ------------------ |
| `values-{env}.yaml`    | Helm values for your deployment                    | Always             |
| `secrets-{env}.yaml`   | Secret placeholders to fill in before deploying    | Always             |
| `bootstrap-{env}.yaml` | Keycloak bootstrap values (realm, clients, scopes) | Keycloak auth only |

### Non-Interactive Mode

All flags are required in non-interactive mode:

```bash
govctl init -I \
  --cloud gcp \
  --domain governance.example.com \
  --environment staging \
  --auth keycloak
```

### CLI Options

| Flag                             | Short   | Description                                  |
| -------------------------------- | ------- | -------------------------------------------- |
| `--cloud`                        | `-c`    | Cloud provider (`gcp`, `aws`, `azure`)       |
| `--domain`                       | `-d`    | Deployment domain                            |
| `--environment`                  | `-e`    | Environment name                             |
| `--auth`                         | `-a`    | Auth provider (`auth0`, `keycloak`, `entra`) |
| `--output`                       | `-o`    | Output directory (default: `output`)         |
| `--interactive/--no-interactive` | `-i/-I` | Toggle interactive mode                      |

## What Gets Generated

### values-{env}.yaml

Configures all platform services based on your selections:

- **global** — environment name, domain
- **auth-service** — IDP provider config, token exchange, ingress
- **governance-service** — storage provider, cloud-specific config, ingress
- **governance-studio** — frontend auth config, feature flags, ingress
- **integrity-service** — blob storage config, persistence, ingress
- **postgresql** — storage class, resource limits

### bootstrap-{env}.yaml _(Keycloak only)_

Pre-configured values for the `keycloak-bootstrap` chart with your domain filled in:

- **Realm** — governance realm with security settings and token lifespans
- **Clients** — frontend (public), backend (confidential), and worker OAuth clients
- **Scopes** — authorization scopes for governance, integrity, organizations, projects, evaluations
- **Users** — platform-admin user

### secrets-{env}.yaml

Only includes secrets relevant to your configuration:

- **Database** — PostgreSQL credentials
- **Auth service** — API secret, JWT secret
- **Encryption** — platform encryption key
- **Auth provider** — Auth0 _or_ Keycloak _or_ Entra secrets (not all three)
- **Storage** — GCS _or_ S3 _or_ Azure Blob credentials
- **Image registry** — pull secret for container images
- **Azure Key Vault** — credentials for DID key management

## Next Steps

After generating your files, follow the deployment guide for your auth provider:

- [Auth0 Deployment Guide](https://github.com/eqtylab/deployment/blob/main/docs/deployment-guide-auth0.md)
- [Keycloak Deployment Guide](https://github.com/eqtylab/deployment/blob/main/docs/deployment-guide-keycloak.md)
- [Entra ID Deployment Guide](https://github.com/eqtylab/deployment/blob/main/docs/deployment-guide-entra.md)
