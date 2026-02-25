"""Auth service section generator."""

from typing import Any

from govctl.core.models import PlatformConfig, AuthProvider


def generate_auth_service_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the auth-service section of values.yaml."""
    section: dict[str, Any] = {
        "replicaCount": 2,
        "image": {
            "tag": "",
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

    # Azure Key Vault config (required for DID keys)
    if config.azure_key_vault_url:
        section["config"]["keyVault"] = {
            "provider": "azure_key_vault",
            "azure": {
                "vaultUrl": config.azure_key_vault_url,
                "tenantId": config.azure_tenant_id,
            },
        }

    return section
