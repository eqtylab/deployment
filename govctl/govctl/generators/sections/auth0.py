"""Auth0 section generator."""

from typing import Any

from govctl.core.models import PlatformConfig


def generate_auth0_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the auth0 post-install hook section of values.yaml."""
    return {
        "createOrganization": True,
        "organizationName": "guardian",
        "displayName": "Guardian Platform",
        "createPlatformAdmin": True,
        "platformAdminEmail": f"admin@{config.domain}",
        "domain": config.auth0_tenant_domain,
    }
