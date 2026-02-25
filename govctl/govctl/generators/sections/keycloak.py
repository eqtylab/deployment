"""Keycloak section generator."""

from typing import Any

from govctl.core.models import PlatformConfig


def generate_keycloak_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the keycloak post-install hook section of values.yaml."""
    return {
        "createOrganization": True,
        "realmName": config.keycloak_realm,
        "displayName": "Governance Platform",
        "createPlatformAdmin": True,
        "platformAdminKeycloakId": "YOUR_KEYCLOAK_USER_ID",
    }
