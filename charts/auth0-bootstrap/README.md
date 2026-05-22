# Auth0 Bootstrap

A Helm chart for deploying the EQTY Lab Auth0 Bootstrap on Kubernetes.

## Description

The Auth0 Bootstrap provides automated application, API, permission, and user configuration for the Governance Platform using Auth0. It runs as a Kubernetes Job that configures Auth0 via the [Auth0 Management API](https://auth0.com/docs/api/management/v2).

Key capabilities:

- **Application Registration**: Creates a frontend (SPA), backend (M2M), and worker (M2M) application
- **Resource Server (API)**: Creates the Governance Platform API with a configurable identifier, token lifetime, and offline-access policy
- **Permissions / Scopes**: Defines fine-grained custom scopes on the Governance Platform API
- **Client Grants**: Grants the backend and worker M2M clients the appropriate scopes on the Governance Platform API
- **Management API Grant**: Grants the backend M2M client a limited set of Auth0 Management API scopes for user management
- **Initial Users**: Optionally creates a platform admin user and additional test users in a database connection
- **Auth0 Actions**: Creates, deploys, and binds the post-login and client-credentials-exchange Actions that enrich tokens with organization, role, project, and service-account claims
- **Idempotent**: All operations use check-then-create / check-then-update patterns and can be safely re-run

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- An Auth0 tenant
- A Machine-to-Machine (M2M) application in the Auth0 Dashboard authorized for the **Auth0 Management API** with at least the following scopes:
  - `read:clients`, `create:clients`, `update:clients`
  - `read:resource_servers`, `create:resource_servers`, `update:resource_servers`
  - `read:client_grants`, `create:client_grants`, `update:client_grants`
  - `read:users`, `create:users`, `update:users`
  - `read:actions`, `create:actions`, `update:actions`, `delete:actions` (required when Actions are enabled)

## Deployment

### Quick Start

Minimum configuration required:

```yaml
auth0:
  domain: "your-tenant.us.auth0.com"
  api:
    identifier: "https://governance.example.com"

applications:
  frontend:
    callbacks:
      - "https://governance.example.com/callback"
      - "http://localhost:5173/callback"
    logoutUrls:
      - "https://governance.example.com"
      - "http://localhost:5173"
    webOrigins:
      - "https://governance.example.com"
      - "http://localhost:5173"

users:
  admin:
    enabled: true
    email: "admin@example.com"
```

```bash
helm upgrade --install auth0-bootstrap ./auth0-bootstrap \
  -f values.yaml \
  --namespace governance \
  --create-namespace
```

### Creating the Bootstrap M2M Application

Before installing, create a Machine-to-Machine application in the Auth0 Dashboard for the bootstrap job. This is a **dedicated secret** (`auth0-management`) separate from `platform-auth0`, which is created by the `governance-platform` chart and stores the application credentials used by the platform services at runtime.

1. In the Auth0 Dashboard, go to **Applications → Applications → Create Application**.
2. Pick **Machine to Machine Applications** and name it something like `Governance Bootstrap M2M`.
3. Authorize it for the **Auth0 Management API** and grant the scopes listed under [Prerequisites](#prerequisites).
4. Copy the **Client ID** and **Client Secret** from the application's _Settings_ tab.
5. Create the Kubernetes secrets in the target namespace:

```bash
# Management API M2M credentials used by the bootstrap job.
# Add auth-service-api-secret when actions.postLogin.enabled is true (default) —
# it's the bearer token presented by the post-login action when calling the
# auth-service claims-enrichment endpoint.
kubectl create secret generic auth0-management \
  --from-literal=client-id=YOUR_MGMT_CLIENT_ID \
  --from-literal=client-secret=YOUR_MGMT_CLIENT_SECRET \
  --from-literal=auth-service-api-secret="$(openssl rand -base64 32)" \
  --namespace governance

# Initial platform admin password (only required when users.admin.enabled is true)
kubectl create secret generic platform-admin \
  --from-literal=password="$(openssl rand -base64 16)" \
  --namespace governance
```

| Scope                                                                         | Purpose                                        |
| ----------------------------------------------------------------------------- | ---------------------------------------------- |
| `read:clients`, `create:clients`, `update:clients`                            | Create and update SPA / M2M applications       |
| `read:resource_servers`, `create:resource_servers`, `update:resource_servers` | Create and update the Governance Platform API  |
| `read:client_grants`, `create:client_grants`, `update:client_grants`          | Grant M2M clients access to APIs               |
| `read:users`, `create:users`, `update:users`                                  | Create the platform admin user and test users  |
| `read:actions`, `create:actions`, `update:actions`, `delete:actions`          | Create, update, deploy, and bind Auth0 Actions |

> **Note:** After the bootstrap job completes, populate the `platform-auth0` secret with the created application client IDs and secrets from the job logs.

### Uninstalling

```bash
helm uninstall auth0-bootstrap --namespace governance
```

This removes all Kubernetes components associated with the chart and deletes the release.

> **Warning**: This will not remove the created Auth0 applications, API, or users. To fully reset, manually delete them from the Auth0 Dashboard.

## Values

### Global Parameters

| Key                     | Type   | Default | Description                               |
| ----------------------- | ------ | ------- | ----------------------------------------- |
| nameOverride            | string | `""`    | Override the chart name                   |
| fullnameOverride        | string | `""`    | Override the full name of the release     |
| global.imagePullSecrets | list   | `[]`    | Image pull secrets for private registries |

### Bootstrap Job Configuration

| Key                               | Type   | Default                     | Description                              |
| --------------------------------- | ------ | --------------------------- | ---------------------------------------- |
| bootstrap.enabled                 | bool   | `true`                      | Enable the bootstrap job                 |
| bootstrap.image.repository        | string | `"dwdraju/alpine-curl-jq"`  | Container image (must include curl + jq) |
| bootstrap.image.pullPolicy        | string | `"IfNotPresent"`            | Image pull policy                        |
| bootstrap.image.tag               | string | `"latest"`                  | Image tag                                |
| bootstrap.args                    | list   | `["/scripts/bootstrap.sh"]` | Args passed to `/bin/sh`                 |
| bootstrap.backoffLimit            | int    | `3`                         | Job backoff limit                        |
| bootstrap.activeDeadlineSeconds   | int    | `600`                       | Job active deadline in seconds           |
| bootstrap.ttlSecondsAfterFinished | int    | `300`                       | TTL for completed jobs                   |

### Bootstrap Resources

| Key                                 | Type   | Default   | Description    |
| ----------------------------------- | ------ | --------- | -------------- |
| bootstrap.resources.limits.cpu      | string | `"500m"`  | CPU limit      |
| bootstrap.resources.limits.memory   | string | `"256Mi"` | Memory limit   |
| bootstrap.resources.requests.cpu    | string | `"100m"`  | CPU request    |
| bootstrap.resources.requests.memory | string | `"128Mi"` | Memory request |

### Bootstrap Security

| Key                                    | Type | Default | Description              |
| -------------------------------------- | ---- | ------- | ------------------------ |
| bootstrap.securityContext.runAsNonRoot | bool | `true`  | Run as non-root user     |
| bootstrap.securityContext.runAsUser    | int  | `1000`  | User ID to run container |
| bootstrap.securityContext.fsGroup      | int  | `1000`  | Filesystem group         |

### Auth0 Tenant & Management API

| Key                                            | Type   | Default                     | Description                                                                                         |
| ---------------------------------------------- | ------ | --------------------------- | --------------------------------------------------------------------------------------------------- |
| auth0.domain                                   | string | `""`                        | **Required.** Auth0 tenant domain (e.g., `tenant.us.auth0.com`)                                     |
| auth0.managementSecret.name                    | string | `"auth0-management"`        | Secret containing bootstrap M2M credentials (and the auth-service api secret when actions are used) |
| auth0.managementSecret.clientIdKey             | string | `"client-id"`               | Key in secret for the M2M client ID                                                                 |
| auth0.managementSecret.clientSecretKey         | string | `"client-secret"`           | Key in secret for the M2M client secret                                                             |
| auth0.managementSecret.authServiceApiSecretKey | string | `"auth-service-api-secret"` | Key in secret for the bearer token forwarded to the post-login action (optional)                    |

### Governance Platform API (Resource Server)

| Key                          | Type   | Default                     | Description                                               |
| ---------------------------- | ------ | --------------------------- | --------------------------------------------------------- |
| auth0.api.name               | string | `"Governance Platform API"` | Display name for the API in Auth0                         |
| auth0.api.identifier         | string | `""`                        | **Required.** API identifier / audience (URL recommended) |
| auth0.api.tokenLifetime      | int    | `86400`                     | Access token lifetime in seconds                          |
| auth0.api.allowOfflineAccess | bool   | `false`                     | Whether to issue refresh tokens                           |

### Frontend Application (SPA)

| Key                              | Type   | Default                          | Description                  |
| -------------------------------- | ------ | -------------------------------- | ---------------------------- |
| applications.frontend.name       | string | `"Governance Platform Frontend"` | Application display name     |
| applications.frontend.callbacks  | list   | See values.yaml                  | Allowed callback URLs        |
| applications.frontend.logoutUrls | list   | See values.yaml                  | Allowed logout redirect URLs |
| applications.frontend.webOrigins | list   | See values.yaml                  | Allowed web origins (CORS)   |

The frontend application is configured as a **Single Page Application (SPA)** with:

- `token_endpoint_auth_method: none` (PKCE auth code flow, no client secret)
- `oidc_conformant: true`
- Grant types: `authorization_code`, `implicit`, `refresh_token`

### Backend Application (M2M)

| Key                                      | Type   | Default                         | Description                                            |
| ---------------------------------------- | ------ | ------------------------------- | ------------------------------------------------------ |
| applications.backend.name                | string | `"Governance Platform Backend"` | Application display name                               |
| applications.backend.apiScopes           | list   | See values.yaml                 | Scopes granted on the Governance Platform API          |
| applications.backend.managementApiScopes | list   | See values.yaml                 | Scopes granted on the Auth0 Management API (user mgmt) |

The backend application is configured as a **Machine-to-Machine (non-interactive) client** with:

- `token_endpoint_auth_method: client_secret_post`
- `oidc_conformant: true`
- Grant types: `client_credentials`
- Client secret auto-generated by Auth0 (printed once in the job logs)

### Worker Application (M2M)

| Key                           | Type   | Default               | Description                                   |
| ----------------------------- | ------ | --------------------- | --------------------------------------------- |
| applications.worker.name      | string | `"Governance Worker"` | Application display name                      |
| applications.worker.apiScopes | list   | See values.yaml       | Scopes granted on the Governance Platform API |

The worker application is configured as a **Machine-to-Machine (non-interactive) client** with:

- `token_endpoint_auth_method: client_secret_post`
- `oidc_conformant: true`
- Grant types: `client_credentials`

### Custom Scopes / Permissions

| Key    | Type | Default         | Description                                                        |
| ------ | ---- | --------------- | ------------------------------------------------------------------ |
| scopes | list | See values.yaml | Custom scopes (permissions) created on the Governance Platform API |

Each scope is an object with `name` and `description`.

### Auth0 Actions

The chart deploys two Auth0 Actions during bootstrap, configured under `actions`:

| Key                                               | Type   | Default                                      | Description                                                                                     |
| ------------------------------------------------- | ------ | -------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| actions.enabled                                   | bool   | `true`                                       | Master switch for creating / deploying / binding actions                                        |
| actions.sourceConfigMap.name                      | string | `"auth0-actions-source"`                     | ConfigMap holding the action JS (created by `bootstrap-auth0.sh` from `scripts/auth0/actions/`) |
| actions.postLogin.enabled                         | bool   | `true`                                       | Enable the post-login token-enrichment action                                                   |
| actions.postLogin.name                            | string | `"Post Login Users & Service Accounts"`      | Action display name in the Auth0 Dashboard                                                      |
| actions.postLogin.codeFile                        | string | `"post-login-users-and-service-accounts.js"` | File inside the action source ConfigMap                                                         |
| actions.postLogin.trigger.id                      | string | `"post-login"`                               | Auth0 trigger identifier                                                                        |
| actions.postLogin.trigger.version                 | string | `"v3"`                                       | Trigger version                                                                                 |
| actions.postLogin.runtime                         | string | `"node22"`                                   | Node runtime for the action                                                                     |
| actions.postLogin.dependencies                    | list   | `[]`                                         | npm dependencies (`{ name, version }`)                                                          |
| actions.postLogin.authService.urlDev              | string | `""`                                         | Dev auth-service URL — forwarded as `event.secrets.AUTH_SERVICE_URL_DEV`                        |
| actions.postLogin.authService.urlStaging          | string | `""`                                         | Staging URL — forwarded as `event.secrets.AUTH_SERVICE_URL_STAGING`                             |
| actions.postLogin.authService.urlProduction       | string | `""`                                         | Production URL — forwarded as `event.secrets.AUTH_SERVICE_URL_PRODUCTION`                       |
| actions.postLogin.authService.url                 | string | `""`                                         | Fallback URL — forwarded as `event.secrets.AUTH_SERVICE_URL`                                    |
| actions.clientCredentialsExchange.enabled         | bool   | `true`                                       | Enable the client-credentials-exchange service-account enrichment action                        |
| actions.clientCredentialsExchange.name            | string | `"Service Account Credentials"`              | Action display name in the Auth0 Dashboard                                                      |
| actions.clientCredentialsExchange.codeFile        | string | `"service-account-credentials.js"`           | File inside the action source ConfigMap                                                         |
| actions.clientCredentialsExchange.trigger.id      | string | `"credentials-exchange"`                     | Auth0 trigger identifier                                                                        |
| actions.clientCredentialsExchange.trigger.version | string | `"v2"`                                       | Trigger version                                                                                 |
| actions.clientCredentialsExchange.runtime         | string | `"node22"`                                   | Node runtime for the action                                                                     |
| actions.clientCredentialsExchange.dependencies    | list   | `[{ name: "auth0", version: "3.x" }]`        | npm dependencies — the action uses v3-style `management.getUser({...})`                         |

Empty URL fields under `actions.postLogin.authService` are omitted from the action's secrets at deploy time, so dev-only tenants can leave the staging/prod URLs blank.

#### Where action secrets come from

There is **no separate `auth0-actions` Kubernetes secret** — sensitive values live alongside the management M2M credentials in `auth0-management`, and non-sensitive configuration is supplied in `values.yaml`:

| Action secret (`event.secrets.X`) | Used by                     | Source                                                              |
| --------------------------------- | --------------------------- | ------------------------------------------------------------------- |
| `AUTH_SERVICE_URL_DEV`            | post-login                  | `actions.postLogin.authService.urlDev` (Helm value)                 |
| `AUTH_SERVICE_URL_STAGING`        | post-login                  | `actions.postLogin.authService.urlStaging` (Helm value)             |
| `AUTH_SERVICE_URL_PRODUCTION`     | post-login                  | `actions.postLogin.authService.urlProduction` (Helm value)          |
| `AUTH_SERVICE_URL`                | post-login                  | `actions.postLogin.authService.url` (Helm value)                    |
| `AUTH_SERVICE_API_SECRET`         | post-login                  | `auth0-management` secret, key `auth-service-api-secret` (optional) |
| `domain`                          | client-credentials-exchange | `auth0.domain` (Helm value)                                         |
| `clientId`                        | client-credentials-exchange | `auth0-management` secret, key `client-id`                          |
| `clientSecret`                    | client-credentials-exchange | `auth0-management` secret, key `client-secret`                      |

#### Action source files

The action JavaScript itself lives in [`scripts/auth0/actions/`](../../scripts/auth0/actions/). The `bootstrap-auth0.sh` helper creates (or replaces) the `auth0-actions-source` ConfigMap from this directory before running `helm install`, so edits to the `.js` files take effect on the next bootstrap run. If you deploy the chart by hand (without the helper), create the ConfigMap manually:

```bash
kubectl create configmap auth0-actions-source \
  --from-file=scripts/auth0/actions/ \
  --namespace governance
```

Pass `--skip-actions` to `bootstrap-auth0.sh` to skip both the ConfigMap creation and the action deployment steps (the flag also sets `actions.enabled=false` for the Helm install).

### Users — Platform Admin

| Key                    | Type   | Default                              | Description                                  |
| ---------------------- | ------ | ------------------------------------ | -------------------------------------------- |
| users.admin.enabled    | bool   | `true`                               | Whether to create the platform admin user    |
| users.admin.email      | string | `"admin@governance.local"`           | Admin email                                  |
| users.admin.firstName  | string | `"Platform"`                         | Admin given name                             |
| users.admin.lastName   | string | `"Admin"`                            | Admin family name                            |
| users.admin.connection | string | `"Username-Password-Authentication"` | Auth0 database connection name               |
| users.admin.secretName | string | `"platform-admin"`                   | Secret containing the admin password         |
| users.admin.secretKey  | string | `"password"`                         | Key within the secret for the admin password |

### Users — Test Users (development only)

| Key                     | Type | Default | Description                                                          |
| ----------------------- | ---- | ------- | -------------------------------------------------------------------- |
| users.testUsers.enabled | bool | `false` | Enable creation of test users                                        |
| users.testUsers.users   | list | `[]`    | List of `{ email, firstName, lastName, password }` test user objects |

> **Warning:** Test user passwords are inlined in plain text in values and rendered into the bootstrap script. Use only in development.

## Bootstrap Execution Order

The bootstrap script executes in a specific order due to dependencies:

1. **Authenticate** against the Auth0 Management API using the M2M credentials
2. **Create the Governance Platform API** (resource server) with the configured custom scopes
3. **Create the frontend SPA application** with callbacks, logout URLs, and CORS origins
4. **Create the backend M2M application** (client secret printed once in logs)
5. **Create the worker M2M application** (client secret printed once in logs)
6. **Grant the backend M2M client** the configured `apiScopes` on the Governance Platform API
7. **Grant the backend M2M client** the configured `managementApiScopes` on the Auth0 Management API
8. **Grant the worker M2M client** the configured `apiScopes` on the Governance Platform API
9. **Create the platform admin user** (if `users.admin.enabled` is `true`)
10. **Create test users** (if `users.testUsers.enabled` is `true`)
11. **Create / update / deploy the post-login Action** and bind it to the `post-login` trigger (if `actions.postLogin.enabled` is `true`)
12. **Create / update / deploy the client-credentials-exchange Action** and bind it to the `credentials-exchange` trigger (if `actions.clientCredentialsExchange.enabled` is `true`)

## Integration with Applications

After successful bootstrap, populate the `platform-auth0` secret with the created application credentials and update each service's chart values. The `governance-platform` chart consumes these:

**auth-service:**

```yaml
config:
  idp:
    provider: "auth0"
    issuer: "https://your-tenant.us.auth0.com/"
    auth0:
      domain: "your-tenant.us.auth0.com"
      managementAudience: "https://your-tenant.us.auth0.com/api/v2/"
      apiIdentifier: "https://governance.your-domain.com"

secrets:
  auth:
    auth0:
      name: "platform-auth0"
```

**governance-studio:**

```yaml
config:
  auth0Domain: "your-tenant.us.auth0.com"
  auth0ClientId: "your-spa-client-id"
  auth0Audience: "https://your-tenant.us.auth0.com/api/v2/"
```

The `platform-auth0` secret should contain these keys after bootstrap:

| Key                  | Description                                                |
| -------------------- | ---------------------------------------------------------- |
| `client-id`          | Backend M2M client ID (used by auth-service)               |
| `client-secret`      | Backend M2M client secret                                  |
| `mgmt-client-id`     | Backend M2M client ID for Management API calls (user mgmt) |
| `mgmt-client-secret` | Backend M2M client secret for Management API calls         |

> **Note:** The frontend SPA client ID and tenant domain are configured as chart values (not stored in secrets). See each service's chart documentation for details.

## Troubleshooting

### Viewing Job Status

```bash
kubectl get jobs -n governance -l app.kubernetes.io/name=auth0-bootstrap
```

### Viewing Logs

```bash
kubectl logs -n governance -l app.kubernetes.io/name=auth0-bootstrap
```

### Checking Pod Status

```bash
kubectl get pods -n governance -l app.kubernetes.io/name=auth0-bootstrap
kubectl describe pod <pod-name> -n governance
```

### Verifying Configuration

View the bootstrap job configuration:

```bash
kubectl get job -n governance -l app.kubernetes.io/name=auth0-bootstrap -o yaml
```

Verify Auth0 resources were created by checking the job logs:

```bash
kubectl logs -n governance -l app.kubernetes.io/name=auth0-bootstrap
```

### Common Issues

**Job fails with `Failed to get Management API token`**

- Verify M2M credentials in the `auth0-management` secret
- Confirm the M2M application is authorized for the Auth0 Management API and has the scopes listed under [Prerequisites](#prerequisites)
- Ensure `auth0.domain` matches your Auth0 tenant exactly (no `https://`, no trailing slash)

**Application already exists**

- The job is idempotent and will skip existing applications by name
- Delete the application manually in the Auth0 Dashboard if you need a fresh start
- Note: existing applications keep their original client secret — no new secret will be printed

**Client secret not shown in logs**

- Client secrets are only shown once during creation
- If the application already existed, no new secret is created
- Rotate the secret manually in the Auth0 Dashboard under _Applications → [app] → Settings → Rotate_

**Failed to create API / `HTTP 422`**

- An API with the same identifier may already exist with conflicting settings
- Confirm `auth0.api.identifier` is unique in your tenant
- The job will update scopes on an existing API but will not change the signing algorithm, token lifetime, or offline-access policy

**Failed to create user / `HTTP 400` (password strength)**

- Auth0 password policies apply to the admin and test user passwords
- Ensure the `platform-admin` secret password meets your tenant's policy
- Configure password policy under _Auth0 Dashboard → Authentication → Database → [Connection] → Password Policy_

**Timeout or deadline exceeded**

- Increase `bootstrap.activeDeadlineSeconds`
- Check network connectivity from the cluster to `https://<your-tenant>.auth0.com`

**Wrong connection name**

- The default `users.admin.connection` is `Username-Password-Authentication` — the standard Auth0 database connection
- If you've renamed or deleted it, set `users.admin.connection` to the actual connection name in your tenant

**Action create / deploy fails with `HTTP 403 insufficient_scope`**

- Add `read:actions`, `create:actions`, `update:actions`, and `delete:actions` to the bootstrap M2M application's Management API authorization
- Re-run the bootstrap job; it will resume from where it left off

**Action source ConfigMap not found**

- The chart mounts `auth0-actions-source` by default. `bootstrap-auth0.sh` creates it from `scripts/auth0/actions/` on every run
- When deploying the chart by hand (no helper script), create the ConfigMap manually with `kubectl create configmap auth0-actions-source --from-file=scripts/auth0/actions/`
- Pass `--skip-actions` to bypass actions entirely, or set `actions.enabled=false` in values

**Post-login action runs but `event.secrets.AUTH_SERVICE_API_SECRET` is undefined**

- The `auth-service-api-secret` key was missing from the `auth0-management` secret when the bootstrap job ran
- The bootstrap helper prints a yellow warning when this key is absent — add it and re-run:
  `kubectl patch secret auth0-management -n <ns> -p '{"stringData":{"auth-service-api-secret":"<shared-bearer-token>"}}'`
- Other `AUTH_SERVICE_URL_*` secrets come from Helm values (`actions.postLogin.authService.*`); empty fields are intentionally omitted
- Note: Auth0 action secrets are only written at create/update time; rotating the api secret requires re-running the bootstrap job

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://docs.eqtylab.io
- GitHub: https://github.com/eqtylab/governance-studio-infrastructure
