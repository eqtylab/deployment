# Scripts

Helper scripts for infrastructure setup, identity provider bootstrap, post-install database seeding, optional OpenBao operator setup, and release packaging checks.

## Infrastructure

| Script                           | Description                                      | Usage                      |
| -------------------------------- | ------------------------------------------------ | -------------------------- |
| [nginx.sh](nginx.sh)             | Installs the NGINX Ingress Controller via Helm   | `./scripts/nginx.sh`       |
| [cert-issuer.sh](cert-issuer.sh) | Installs cert-manager via Helm for automatic TLS | `./scripts/cert-issuer.sh` |

Both scripts accept `-n <namespace>` to override the default namespace (`ingress-nginx`).

## Identity Provider Bootstrap

| Script                                                           | Description                                                          | Usage                                                                      |
| ---------------------------------------------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| [auth0/bootstrap-auth0.sh](auth0/bootstrap-auth0.sh)             | Runs the `auth0-bootstrap` Helm chart and monitors job completion    | `./scripts/auth0/bootstrap-auth0.sh -f bootstrap-values.yaml -n gov`       |
| [entra/bootstrap-entra.sh](entra/bootstrap-entra.sh)             | Runs the `entra-bootstrap` Helm chart and monitors job completion    | `./scripts/entra/bootstrap-entra.sh -f bootstrap-values.yaml -n gov`       |
| [keycloak/bootstrap-keycloak.sh](keycloak/bootstrap-keycloak.sh) | Runs the `keycloak-bootstrap` Helm chart and monitors job completion | `./scripts/keycloak/bootstrap-keycloak.sh -f bootstrap-values.yaml -n gov` |

These scripts validate prerequisites (required secrets exist), deploy the bootstrap Helm chart, monitor the job to completion, and display next steps.

## Post-Install Setup

| Script                                                                             | Description                                                           | Usage                                                                                             |
| ---------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| [auth0/post-install-auth0-setup.sh](auth0/post-install-auth0-setup.sh)             | Creates organization and platform-admin user via Auth0 Management API | `./scripts/auth0/post-install-auth0-setup.sh -n gov -e admin@example.com -d example.us.auth0.com` |
| [entra/post-install-entra-setup.sh](entra/post-install-entra-setup.sh)             | Creates organization and platform-admin user via Microsoft Graph API  | `./scripts/entra/post-install-entra-setup.sh -n gov -e admin@contoso.com`                         |
| [keycloak/post-install-keycloak-setup.sh](keycloak/post-install-keycloak-setup.sh) | Creates organization and platform-admin user via Keycloak Admin API   | `./scripts/keycloak/post-install-keycloak-setup.sh -n gov -e admin@example.com`                   |

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

## OpenBao Operator Setup

The `openbao/` directory is synced from `eqtylab/guardian-infrastructure`; edit it there, not here. It configures a development-only OpenBao for Auth signing and is shipped in the connected customer package (see [`docs/openbao-delivery.md`](../docs/openbao-delivery.md)).

| Script                                                         | Description                                                                          | Usage                                                        |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------------ |
| [openbao/configure-auth.sh](openbao/configure-auth.sh)         | Enables the Transit mount, scoped policy, Kubernetes auth method and role for Auth   | `./scripts/openbao/configure-auth.sh --help`                 |
| [openbao/kind-custody-smoke.sh](openbao/kind-custody-smoke.sh) | Installs the custody chart on a disposable kind cluster and checks Raft/unseal       | `./scripts/openbao/kind-custody-smoke.sh`                    |
| [openbao/test-custody-chart.py](openbao/test-custody-chart.py) | Cluster-free custody render, NOTES and package checks (build dependencies first)     | `python3 -B scripts/openbao/test-custody-chart.py`           |

The script reads `openbao/policies/guardian-auth.hcl` and `helpers/output.sh` relative to itself; keep that layout when copying it.

## Release Tooling

| Script                                                                       | Description                                                                                       | Usage                                                                                                         |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| [release/custody_distribution.py](release/custody_distribution.py)           | Validates optional custody selection in release manifests and verifies the packaged custody files | `python3 -B scripts/release/custody_distribution.py validate-manifests releases/v*/release-manifest.yaml`   |

Owned in this repository (not synced). The release workflow runs it before publication; `python3 -B -m unittest discover -s scripts/release -p 'test_*.py' -v` runs its regressions.
