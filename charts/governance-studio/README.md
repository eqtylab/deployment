# EQTY Lab Governance Studio - Customer Deployment

This Helm chart enables customers to deploy the EQTY Lab Governance Studio frontend in their own Kubernetes environments with custom domain names and configuration.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.8+
- Ingress controller (nginx, traefik, etc.)
- Valid TLS certificates or cert-manager for automatic certificate management

## Quick Start

### 1. Add the Helm Repository (if published)

```bash
helm repo add eqtylab https://charts.eqtylab.io
helm repo update
```

### 2. Create Your Configuration

Copy the example values file and customize it for your environment:

```bash
cp customer-values-example.yaml my-values.yaml
```

Edit `my-values.yaml` with your specific configuration:

- **Domain Name**: Update `config.appHostname` and `ingress.hosts`
- **API URLs**: Set `config.apiUrl` to your backend API
- **Auth0**: Configure your Auth0 tenant details
- **Branding**: Customize logos and colors for your organization
- **Features**: Enable/disable features as needed

### 3. Deploy

```bash
helm install governance-studio eqtylab/governance-studio \
  -f my-values.yaml \
  --namespace governance \
  --create-namespace
```

### 4. Access Your Deployment

Once deployed, access your Governance Studio at your configured domain (e.g., `https://governance.your-company.com`).

## Configuration Reference

### Core Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `config.apiUrl` | Backend API URL | `""` |
| `config.auth0Domain` | Auth0 tenant domain | `""` |
| `config.auth0ClientId` | Auth0 application client ID | `""` |
| `config.appHostname` | Application hostname | `""` |

### Feature Flags

| Parameter | Description | Default |
|-----------|-------------|---------|
| `config.features.compliance` | Enable compliance features | `true` |
| `config.features.governance` | Enable governance features | `true` |
| `config.features.guardian` | Enable guardian features | `true` |
| `config.features.lineage` | Enable lineage features | `true` |

### Branding

| Parameter | Description | Default |
|-----------|-------------|---------|
| `config.branding.logoUrl` | URL to your company logo | `"/vite.svg"` |
| `config.branding.primaryColor` | Primary brand color (hex) | `"#0f172a"` |
| `config.branding.companyName` | Company name for display | `"EQTY Lab"` |

### Infrastructure

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of pod replicas | `2` |
| `image.repository` | Container image repository | `""` |
| `image.tag` | Container image tag | `"latest"` |
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.className` | Ingress class name | `"nginx"` |

## Runtime Configuration

This deployment uses runtime configuration injection, which means:

- ✅ **Single Container Image**: One image works for all customer environments
- ✅ **No Rebuilds**: Configuration changes don't require rebuilding containers
- ✅ **Easy Updates**: Update configuration by changing Helm values and redeploying
- ✅ **Environment Flexibility**: Switch between dev/staging/prod easily

Configuration is injected at container startup via environment variables and converted to a JavaScript configuration file that the frontend loads.

## Upgrading

To upgrade to a new version:

### Standalone Deployment

```bash
# Check current version
helm list -n governance

# Upgrade to latest version
helm upgrade governance-studio eqtylab/governance-studio \
  -f my-values.yaml \
  --namespace governance

# Upgrade to specific version
helm upgrade governance-studio eqtylab/governance-studio \
  --version 1.0.0 \
  -f my-values.yaml \
  --namespace governance
```

### As Part of Governance Studio Platform

If deployed as part of the umbrella chart:

```bash
# Upgrade the entire platform
helm upgrade governance-studio ./charts/governance-studio \
  --namespace governance \
  --values values.yaml \
  --values my-secrets.yaml
```

### Upgrade Best Practices

1. **Test Configuration**: Verify your values file is up to date
2. **Check Breaking Changes**: Review release notes for breaking changes
3. **Rolling Updates**: The chart supports zero-downtime rolling updates
4. **Backup Configuration**: Keep a backup of your current configuration

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n governance
kubectl logs -f deployment/governance-studio -n governance
```

### Verify Configuration

Check that your configuration was applied correctly:

```bash
kubectl get configmap governance-studio-config -n governance -o yaml
```

### Check Ingress

```bash
kubectl get ingress -n governance
kubectl describe ingress governance-studio -n governance
```

### Common Issues

1. **404 on custom domain**: Check that your DNS points to the ingress controller
2. **TLS certificate issues**: Verify cert-manager is working or upload certificates manually
3. **Auth0 login fails**: Check that redirect URIs are configured correctly in Auth0
4. **API connection fails**: Verify the API URL is correct and reachable from the frontend

### Health Monitoring

The application provides health check endpoints:

```bash
# Check application health (if health endpoint is configured)
curl https://your-domain.com/health

# Monitor pod resource usage
kubectl top pods -n governance -l app.kubernetes.io/name=governance-studio

# View application logs
kubectl logs -f deployment/governance-studio -n governance --tail=100
```

## Support

For deployment support, please contact support@eqtylab.io or create an issue in the GitHub repository.