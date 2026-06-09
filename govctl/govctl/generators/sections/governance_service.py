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
        "environment": config.environment,
        "logLevel": "debug",
        "storageProvider": config.storage_provider,
    }

    # Provider-specific storage config
    if config.cloud_provider == CloudProvider.AWS:
        section["config"]["awsS3Region"] = config.cloud_region or "us-east-1"
        section["config"]["awsS3BucketName"] = "YOUR_S3_BUCKET"
        section["config"]["awsS3UseIamRole"] = config.aws_s3_use_iam_role
        if config.aws_s3_use_iam_role:
            # IRSA requires a dedicated service account annotated with the IAM role
            # ARN; without this the pod runs under the namespace default SA and the
            # role is never assumed
            section["serviceAccount"] = {
                "create": True,
                "annotations": {
                    "eks.amazonaws.com/role-arn": "YOUR_IAM_ROLE_ARN",
                },
            }
    elif config.cloud_provider == CloudProvider.AZURE:
        section["config"]["azureStorageAccountName"] = "YOUR_STORAGE_ACCOUNT"
        section["config"]["azureStorageContainerName"] = "YOUR_CONTAINER"
    elif config.cloud_provider == CloudProvider.GCP:
        section["config"]["gcsBucketName"] = "YOUR_GCS_BUCKET"

    # Auth provider config
    if config.auth_provider == AuthProvider.AUTH0:
        section["config"]["auth0Domain"] = (
            config.auth0_domain or "YOUR_AUTH0_DOMAIN.us.auth0.com"
        )
    elif config.auth_provider == AuthProvider.ENTRA:
        section["config"]["entraTenantId"] = (
            config.entra_tenant_id or "YOUR_ENTRA_TENANT_ID"
        )
    elif config.auth_provider == AuthProvider.KEYCLOAK:
        keycloak_url = config.keycloak_url or f"https://{config.domain}/keycloak"
        section["config"]["keycloakUrl"] = keycloak_url
        section["config"]["keycloakRealm"] = config.keycloak_realm

    return section
