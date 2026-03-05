"""Auth service section generator."""

from typing import Any

from govctl.core.models import PlatformConfig, AuthProvider, KeyManagementProvider


def generate_auth_service_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the auth-service section of values.yaml."""
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
                "nginx.ingress.kubernetes.io/proxy-buffer-size": "16k",
                "nginx.ingress.kubernetes.io/client-header-buffer-size": "16k",
                "nginx.ingress.kubernetes.io/large-client-header-buffers": "4 16k",
            },
            "hosts": [
                {
                    "host": config.domain,
                    "paths": [
                        {
                            "path": "/authService(/|$)(.*)",
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

    # Add auth provider config
    section["config"] = {
        "idp": {
            "provider": config.auth_provider.value,
        },
    }

    if config.auth_provider == AuthProvider.AUTH0:
        auth0_domain = config.auth0_domain or "YOUR_AUTH0_DOMAIN.us.auth0.com"
        section["config"]["idp"]["issuer"] = f"https://{auth0_domain}/"
        section["config"]["idp"]["skipIssuerVerification"] = True
        section["config"]["idp"]["auth0"] = {
            "domain": auth0_domain,
            "managementAudience": f"https://{auth0_domain}/api/v2/",
            "apiIdentifier": config.auth0_audience or f"https://{auth0_domain}/api/v2/",
        }
    elif config.auth_provider == AuthProvider.KEYCLOAK:
        keycloak_url = config.keycloak_url or f"https://{config.domain}/keycloak"
        section["config"]["idp"][
            "issuer"
        ] = f"{keycloak_url}/realms/{config.keycloak_realm}"
        section["config"]["idp"]["skipIssuerVerification"] = False
        section["config"]["idp"]["keycloak"] = {
            "realm": config.keycloak_realm,
            "adminUrl": keycloak_url,
            "clientId": "governance-platform-frontend",
            "enableUserManagement": True,
            "enableGroupSync": False,
        }
        section["config"]["tokenExchange"] = {
            "enabled": True,
            "keyId": f"auth-service-{config.environment}-001",
        }
    elif config.auth_provider == AuthProvider.ENTRA:
        tenant_id = config.entra_tenant_id or "YOUR_ENTRA_TENANT_ID"
        section["config"]["idp"][
            "issuer"
        ] = f"https://login.microsoftonline.com/{tenant_id}/v2.0"
        section["config"]["idp"]["skipIssuerVerification"] = False
        section["config"]["idp"]["entra"] = {
            "tenantId": tenant_id,
            "defaultRoles": "user",
        }

    # Key management config (required for DID keys)
    section["config"]["keyManagement"] = {
        "provider": config.key_management_provider.value,
    }

    if config.key_management_provider == KeyManagementProvider.AZURE_KEY_VAULT:
        section["config"]["keyManagement"]["azure_key_vault"] = {
            "vaultUrl": config.azure_key_vault_url,
            "tenantId": config.azure_tenant_id,
        }
    elif config.key_management_provider == KeyManagementProvider.AWS_KMS:
        aws_kms_config: dict[str, Any] = {}
        if config.aws_kms_region:
            aws_kms_config["region"] = config.aws_kms_region
        if config.aws_kms_endpoint:
            aws_kms_config["endpoint"] = config.aws_kms_endpoint
        if config.aws_kms_alias_prefix:
            aws_kms_config["aliasPrefix"] = config.aws_kms_alias_prefix
        if config.aws_kms_deletion_window_days != 7:
            aws_kms_config["deletionWindowDays"] = config.aws_kms_deletion_window_days
        if aws_kms_config:
            section["config"]["keyManagement"]["aws_kms"] = aws_kms_config

    return section
