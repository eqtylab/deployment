# Keycloak Bootstrap

A Helm chart for deploying the EQTY Lab Keycloak Bootstrap on Kubernetes.

## Description

The Keycloak Bootstrap provides automated realm and client configuration for the Governance Platform. It runs as a Kubernetes Job that configures Keycloak with the necessary settings for the platform to function.

Key capabilities:

- **Realm Configuration**: Creates and configures the governance realm with security settings
- **Client Management**: Sets up frontend, backend, and worker OAuth clients
- **Scope Creation**: Creates custom OAuth scopes for fine-grained authorization
- **User Provisioning**: Creates initial platform admin user
- **Secret Generation**: Outputs configuration secrets for platform services

**Note**: Groups and projects are now managed entirely within the Governance Service, not in Keycloak. This simplified approach uses token exchange flows with Auth Service for claims enrichment.

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- A running Keycloak instance
- Admin credentials for Keycloak

## Installing the Chart

### Basic Installation

```bash
helm install keycloak-bootstrap ./keycloak-bootstrap \
  --set keycloak.url=http://keycloak:8080 \
  --set keycloak.adminPasswordSecret.name=keycloak-admin \
  --set clients.backend.secretName=keycloak-backend-secret \
  --set clients.worker.secretName=keycloak-worker-secret \
  --namespace governance \
  --create-namespace
```

### Installation with Custom Values

```bash
helm install keycloak-bootstrap ./keycloak-bootstrap \
  -f values.yaml \
  --namespace governance \
  --create-namespace
```

## Uninstalling the Chart

```bash
helm uninstall keycloak-bootstrap --namespace governance
```

This removes all Kubernetes components associated with the chart and deletes the release.

**Note**: This will not remove the created Keycloak resources (realm, clients, users). To fully reset, manually delete the realm in Keycloak.

## Required Secrets

Before installing, create the following secrets:

```bash
# Keycloak admin password
kubectl create secret generic keycloak-admin \
  --from-literal=password=YOUR_ADMIN_PASSWORD \
  --namespace governance

# Backend client secret
kubectl create secret generic keycloak-backend-client \
  --from-literal=client-secret=$(openssl rand -hex 32) \
  --namespace governance

# Worker client secret
kubectl create secret generic keycloak-worker-client \
  --from-literal=client-secret=$(openssl rand -hex 32) \
  --namespace governance

# Admin user password (if creating admin user)
kubectl create secret generic keycloak-admin-user \
  --from-literal=password=$(openssl rand -base64 16) \
  --namespace governance
```

## Values

### Global Parameters

| Key                     | Type   | Default | Description                               |
| ----------------------- | ------ | ------- | ----------------------------------------- |
| nameOverride            | string | `""`    | Override the chart name                   |
| fullnameOverride        | string | `""`    | Override the full name of the release     |
| global.imagePullSecrets | list   | `[]`    | Image pull secrets for private registries |

### Bootstrap Job Configuration

| Key                               | Type   | Default                                                   | Description                     |
| --------------------------------- | ------ | --------------------------------------------------------- | ------------------------------- |
| bootstrap.enabled                 | bool   | `true`                                                    | Enable the bootstrap job        |
| bootstrap.image.repository        | string | `"alpine"`                                                | Container image repository      |
| bootstrap.image.tag               | string | `"3.19"`                                                  | Image tag                       |
| bootstrap.image.pullPolicy        | string | `"IfNotPresent"`                                          | Image pull policy               |
| bootstrap.command                 | list   | `["/bin/sh", "-c"]`                                       | Command override                |
| bootstrap.args                    | list   | `["apk add --no-cache curl jq && /scripts/bootstrap.sh"]` | Arguments for bootstrap command |
| bootstrap.backoffLimit            | int    | `3`                                                       | Job backoff limit               |
| bootstrap.ttlSecondsAfterFinished | int    | `300`                                                     | TTL for completed jobs          |
| bootstrap.activeDeadlineSeconds   | int    | `600`                                                     | Job active deadline in seconds  |

### Bootstrap Resources

| Key                                 | Type   | Default   | Description    |
| ----------------------------------- | ------ | --------- | -------------- |
| bootstrap.resources.limits.cpu      | string | `"500m"`  | CPU limit      |
| bootstrap.resources.limits.memory   | string | `"256Mi"` | Memory limit   |
| bootstrap.resources.requests.cpu    | string | `"100m"`  | CPU request    |
| bootstrap.resources.requests.memory | string | `"128Mi"` | Memory request |

### Bootstrap Security

| Key                                         | Type | Default   | Description              |
| ------------------------------------------- | ---- | --------- | ------------------------ |
| bootstrap.securityContext.runAsNonRoot      | bool | `true`    | Run as non-root user     |
| bootstrap.securityContext.runAsUser         | int  | `1000`    | User ID to run container |
| bootstrap.securityContext.fsGroup           | int  | `1000`    | Filesystem group         |
| bootstrap.securityContext.capabilities.drop | list | `["ALL"]` | Capabilities to drop     |

### Bootstrap Wait Configuration

| Key                         | Type | Default | Description                       |
| --------------------------- | ---- | ------- | --------------------------------- |
| bootstrap.wait.enabled      | bool | `false` | Enable waiting for Keycloak ready |
| bootstrap.wait.maxAttempts  | int  | `60`    | Maximum number of retry attempts  |
| bootstrap.wait.sleepSeconds | int  | `5`     | Seconds to sleep between attempts |

### Keycloak Configuration

| Key                               | Type   | Default                                        | Description                    |
| --------------------------------- | ------ | ---------------------------------------------- | ------------------------------ |
| keycloak.url                      | string | `"http://keycloak:8080"`                       | Keycloak server URL            |
| keycloak.healthUrl                | string | `"http://keycloak:9000/keycloak/health/ready"` | Health check URL               |
| keycloak.adminUsername            | string | `"admin"`                                      | Admin username                 |
| keycloak.adminPasswordSecret.name | string | `"keycloak-admin"`                             | Secret name for admin password |
| keycloak.adminPasswordSecret.key  | string | `"password"`                                   | Secret key for admin password  |

### Realm Configuration

| Key                                  | Type   | Default                 | Description                         |
| ------------------------------------ | ------ | ----------------------- | ----------------------------------- |
| keycloak.realm.name                  | string | `"governance"`          | Realm name                          |
| keycloak.realm.displayName           | string | `"Governance Platform"` | Realm display name                  |
| keycloak.realm.loginWithEmailAllowed | bool   | `true`                  | Allow login with email              |
| keycloak.realm.registrationAllowed   | bool   | `true`                  | Allow user registration             |
| keycloak.realm.resetPasswordAllowed  | bool   | `true`                  | Allow password reset                |
| keycloak.realm.rememberMe            | bool   | `true`                  | Enable remember me option           |
| keycloak.realm.verifyEmail           | bool   | `false`                 | Require email verification          |
| keycloak.realm.sslRequired           | string | `"external"`            | SSL requirement (external/all/none) |
| keycloak.realm.bruteForceProtected   | bool   | `true`                  | Enable brute force protection       |

### Token Configuration

| Key                                   | Type | Default | Description                         |
| ------------------------------------- | ---- | ------- | ----------------------------------- |
| keycloak.tokens.accessTokenLifespan   | int  | `300`   | Access token lifespan in seconds    |
| keycloak.tokens.ssoSessionIdleTimeout | int  | `1800`  | SSO session idle timeout in seconds |
| keycloak.tokens.ssoSessionMaxLifespan | int  | `36000` | SSO session max lifespan in seconds |

### Frontend Client Configuration

| Key                             | Type   | Default                                | Description                  |
| ------------------------------- | ------ | -------------------------------------- | ---------------------------- |
| clients.frontend.clientId       | string | `"governance-platform-frontend"`       | Client ID                    |
| clients.frontend.name           | string | `"Governance Platform Frontend"`       | Display name                 |
| clients.frontend.description    | string | See values.yaml                        | Client description           |
| clients.frontend.publicClient   | bool   | `true`                                 | Public client (no secret)    |
| clients.frontend.redirectUris   | list   | See values.yaml                        | Valid redirect URIs          |
| clients.frontend.webOrigins     | list   | See values.yaml                        | Allowed web origins for CORS |
| clients.frontend.defaultScopes  | list   | `["openid","profile","email","roles"]` | Default client scopes        |
| clients.frontend.optionalScopes | list   | `["offline_access"]`                   | Optional client scopes       |

### Backend Client Configuration

| Key                                    | Type   | Default                                | Description                  |
| -------------------------------------- | ------ | -------------------------------------- | ---------------------------- |
| clients.backend.clientId               | string | `"governance-platform-backend"`        | Client ID                    |
| clients.backend.name                   | string | `"Governance Platform Backend"`        | Display name                 |
| clients.backend.description            | string | See values.yaml                        | Client description           |
| clients.backend.publicClient           | bool   | `false`                                | Confidential client          |
| clients.backend.serviceAccountsEnabled | bool   | `true`                                 | Enable service account       |
| clients.backend.secretName             | string | `"keycloak-backend-client"`            | Secret name for credentials  |
| clients.backend.secretKey              | string | `"client-secret"`                      | Secret key for client secret |
| clients.backend.redirectUris           | list   | See values.yaml                        | Valid redirect URIs          |
| clients.backend.webOrigins             | list   | See values.yaml                        | Allowed web origins for CORS |
| clients.backend.defaultScopes          | list   | `["openid","profile","email","roles"]` | Default client scopes        |

### Worker Client Configuration

| Key                                   | Type   | Default                                | Description                  |
| ------------------------------------- | ------ | -------------------------------------- | ---------------------------- |
| clients.worker.clientId               | string | `"governance-worker"`                  | Client ID                    |
| clients.worker.name                   | string | `"Governance Worker"`                  | Display name                 |
| clients.worker.description            | string | See values.yaml                        | Client description           |
| clients.worker.publicClient           | bool   | `false`                                | Confidential client          |
| clients.worker.serviceAccountsEnabled | bool   | `true`                                 | Enable service account       |
| clients.worker.secretName             | string | `"keycloak-worker-client"`             | Secret name for credentials  |
| clients.worker.secretKey              | string | `"client-secret"`                      | Secret key for client secret |
| clients.worker.defaultScopes          | list   | `["openid","profile","email","roles"]` | Default client scopes        |

### Custom Scopes

| Key    | Type | Default         | Description                   |
| ------ | ---- | --------------- | ----------------------------- |
| scopes | list | See values.yaml | Custom OAuth scopes to create |

Default scopes created:

- `read:organizations` - Read access to organizations
- `write:organizations` - Write access to organizations
- `read:projects` - Read access to projects
- `write:projects` - Write access to projects
- `read:evaluations` - Read access to evaluations
- `write:evaluations` - Write access to evaluations

### Admin User Configuration

| Key                           | Type   | Default                    | Description                      |
| ----------------------------- | ------ | -------------------------- | -------------------------------- |
| users.admin.enabled           | bool   | `true`                     | Enable creation of admin user    |
| users.admin.username          | string | `"platform-admin"`         | Admin username                   |
| users.admin.email             | string | `"admin@governance.local"` | Admin email address              |
| users.admin.firstName         | string | `"Platform"`               | Admin first name                 |
| users.admin.lastName          | string | `"Admin"`                  | Admin last name                  |
| users.admin.emailVerified     | bool   | `true`                     | Mark email as verified           |
| users.admin.temporaryPassword | bool   | `false`                    | Require password change on login |
| users.admin.secretName        | string | `"keycloak-admin-user"`    | Secret name for admin password   |
| users.admin.secretKey         | string | `"password"`               | Secret key for admin password    |

### Test Users Configuration

| Key                     | Type | Default         | Description                   |
| ----------------------- | ---- | --------------- | ----------------------------- |
| users.testUsers.enabled | bool | `false`         | Enable creation of test users |
| users.testUsers.users   | list | See values.yaml | List of test users to create  |

### Output Configuration

| Key                     | Type   | Default                      | Description                         |
| ----------------------- | ------ | ---------------------------- | ----------------------------------- |
| output.generateEnvFile  | bool   | `true`                       | Generate .env file with config      |
| output.createSecrets    | bool   | `true`                       | Create K8s secrets with credentials |
| output.secrets.frontend | string | `"keycloak-frontend-config"` | Secret name for frontend config     |
| output.secrets.backend  | string | `"keycloak-backend-config"`  | Secret name for backend config      |
| output.secrets.worker   | string | `"keycloak-worker-config"`   | Secret name for worker config       |

## Usage Examples

### Development Environment

```yaml
# values-dev.yaml
keycloak:
  url: http://keycloak:8080
  realm:
    name: governance-dev

clients:
  frontend:
    redirectUris:
      - "http://localhost:5173/*"
    webOrigins:
      - "http://localhost:5173"
  backend:
    redirectUris:
      - "http://localhost:8000/*"
    webOrigins:
      - "http://localhost:8000"

users:
  admin:
    enabled: true
  testUsers:
    enabled: true
    users:
      - username: "test-user-1"
        email: "test1@governance.local"
        firstName: "Test"
        lastName: "User 1"
        password: "test123"
```

### Production Environment

```yaml
# values-prod.yaml
keycloak:
  url: https://auth.example.com
  realm:
    name: governance
    sslRequired: "all"

clients:
  frontend:
    redirectUris:
      - "https://app.example.com/*"
    webOrigins:
      - "https://app.example.com"
  backend:
    redirectUris:
      - "https://api.example.com/*"
    webOrigins:
      - "https://api.example.com"

users:
  admin:
    enabled: true
    temporaryPassword: true
  testUsers:
    enabled: false

bootstrap:
  resources:
    limits:
      cpu: 1000m
      memory: 512Mi
```

## Integration with Applications

After successful bootstrap, the platform services reference the Keycloak secret using `secretKeyRef`. The standard secret name is `platform-keycloak` with the following keys:

```yaml
# Example auth-service deployment referencing Keycloak credentials
config:
  - name: IDP_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: platform-keycloak
        key: backend-client-id
  - name: IDP_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: platform-keycloak
        key: backend-client-secret
```

The Keycloak secret should contain these keys:

| Key                          | Description                               |
| ---------------------------- | ----------------------------------------- |
| `url`                        | Keycloak server URL                       |
| `realm`                      | Realm name                                |
| `frontend-client-id`         | Public client ID for frontend SPA         |
| `backend-client-id`          | Confidential client ID for backend        |
| `backend-client-secret`      | Client secret for backend authentication  |
| `token-exchange-private-key` | (Optional) Private key for token exchange |

## Troubleshooting

### Viewing Job Status

```bash
kubectl get jobs -n governance -l app.kubernetes.io/name=keycloak-bootstrap
```

### Viewing Logs

```bash
kubectl logs -n governance -l app.kubernetes.io/name=keycloak-bootstrap
```

### Common Issues

**Job fails with authentication error**

- Verify Keycloak admin credentials
- Check if Keycloak is accessible from the pod
- Ensure `keycloak.adminPasswordSecret` references correct secret

**Realm already exists**

- The job is idempotent and will skip existing resources
- Delete the realm manually if you need a fresh start

**Timeout waiting for Keycloak**

- Increase `bootstrap.wait.maxAttempts`
- Check Keycloak pod status
- Verify `keycloak.healthUrl` is correct

**Client secret not found**

- Ensure client secret secrets are created before running bootstrap
- Verify secret names match configuration

**Connection refused**

- Verify Keycloak URL is correct for internal cluster access
- Check if Keycloak service is running
- Ensure namespace is correct

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://docs.eqtylab.io
- GitHub: https://github.com/eqtylab/governance-studio-infrastructure
