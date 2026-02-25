"""Governance service section generator."""

from typing import Any

from govctl.core.models import PlatformConfig, CloudProvider, AuthProvider


def generate_governance_service_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the governance-service section of values.yaml."""
    section: dict[str, Any] = {
        "replicaCount": 2,
        "image": {
            "tag": "latest",
            "pullPolicy": "Always",
        },
    }

    if config.enable_ingress:
        section["ingress"] = {
            "enabled": True,
            "className": "nginx",
            "annotations": {
                "cert-manager.io/issuer": "letsencrypt-prod",
                "nginx.ingress.kubernetes.io/use-regex": "true",
                "nginx.ingress.kubernetes.io/rewrite-target": "/$2",
                "nginx.ingress.kubernetes.io/enable-cors": "true",
                "nginx.ingress.kubernetes.io/proxy-body-size": "64m",
            },
            "hosts": [
                {
                    "host": config.domain,
                    "paths": [
                        {
                            "path": "/governanceService(/|$)(.*)",
                            "pathType": "ImplementationSpecific",
                        }
                    ],
                }
            ],
            "tls": [
                {
                    "secretName": f"{config.environment}-tls-secret",
                    "hosts": [config.domain],
                }
            ],
        }

    # Application configuration
    section["config"] = {
        "appEnv": config.environment,
        "logLevel": "debug",
        "storageProvider": config.storage_provider,
    }

    # Provider-specific storage config
    if config.cloud_provider == CloudProvider.GCP:
        section["config"]["gcsBucketName"] = "YOUR_GCS_BUCKET"
    elif config.cloud_provider == CloudProvider.AWS:
        section["config"]["awsS3Region"] = config.cloud_region or "us-east-1"
        section["config"]["awsS3BucketName"] = "YOUR_S3_BUCKET"
    elif config.cloud_provider == CloudProvider.AZURE:
        section["config"]["azureStorageAccountName"] = "YOUR_STORAGE_ACCOUNT"
        section["config"]["azureStorageContainerName"] = "YOUR_CONTAINER"

    # Auth provider config
    if config.auth_provider == AuthProvider.AUTH0:
        section["config"]["auth0Domain"] = (
            config.auth0_domain or "YOUR_AUTH0_DOMAIN.us.auth0.com"
        )
    elif config.auth_provider == AuthProvider.KEYCLOAK:
        keycloak_url = config.keycloak_url or f"https://{config.domain}/keycloak"
        section["config"]["keycloakUrl"] = keycloak_url
        section["config"]["keycloakRealm"] = config.keycloak_realm
    elif config.auth_provider == AuthProvider.ENTRA:
        section["config"]["entraTenantId"] = (
            config.entra_tenant_id or "YOUR_ENTRA_TENANT_ID"
        )

    return section
