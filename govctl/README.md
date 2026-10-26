# The Guardian Platform CLI (govctl)

CLI tool for generating Guardian Platform Helm values and secrets files.

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

- **Kubernetes cluster** — a running cluster on AWS (EKS), Azure (AKS), or GCP (GKE)
- **Helm** — installed locally
- **NGINX Ingress Controller** — deployed to the cluster
- **cert-manager** — deployed with a `letsencrypt-prod` Issuer in the release namespace. The generated ingresses use the namespaced `cert-manager.io/issuer` annotation; for a ClusterIssuer, change it to `cert-manager.io/cluster-issuer`
- **Domain** — with DNS pointing to the cluster's ingress load balancer

### Storage

- **Object storage** — for governance artifacts and integrity data
  - AWS: S3 bucket (access via static keys, or an IAM role / IRSA — `govctl` will ask which). The IAM role covers S3 only: AWS KMS still needs static access keys in the `platform-aws-kms` secret
  - Azure: Blob Storage account and container
  - GCP: GCS bucket
- **Key management** — for DID signing keys (one of: AWS KMS, Azure Key Vault, or GCP KMS)

### Auth Provider

Set up one of the following before deployment:

- **Auth0** — tenant with M2M and SPA applications configured
- **Keycloak** — instance accessible at your domain (e.g. `https://{domain}/keycloak`). The URL you enter is also used by the bootstrap chart and the post-install hook
- **Microsoft Entra ID** — app registration with appropriate API permissions

### Container Registry

- Access to a container registry (default: `docker.cloudsmith.io`) with the platform images
- A Cloudsmith prod entitlement token from EQTY Lab

## Usage

```bash
govctl init
```

For the default Cloudsmith profile, the registry prompts are:

```text
Image Registry Configuration:
  Registry URL (docker.cloudsmith.io):
  Registry Username (eqtylab/prod):
  Registry Email ():
```

The confirmation summary includes the artifact source (`cloudsmith`), image
prefix (`docker.cloudsmith.io/eqtylab/prod`), registry host, and username. Review
these before generating the values, secrets, and bootstrap files.

After completing the provider bootstrap and secrets, the platform command for
an example staging installation is below. With Helm 3.20 or later, load your prod
entitlement into `CLOUDSMITH_ENTITLEMENT_TOKEN` through your secret manager first:

```bash
printf '%s' "$CLOUDSMITH_ENTITLEMENT_TOKEN" | helm repo add cloudsmith-prod \
  https://dl.cloudsmith.io/basic/eqtylab/prod/helm/charts/ \
  --username token --password-stdin
helm repo update cloudsmith-prod
helm upgrade --install guardian-platform \
  cloudsmith-prod/guardian-platform \
  --version <released-version> \
  -f output/values-staging.yaml \
  -f output/secrets-staging.yaml \
  -n guardian --create-namespace
```

Select a stable version with a verified `cloudsmith-delivery.json`. For a version
not yet delivered to Cloudsmith, generate GHCR settings with
`govctl init --artifact-source github` and use the existing GHCR install path.

The interactive wizard walks you through:

1. **Domain** — your deployment domain (required; there is no default)
2. **Environment** — a name such as `development` (the default), `staging`, or `production`, lowercased: up to 63 letters, digits, and hyphens, starting and ending with a letter or digit. `development` and `dev` also allow `http://localhost:5173` in the bootstrap files' callbacks and origins
3. **Database mode** — bundled Bitnami PostgreSQL (default unless the environment is `production`) or external managed PostgreSQL (default for `production`)
4. **Cloud provider** — AWS, Azure, or GCP. AWS also asks for the region and whether S3 uses an IAM role (IRSA) or static keys
5. **Key management** — AWS KMS, Azure Key Vault, or GCP KMS for DID keys (defaults to the cloud provider's service), with its settings. The Key Vault URL and GCP project ID have no default
6. **Auth provider** — Auth0, Microsoft Entra ID, or Keycloak, with its settings. The Auth0 domain has no default
7. **Image registry** — container registry host (with an optional port), image prefix for a custom registry, and credentials

Generated files:

| File                   | Contents                                            |
| ---------------------- | --------------------------------------------------- |
| `values-{env}.yaml`    | Helm values for your deployment                     |
| `secrets-{env}.yaml`   | Secret placeholders to fill in before deploying     |
| `bootstrap-{env}.yaml` | IdP bootstrap values for the selected auth provider |

### Non-Interactive Mode

`--cloud`, `--domain`, `--environment`, and `--auth` are required in non-interactive mode:

```bash
govctl init -I \
  --cloud gcp \
  --domain guardian.example.com \
  --environment staging \
  --auth keycloak \
  --database bundled
```

### CLI Options

| Flag                             | Short   | Description                                                                                                           |
| -------------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------- |
| `--cloud`                        | `-c`    | Cloud provider (`aws`, `azure`, `gcp`)                                                                                |
| `--domain`                       | `-d`    | Deployment domain, validated as a DNS name                                                                            |
| `--environment`                  | `-e`    | Environment name, lowercased and validated (e.g. `development`, `staging`, `production`)                              |
| `--auth`                         | `-a`    | Auth provider (`auth0`, `entra`, `keycloak`)                                                                          |
| `--database`                     | `-D`    | Database mode (`bundled` or `external`). Defaults to `external` when environment is `production`, otherwise `bundled` |
| `--artifact-source`              |         | `cloudsmith` (default) for verified customer releases; `github` for existing GHCR installs                            |
| `--output`                       | `-o`    | Output directory (default: `output`)                                                                                  |
| `--interactive/--no-interactive` | `-i/-I` | Toggle interactive mode                                                                                               |
| `--force`                        | `-f`    | Overwrite existing generated files without asking                                                                     |

Existing `values-{env}.yaml`, `secrets-{env}.yaml`, or `bootstrap-{env}.yaml` files in the output directory are not replaced silently: interactive mode asks first, and non-interactive mode exits unless `--force` is passed. Regenerating replaces every generated secret, so do not overwrite the secrets of an existing install. `secrets-{env}.yaml` is written with mode `0600`.

## What Gets Generated

### values-{env}.yaml

Configures all platform services based on your selections. Values the charts require that `govctl` cannot fill are left empty and marked `# REQUIRED: <label>`; replace the remaining `YOUR_*` placeholders too.

- **global** — environment name, domain. Also `global.postgresql.{host, port, database, username, sslMode, sslRootCert}` when database mode is `external`, with `host` marked `REQUIRED`
- **auth-service** — IDP provider config, key management, ingress, and token exchange for Keycloak and Entra
- **eqty-pdfgen** — cluster-internal manifest PDF rendering service (`enabled: true` by default; no ingress)
- **gateway-stack** — LLM Gateway and Control Plane (`enabled: false` by default, plus image overrides for GitHub output; hostnames, TLS, and plugin storage are not prompted for)
- **governance-service** — storage provider, cloud-specific config, ingress
- **guardian** — Guardian: frontend auth config, feature flags, ingress
- **integrity-service** — blob storage config, ingress
- **postgresql** — `enabled: true` plus persistence size and resource requests and limits when database mode is `bundled`; just `enabled: false` when `external`

To enable the gateway, layer [`values-gateway.yaml`](../charts/guardian-platform/examples/values-gateway.yaml) over the generated file and see [`charts/gateway-stack/README.md`](../charts/gateway-stack/README.md) for hostnames, TLS, and plugin setup.

PDFgen bound signing and optional timestamping are available through explicit values overrides: layer `eqty-pdfgen.config.signingBound`, `eqty-pdfgen.config.timestampUrl`, and compatible Auth/PDFgen image selections over the generated file. Verify the [image capability prerequisites](../charts/eqty-pdfgen/README.md#prerequisites) first. Bound signing is independent of the key-management provider; OpenBao remains optional. Full generator support for these settings is deferred.

When database mode is `external`, `global.postgresql.host` is marked `REQUIRED` — fill it in before deploying. The generated `gatewayDsn` in `secrets-{env}.yaml` contains `TODO-set-managed-pg-host.example.com` as its host; replace it with the same host. The `gatewayDsn` uses `sslmode=require`: gateway-stack does not read `global.postgresql.sslMode` or `sslRootCert`, so the gateway's connection is encrypted but the server certificate is not verified. The generated `secrets-{env}.yaml` already includes the `platform-database` Secret by default. For `sslMode: verify-ca` or `verify-full`, create a Secret named `postgres-ca` holding the CA bundle at key `ca.crt` before deploying, or use a ConfigMap and set `global.postgresql.sslRootCert.configMapName` in place of `secretName`. See the [Cloud-Managed PostgreSQL Configuration](../charts/guardian-platform/README.md#cloud-managed-postgresql-configuration) section of the chart README for the full setup and the manual-secret alternative.

### bootstrap-{env}.yaml

Pre-configured values for the matching `<provider>-bootstrap` chart with your domain filled in. The bootstrap charts are not published to Cloudsmith; install them from the `charts/` directory of [eqtylab/deployment](https://github.com/eqtylab/deployment). The bootstrap runs before the platform install, so pass `--create-namespace`:

```bash
helm upgrade --install keycloak-bootstrap ./charts/keycloak-bootstrap \
  -f output/bootstrap-staging.yaml \
  -n guardian --create-namespace --wait
```

Frontend callbacks and origins include `http://localhost:5173` only when the environment is `development` or `dev`.

The bootstrap file sets:

- **Auth0** — frontend SPA, backend M2M, worker M2M applications; Guardian Platform API (resource server) with scopes; client grants; platform-admin user; the Auth Service URL (`https://<domain>/authService`) the post-login Action calls
- **Keycloak** — platform realm with security settings and token lifespans; frontend (public), backend (confidential), and worker OAuth clients; authorization scopes; platform-admin user
- **Entra** — frontend (SPA), backend, and worker app registrations with Graph API permissions and the `access_as_user` scope

### secrets-{env}.yaml

Only includes secrets relevant to your configuration:

- **Database** — PostgreSQL credentials, plus a `gatewayDsn` connection string for the `guardian_gateway` database (only consumed when `gateway-stack` is enabled; it repeats the generated password, so change both together). With the bundled database, its host is `guardian-platform-postgresql`, which assumes the Helm release name `guardian-platform`; change the host if you install under another release name
- **Auth Service** — API secret, JWT secret
- **Auth provider** — Auth0 _or_ Entra _or_ Keycloak secrets (not all three); Entra and Keycloak include a generated token signing key
- **Storage** — AWS S3 _or_ Azure Blob _or_ GCS credentials (S3 credentials are omitted when using IAM role / IRSA access)
- **Image registry** — pull secret for container images (the GitHub username is marked `REQUIRED`)
- **Key management** — AWS KMS _or_ Azure Key Vault _or_ GCP KMS credentials for DID keys. AWS KMS always needs static access keys, even when S3 uses an IAM role. The GCP KMS service account JSON is marked `OPTIONAL`: leave it empty for Workload Identity

## Next Steps

After generating your files, fill in the placeholders described on the docs site's [govctl](https://guardian.docs.eqtylab.io/deployment/govctl/) page, then continue with [Deployment Process](https://guardian.docs.eqtylab.io/deployment/deployment-process/) and your identity provider's page: [Auth0](https://guardian.docs.eqtylab.io/deployment/auth0/), [Microsoft Entra ID](https://guardian.docs.eqtylab.io/deployment/microsoft-entra-id/), or [Keycloak](https://guardian.docs.eqtylab.io/deployment/keycloak/).

## OpenBao workflow

OpenBao is optional. The current supported configuration
workflow is manual Helm values, using
[the umbrella overlay](../charts/guardian-platform/examples/values-openbao.yaml)
and the [Auth examples](../charts/auth-service/README.md#openbao-transit).
Generate any base cloud/identity configuration first, then maintain and layer the
OpenBao overlay yourself, selecting the provider both globally and in Auth.
`govctl` does not currently offer or generate OpenBao; its three-provider prompt
is intentional until the complete generator workflow is implemented.

A future generator feature must add the provider model and prompt together with
typed endpoint, algorithm, CA and auth inputs, values output,
and round-trip/render tests. Kubernetes auth must emit no token Secret;
`token_file` must reference an operator-managed Secret name and custom token key
without collecting token contents. Existing cloud output must remain unchanged.

## Artifact source

`govctl init` defaults to Cloudsmith for customer installs. Use this profile only
with a stable chart version whose `cloudsmith-delivery.json` confirms delivery.
Generated Cloudsmith values inherit that chart’s released image tags and digests;
they do not override images to `latest`, and the pull policy comes from
`global.imagePullPolicy`. GitHub output sets each image to
`tag: latest` with `pullPolicy: Always`. Use
`--artifact-source github` for internal GHCR installations or versions not yet delivered to Cloudsmith. Cloudsmith output
sets the EQTY Lab image prefix, pull-secret registry, and entitlement username
(`eqtylab/prod`) together. Fill the token placeholder through your existing
secret-management process. Custom registry hosts prompt for the full image
repository prefix as well. See [Cloudsmith installation](../docs/cloudsmith.md).
