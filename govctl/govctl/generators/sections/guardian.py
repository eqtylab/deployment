"""Guardian chart section generator."""

from typing import Any

from govctl.core.artifacts import runtime_image_values

from govctl.core.models import PlatformConfig, AuthProvider
from govctl.generators.shared import ingress_values


def generate_guardian_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the guardian section of values.yaml."""
    section: dict[str, Any] = {
        "replicaCount": 1,
        **runtime_image_values(config),
        "ingress": ingress_values(
            config,
            [{"path": "/", "pathType": "Prefix"}],
            {"nginx.ingress.kubernetes.io/proxy-body-size": "64m"},
        ),
    }

    # Auth provider config
    section["config"] = {}

    if config.auth_provider == AuthProvider.AUTH0:
        section["config"]["authProvider"] = "auth0"
        section["config"]["auth0Domain"] = config.auth0_tenant_domain
        section["config"]["auth0Audience"] = config.auth0_api_identifier
        section["config"]["auth0ClientId"] = "YOUR_AUTH0_SPA_CLIENT_ID"
    elif config.auth_provider == AuthProvider.ENTRA:
        tenant_id = config.entra_tenant_id or "YOUR_ENTRA_TENANT_ID"
        section["config"]["authProvider"] = "entra"
        section["config"]["entraClientId"] = "YOUR_ENTRA_CLIENT_ID"
        section["config"]["entraTenantId"] = tenant_id
        section["config"][
            "entraScopes"
        ] = "openid profile email offline_access api://<backend-client-id>/access_as_user"  # Replace <backend-client-id> with backend app registration ID
    elif config.auth_provider == AuthProvider.KEYCLOAK:
        section["config"]["authProvider"] = "keycloak"
        section["config"]["keycloakUrl"] = config.keycloak_base_url
        section["config"]["keycloakRealm"] = config.keycloak_realm
        section["config"]["keycloakClientId"] = "guardian-platform-frontend"

    # Application settings
    section["config"]["appTitle"] = f"Guardian - {config.environment.capitalize()}"

    # Feature flags
    section["config"]["features"] = {
        "governance": True,
        "lineage": True,
    }

    return section
