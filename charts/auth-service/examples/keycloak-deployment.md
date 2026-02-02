# Deploying Auth Service with Keycloak

This guide shows how to deploy the auth service with Keycloak as the identity provider.

## Prerequisites

1. Keycloak instance deployed and accessible
2. Keycloak bootstrap completed (realm, clients, and initial users created)
3. Kubernetes secrets created with necessary credentials

## Step 1: Create Required Secrets

```bash
# Create Keycloak credentials secret
kubectl create secret generic platform-keycloak \
  --from-literal=client-id="governance-platform-frontend" \
  --from-literal=client-secret="<your-frontend-secret>" \
  --from-literal=service-account-client-id="governance-platform-backend" \
  --from-literal=service-account-client-secret="<your-backend-secret>" \
  -n <namespace>

# Create governance worker credentials
kubectl create secret generic platform-governance-worker \
  --from-literal=encryption-key="$(openssl rand -base64 32)" \
  --from-literal=client-id="governance-worker" \
  --from-literal=client-secret="<your-worker-secret>" \
  -n <namespace>

# Create database credentials
kubectl create secret generic platform-database \
  --from-literal=password="<your-db-password>" \
  -n <namespace>

# Create auth service security secrets
kubectl create secret generic platform-auth-service \
  --from-literal=api-secret="$(openssl rand -hex 32)" \
  --from-literal=jwt-secret="$(openssl rand -hex 32)" \
  -n <namespace>
```

## Step 2: Deploy Auth Service with Keycloak

### Option A: Using the provided values-keycloak.yaml

```bash
helm upgrade --install auth-service ./charts/auth-service \
  -f ./charts/auth-service/examples/values-keycloak.yaml \
  --set config.idp.issuer="https://keycloak.your-domain.com/realms/governance" \
  --set config.idp.keycloak.adminUrl="https://keycloak.your-domain.com" \
  --set externalDatabase.host="postgresql.your-domain.local" \
  --set ingress.hosts[0].host="auth.your-domain.local" \
  -n <namespace>
```

### Option B: Using inline values

```bash
helm upgrade --install auth-service ./charts/auth-service \
  --set config.idp.provider="keycloak" \
  --set config.idp.issuer="https://keycloak.your-domain.com/realms/governance" \
  --set config.idp.keycloak.realm="governance" \
  --set config.idp.keycloak.adminUrl="https://keycloak.your-domain.com" \
  --set config.idp.keycloak.clientId="governance-platform-frontend" \
  --set config.idp.keycloak.enableUserManagement=true \
  --set config.serviceAccounts.governanceWorker.enabled=true \
  --set config.tokenExchange.enabled=true \
  --set secrets.auth.keycloak.name="platform-keycloak" \
  --set secrets.authService.name="platform-auth-service" \
  --set secrets.worker.name="platform-governance-worker" \
  --set secrets.tokenExchange.name="platform-auth-service" \
  --set externalDatabase.passwordSecretKeyRef.name="platform-database" \
  -n <namespace>
```

## Step 3: Verify Deployment

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=auth-service -n <namespace>

# Check logs
kubectl logs -l app.kubernetes.io/name=auth-service -n <namespace>

# Test health endpoint
kubectl port-forward svc/auth-service 8080:8080 -n <namespace>
curl http://localhost:8080/health
```

## Step 4: Configure Frontend Application

Update your frontend application to use Keycloak:

```javascript
// Frontend configuration
const authConfig = {
  authority: "https://keycloak.your-domain.com/realms/governance",
  client_id: "governance-platform-frontend",
  redirect_uri: window.location.origin + "/callback",
  response_type: "code",
  scope: "openid profile email",
  post_logout_redirect_uri: window.location.origin,
  // Additional Keycloak-specific settings
  automaticSilentRenew: true,
  loadUserInfo: true,
};
```

## Step 5: Test Authentication Flow

1. Access your frontend application
2. Click login - you should be redirected to Keycloak
3. Login with the admin user created during bootstrap
4. Verify you're redirected back to the application
5. Check that the auth service properly validates tokens

## Troubleshooting

### Common Issues

1. **Token validation fails**
   - Verify the issuer URL matches exactly (including trailing slashes)
   - Check that the Keycloak realm is accessible from the auth service pod
   - Ensure the JWKS endpoint is reachable: `https://keycloak.your-domain.com/realms/governance/protocol/openid-connect/certs`

2. **Service account authentication fails**
   - Verify the service account client has "Service Accounts Enabled" in Keycloak
   - Check that the client credentials are correct
   - Ensure the service account has the necessary roles assigned

3. **User management operations fail**
   - Verify the backend client has admin permissions in Keycloak
   - Check that `enableUserManagement` is set to true
   - Ensure the admin URL is correct and accessible

### Debug Commands

```bash
# Check environment variables
kubectl exec -it <auth-service-pod> -n <namespace> -- env | grep -E "(IDP_|KEYCLOAK_)"

# Test Keycloak connectivity from pod
kubectl exec -it <auth-service-pod> -n <namespace> -- curl -s https://keycloak.your-domain.com/realms/governance/.well-known/openid-configuration

# View ConfigMap environment variables
kubectl get configmap <release-name>-auth-service -n <namespace> -o yaml
```

## Production Considerations

1. **High Availability**
   - Deploy multiple replicas of auth service
   - Use pod anti-affinity rules
   - Configure proper resource limits

2. **Security**
   - Use TLS for all communications
   - Rotate secrets regularly
   - Enable network policies
   - Use separate service accounts for different operations

3. **Monitoring**
   - Enable metrics endpoint
   - Configure ServiceMonitor for Prometheus
   - Set up alerts for authentication failures

4. **Performance**
   - Enable RBAC caching
   - Configure appropriate connection pool sizes
   - Use persistent connections to Keycloak
