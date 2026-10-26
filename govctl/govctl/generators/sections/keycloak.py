"""Keycloak section generator."""

from typing import Any

from govctl.core.models import PlatformConfig


def generate_keycloak_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the keycloak post-install hook section of values.yaml."""
    section: dict[str, Any] = {
        "createOrganization": True,
        "realmName": config.keycloak_realm,
        "displayName": "Guardian Platform",
        "createPlatformAdmin": True,
        "platformAdminEmail": f"admin@{config.domain}",
    }
    if config.keycloak_url:
        section["url"] = config.keycloak_base_url
    return section
