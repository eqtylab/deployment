# Microsoft Entra ID Bootstrap

A Helm chart for deploying the EQTY Lab Entra ID Bootstrap on Kubernetes.

## Description

The Entra ID Bootstrap provides automated app registration and OAuth configuration for the Governance Platform using Microsoft Entra ID. It runs as a Kubernetes Job that configures Entra ID via the Azure CLI and Microsoft Graph API.

Key capabilities:

- **App Registration**: Creates frontend (SPA), backend (confidential), and worker (confidential) app registrations
- **Token Configuration**: Sets `accessTokenAcceptedVersion` to 2 on all apps for v2.0 token validation
- **API Scope**: Creates `access_as_user` OAuth2 delegated scope on the backend app
- **Graph Permissions**: Configures Microsoft Graph API permissions (User.Read, profile, openid, User.Read.All)
- **Frontend-Backend Linking**: Adds frontend → backend API permission for the `access_as_user` scope
- **Admin Consent**: Grants admin consent for Graph API permissions
- **Idempotent**: All operations use check-then-create pattern and can be safely re-run

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- A Microsoft Entra ID tenant
- A service principal with the following Microsoft Graph API permissions (Application type):
  - `Application.ReadWrite.All` — create and update app registrations
  - `DelegatedPermissionGrant.ReadWrite.All` — grant admin consent for delegated permissions

## Deployment

### Quick Start

Minimum configuration required:

```yaml
entra:
  tenantId: "YOUR_ENTRA_TENANT_ID"
  domain: "governance.example.com"

apps:
  frontend:
    redirectUris:
      - "https://governance.example.com"
      - "http://localhost:5173"
  backend:
    displayName: "Governance Platform Backend"
  worker:
    displayName: "Governance Worker"
```

```bash
helm upgrade --install entra-bootstrap ./entra-bootstrap \
  -f values.yaml \
  --namespace governance \
  --create-namespace
```

### Creating the Service Principal

Before installing, create a service principal for the bootstrap job. This is a **dedicated secret** (`entra-bootstrap-sp`) separate from `platform-entra`, which is created by the `governance-platform` chart and stores the app registration credentials for the platform services.

```bash
# 1. Create a new app registration for bootstrap and capture the appId
APP_ID=$(az ad app create --display-name "Governance Bootstrap SP" --query appId -o tsv)
echo "Created app registration: $APP_ID"

# 2. Create a service principal
az ad sp create --id $APP_ID

# 3. Grant required permissions (Application type)
#    - Application.ReadWrite.All: create/update app registrations
#    - DelegatedPermissionGrant.ReadWrite.All: grant admin consent
az ad app permission add \
  --id $APP_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9=Role

az ad app permission add \
  --id $APP_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 8e8e4742-1d2d-4f22-b4fa-e31d2a2e3798=Role

# 4. Grant admin consent for the service principal itself
az ad app permission admin-consent --id $APP_ID

# 5. Create a client secret (save the output password)
az ad app credential reset --id $APP_ID --display-name "bootstrap" --years 2

# 6. Create the Kubernetes secret with the SP credentials
kubectl create secret generic entra-bootstrap-sp \
  --from-literal=client-id=$APP_ID \
  --from-literal=client-secret=<password from step 5> \
  --namespace governance
```

| Permission                               | ID                                     | Type        | Purpose                                       |
| ---------------------------------------- | -------------------------------------- | ----------- | --------------------------------------------- |
| `Application.ReadWrite.All`              | `1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9` | Application | Create and configure app registrations        |
| `DelegatedPermissionGrant.ReadWrite.All` | `8e8e4742-1d2d-4f22-b4fa-e31d2a2e3798` | Application | Grant admin consent for delegated permissions |

> **Note:** After the bootstrap job completes, populate the `platform-entra` secret with the created app registration client IDs and secrets from the job logs.

### Uninstalling

```bash
helm uninstall entra-bootstrap --namespace governance
```

This removes all Kubernetes components associated with the chart and deletes the release.

> **Warning**: This will not remove the created Entra ID app registrations. To fully reset, manually delete the app registrations in the Azure portal.

## Values

### Global Parameters

| Key                     | Type   | Default | Description                               |
| ----------------------- | ------ | ------- | ----------------------------------------- |
| nameOverride            | string | `""`    | Override the chart name                   |
| fullnameOverride        | string | `""`    | Override the full name of the release     |
| global.imagePullSecrets | list   | `[]`    | Image pull secrets for private registries |

### Bootstrap Job Configuration

| Key                               | Type   | Default                         | Description                    |
| --------------------------------- | ------ | ------------------------------- | ------------------------------ |
| bootstrap.enabled                 | bool   | `true`                          | Enable the bootstrap job       |
| bootstrap.image.repository        | string | `"mcr.microsoft.com/azure-cli"` | Container image repository     |
| bootstrap.image.pullPolicy        | string | `"IfNotPresent"`                | Image pull policy              |
| bootstrap.image.tag               | string | `"latest"`                      | Image tag                      |
| bootstrap.backoffLimit            | int    | `3`                             | Job backoff limit              |
| bootstrap.activeDeadlineSeconds   | int    | `600`                           | Job active deadline in seconds |
| bootstrap.ttlSecondsAfterFinished | int    | `300`                           | TTL for completed jobs         |

### Bootstrap Resources

| Key                                 | Type   | Default   | Description    |
| ----------------------------------- | ------ | --------- | -------------- |
| bootstrap.resources.limits.cpu      | string | `"500m"`  | CPU limit      |
| bootstrap.resources.limits.memory   | string | `"512Mi"` | Memory limit   |
| bootstrap.resources.requests.cpu    | string | `"100m"`  | CPU request    |
| bootstrap.resources.requests.memory | string | `"256Mi"` | Memory request |

### Bootstrap Security

| Key                                    | Type | Default | Description              |
| -------------------------------------- | ---- | ------- | ------------------------ |
| bootstrap.securityContext.runAsNonRoot | bool | `true`  | Run as non-root user     |
| bootstrap.securityContext.runAsUser    | int  | `1000`  | User ID to run container |
| bootstrap.securityContext.fsGroup      | int  | `1000`  | Filesystem group         |

### Entra ID Configuration

| Key                                          | Type   | Default                | Description                                            |
| -------------------------------------------- | ------ | ---------------------- | ------------------------------------------------------ |
| entra.tenantId                               | string | `""`                   | **Required.** Microsoft Entra tenant ID (directory ID) |
| entra.domain                                 | string | `""`                   | **Required.** Domain for redirect URIs                 |
| entra.servicePrincipalSecret.name            | string | `"entra-bootstrap-sp"` | Secret containing bootstrap SP credentials             |
| entra.servicePrincipalSecret.clientIdKey     | string | `"client-id"`          | Key in secret for the SP client ID                     |
| entra.servicePrincipalSecret.clientSecretKey | string | `"client-secret"`      | Key in secret for the SP client secret                 |

### Frontend App Configuration

| Key                        | Type   | Default                          | Description                   |
| -------------------------- | ------ | -------------------------------- | ----------------------------- |
| apps.frontend.displayName  | string | `"Governance Platform Frontend"` | App registration display name |
| apps.frontend.redirectUris | list   | See values.yaml                  | SPA redirect URIs             |

The frontend app is configured as a **Single-page application (SPA)** with:

- PKCE auth code flow (no client secret)
- ID token issuance enabled
- `accessTokenAcceptedVersion: 2`
- Graph API delegated permissions: `User.Read`, `profile`, `openid`, `offline_access`
- Backend API delegated permission: `access_as_user`

### Backend App Configuration

| Key                      | Type   | Default                         | Description                   |
| ------------------------ | ------ | ------------------------------- | ----------------------------- |
| apps.backend.displayName | string | `"Governance Platform Backend"` | App registration display name |

The backend app is configured as a **confidential client** with:

- Client secret (auto-generated, shown in job logs)
- `accessTokenAcceptedVersion: 2`
- Application ID URI: `api://<appId>`
- `access_as_user` delegated OAuth2 scope
- Graph API permissions: `User.Read` (delegated), `profile` (delegated), `openid` (delegated), `User.Read.All` (application)
- Admin consent granted for Graph API permissions

### Worker App Configuration

| Key                     | Type   | Default               | Description                   |
| ----------------------- | ------ | --------------------- | ----------------------------- |
| apps.worker.displayName | string | `"Governance Worker"` | App registration display name |

The worker app is configured as a **confidential client** with:

- Client secret (auto-generated, shown in job logs)
- No additional API permissions or scopes

## Bootstrap Execution Order

The bootstrap script executes in a specific order due to dependencies:

1. **Create backend app** (confidential client)
2. **Set token version v2** on backend
3. **Set Application ID URI** (`api://<appId>`) on backend — required for custom scopes
4. **Create `access_as_user` scope** on backend — exports scope ID for frontend
5. **Add Graph API permissions** to backend
6. **Grant admin consent** for backend
7. **Create frontend app** (SPA) — references backend's `access_as_user` scope
8. **Set token version v2** on frontend
9. **Create worker app** (confidential client)

## Integration with Applications

After successful bootstrap, update the `platform-entra` secret with the created app registration credentials. The following shows how each service consumes Entra configuration:

**auth-service:**

```yaml
config:
  idp:
    provider: "entra"
    issuer: "https://login.microsoftonline.com/your-tenant-id/v2.0"
    entra:
      tenantId: "your-tenant-id"
      defaultRoles: "user"

secrets:
  auth:
    entra:
      name: "platform-entra"
```

**governance-service:**

```yaml
config:
  authProvider: "entra"

secrets:
  auth:
    entra:
      name: "platform-entra"
```

**governance-studio:**

```yaml
config:
  authProvider: "entra"
  entraClientId: "your-frontend-app-id"
  entraTenantId: "your-tenant-id"
```

The `platform-entra` secret should contain these keys after bootstrap:

| Key                   | Description                                          |
| --------------------- | ---------------------------------------------------- |
| `client-id`           | Backend app client ID (OIDC client for auth-service) |
| `client-secret`       | Backend app client secret                            |
| `graph-client-id`     | Backend app client ID (for Graph API calls)          |
| `graph-client-secret` | Backend app client secret (for Graph API calls)      |

> **Note:** The frontend app ID and tenant ID are configured as chart values (not stored in secrets). See each service's chart documentation for details.

## Troubleshooting

### Viewing Job Status

```bash
kubectl get jobs -n governance -l app.kubernetes.io/name=entra-bootstrap
```

### Viewing Logs

```bash
kubectl logs -n governance -l app.kubernetes.io/name=entra-bootstrap
```

### Checking Pod Status

```bash
kubectl get pods -n governance -l app.kubernetes.io/name=entra-bootstrap
kubectl describe pod <pod-name> -n governance
```

### Verifying Configuration

View the bootstrap job configuration:

```bash
kubectl get job -n governance -l app.kubernetes.io/name=entra-bootstrap -o yaml
```

Verify Entra resources were created by checking the job logs:

```bash
kubectl logs -n governance -l app.kubernetes.io/name=entra-bootstrap
```

### Common Issues

**Job fails with authentication error**

- Verify service principal credentials in the `entra-bootstrap-sp` secret
- Check if the service principal has `Application.ReadWrite.All` and `DelegatedPermissionGrant.ReadWrite.All` permissions
- Ensure `entra.tenantId` is correct

**App registration already exists**

- The job is idempotent and will skip existing app registrations
- Delete the app registrations manually in Azure portal if you need a fresh start

**Admin consent fails**

- Admin consent may need to be granted manually in the Azure portal
- Navigate to: Azure Portal → Entra ID → App registrations → [app] → API permissions → Grant admin consent

**Timeout or deadline exceeded**

- Increase `bootstrap.activeDeadlineSeconds`
- Check network connectivity from the cluster to `login.microsoftonline.com` and `graph.microsoft.com`

**Client secret not shown in logs**

- Client secrets are only shown once during creation
- If the app already existed, no new secret is created
- Use `az ad app credential reset` to generate a new secret manually

**Token validation errors after bootstrap**

- Verify `accessTokenAcceptedVersion` is set to 2 on the backend app
- Check the issuer URL matches `https://login.microsoftonline.com/{tenant-id}/v2.0`
- Ensure the Application ID URI (`api://<appId>`) is set on the backend app

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://docs.eqtylab.io
- GitHub: https://github.com/eqtylab/governance-studio-infrastructure
