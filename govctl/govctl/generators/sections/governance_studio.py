"""Governance studio section generator."""

from typing import Any

from govctl.core.models import PlatformConfig, AuthProvider


def generate_governance_studio_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the governance-studio section of values.yaml."""
    section: dict[str, Any] = {
        "replicaCount": 1,
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
                "nginx.ingress.kubernetes.io/enable-cors": "true",
                "nginx.ingress.kubernetes.io/proxy-body-size": "64m",
            },
            "hosts": [
                {
                    "host": config.domain,
                    "paths": [{"path": "/", "pathType": "Prefix"}],
                }
            ],
            "tls": [
                {
                    "secretName": f"{config.environment}-tls-secret",
                    "hosts": [config.domain],
                }
            ],
        }

    # Auth provider config
    section["config"] = {}

    if config.auth_provider == AuthProvider.AUTH0:
        auth0_domain = config.auth0_domain or "YOUR_AUTH0_DOMAIN.us.auth0.com"
        section["config"]["auth0Domain"] = auth0_domain
        section["config"]["auth0Audience"] = (
            config.auth0_audience or f"https://{auth0_domain}/api/v2/"
        )
        section["config"]["auth0ClientId"] = "YOUR_AUTH0_SPA_CLIENT_ID"
    elif config.auth_provider == AuthProvider.KEYCLOAK:
        keycloak_url = config.keycloak_url or f"https://{config.domain}/keycloak"
        section["config"]["authProvider"] = "keycloak"
        section["config"]["keycloakUrl"] = keycloak_url
        section["config"]["keycloakRealm"] = config.keycloak_realm
        section["config"]["keycloakClientId"] = "governance-platform-frontend"
    elif config.auth_provider == AuthProvider.ENTRA:
        tenant_id = config.entra_tenant_id or "YOUR_ENTRA_TENANT_ID"
        section["config"]["entraClientId"] = (
            config.entra_client_id or "YOUR_ENTRA_CLIENT_ID"
        )
        section["config"]["entraTenantId"] = tenant_id

    # Application settings
    section["config"][
        "appTitle"
    ] = f"Governance Studio - {config.environment.capitalize()}"

    # Feature flags
    section["config"]["features"] = {
        "governance": True,
        "lineage": True,
    }

    return section
