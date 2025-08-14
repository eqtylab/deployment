# Keycloak Bootstrap Helm Chart

This Helm chart provides an automated way to bootstrap Keycloak with the necessary configuration for the Governance Platform.

## Overview

The bootstrap process creates:

- A configured realm with security settings and token exchange enabled
- Client applications (frontend, backend, worker)
- Custom scopes for authorization
- Initial platform admin user
- Configuration secrets for applications

**Note**: Groups and projects are now managed entirely within the Governance Service, not in Keycloak. This simplified approach uses token exchange flows with Auth Service for claims enrichment.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- A running Keycloak instance
- Admin credentials for Keycloak

## Installation

### Basic Installation

```bash
helm install keycloak-bootstrap ./keycloak-bootstrap \
  --set keycloak.url=http://keycloak:8080 \
  --set keycloak.adminPasswordSecret.name=keycloak-admin \
  --set clients.backend.secretName=keycloak-backend-secret \
  --set clients.worker.secretName=keycloak-worker-secret
```

### Installation with Custom Values

```bash
helm install keycloak-bootstrap ./keycloak-bootstrap -f my-values.yaml
```

## Configuration

### Required Secrets

Before installing, create the following secrets:

```bash
# Keycloak admin password
kubectl create secret generic keycloak-admin \
  --from-literal=password=admin

# Backend client secret
kubectl create secret generic keycloak-backend-client \
  --from-literal=client-secret=$(openssl rand -hex 32)

# Worker client secret
kubectl create secret generic keycloak-worker-client \
  --from-literal=client-secret=$(openssl rand -hex 32)

# Admin user password (if creating admin user)
kubectl create secret generic keycloak-admin-user \
  --from-literal=password=admin123
```

### Key Configuration Options

| Parameter                       | Description                    | Default                       |
| ------------------------------- | ------------------------------ | ----------------------------- |
| `bootstrap.enabled`             | Enable the bootstrap job       | `true`                        |
| `keycloak.url`                  | Keycloak server URL            | `http://keycloak:8080`        |
| `keycloak.realm.name`           | Name of the realm to create    | `governance`                  |
| `clients.frontend.redirectUris` | Frontend redirect URIs         | `["http://localhost:5173/*"]` |
| `clients.backend.redirectUris`  | Backend redirect URIs          | `["http://localhost:8000/*"]` |
| `users.admin.enabled`           | Create admin user              | `true`                        |
| `output.createSecrets`          | Create K8s secrets with config | `true`                        |

See `values.yaml` for all available options.

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

## Troubleshooting

### Check Job Status

```bash
kubectl get jobs -l app.kubernetes.io/name=keycloak-bootstrap
```

### View Logs

```bash
kubectl logs -l app.kubernetes.io/name=keycloak-bootstrap
```

### Common Issues

1. **Job fails with authentication error**
   - Verify Keycloak admin credentials
   - Check if Keycloak is accessible from the pod

2. **Realm already exists**
   - The job is idempotent and will skip existing resources
   - Delete the realm manually if you need a fresh start

3. **Timeout waiting for Keycloak**
   - Increase `bootstrap.wait.maxAttempts`
   - Check Keycloak pod status

## Integration with Applications

After successful bootstrap, use the created secrets in your applications:

```yaml
# Example auth-service deployment
env:
  - name: KEYCLOAK_URL
    valueFrom:
      secretKeyRef:
        name: keycloak-backend-config
        key: KEYCLOAK_URL
  - name: KEYCLOAK_REALM
    valueFrom:
      secretKeyRef:
        name: keycloak-backend-config
        key: KEYCLOAK_REALM
  - name: KEYCLOAK_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: keycloak-backend-config
        key: KEYCLOAK_CLIENT_ID
  - name: KEYCLOAK_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: keycloak-backend-secret
        key: client-secret
```

## Cleanup

To remove the bootstrap job and its resources:

```bash
helm uninstall keycloak-bootstrap
```

Note: This will not remove the created Keycloak resources (realm, clients, users).
