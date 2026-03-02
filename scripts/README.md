# Scripts

Helper scripts for infrastructure setup, identity provider bootstrap, and post-install database seeding.

## Infrastructure

| Script                           | Description                                      | Usage                      |
| -------------------------------- | ------------------------------------------------ | -------------------------- |
| [nginx.sh](nginx.sh)             | Installs the NGINX Ingress Controller via Helm   | `./scripts/nginx.sh`       |
| [cert-issuer.sh](cert-issuer.sh) | Installs cert-manager via Helm for automatic TLS | `./scripts/cert-issuer.sh` |

Both scripts accept `-n <namespace>` to override the default namespace (`ingress-nginx`).

## Identity Provider Bootstrap

| Script                                                           | Description                                                          | Usage                                                                      |
| ---------------------------------------------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| [entra/bootstrap-entra.sh](entra/bootstrap-entra.sh)             | Runs the `entra-bootstrap` Helm chart and monitors job completion    | `./scripts/entra/bootstrap-entra.sh -f bootstrap-values.yaml -n gov`       |
| [keycloak/bootstrap-keycloak.sh](keycloak/bootstrap-keycloak.sh) | Runs the `keycloak-bootstrap` Helm chart and monitors job completion | `./scripts/keycloak/bootstrap-keycloak.sh -f bootstrap-values.yaml -n gov` |

These scripts validate prerequisites (required secrets exist), deploy the bootstrap Helm chart, monitor the job to completion, and display next steps.

## Post-Install Setup

| Script                                                                             | Description                                                          | Usage                                                                           |
| ---------------------------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| [entra/post-install-entra-setup.sh](entra/post-install-entra-setup.sh)             | Creates organization and platform-admin user via Microsoft Graph API | `./scripts/entra/post-install-entra-setup.sh -n gov -e admin@contoso.com`       |
| [keycloak/post-install-keycloak-setup.sh](keycloak/post-install-keycloak-setup.sh) | Creates organization and platform-admin user via Keycloak Admin API  | `./scripts/keycloak/post-install-keycloak-setup.sh -n gov -e admin@example.com` |

These scripts are an alternative to the Helm post-install hooks. They wait for the platform to be running, verify database migrations are complete, seed the organization and admin user, and verify the integration.

## Helpers

The `helpers/` directory contains shared shell functions used by all scripts:

| File                                   | Purpose                              |
| -------------------------------------- | ------------------------------------ |
| [helpers/assert.sh](helpers/assert.sh) | Prerequisite and argument validation |
| [helpers/output.sh](helpers/output.sh) | Colored output formatting            |
| [helpers/log.sh](helpers/log.sh)       | Logging utilities                    |
| [helpers/string.sh](helpers/string.sh) | String manipulation                  |
| [helpers/array.sh](helpers/array.sh)   | Array utilities                      |
| [helpers/os.sh](helpers/os.sh)         | OS detection                         |
