"""Entra section generator."""

from typing import Any

from govctl.core.models import PlatformConfig
from govctl.utils.yaml import required


def generate_entra_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the entra post-install hook section of values.yaml."""
    section: dict[str, Any] = {
        "createOrganization": True,
        "organizationName": "guardian",
        "displayName": "Guardian Platform",
        "createPlatformAdmin": True,
        "platformAdminEmail": required("Platform admin email in your Entra tenant"),
    }
    # Without a tenant ID the hook reads it from the platform-entra Secret
    if config.entra_tenant_id:
        section["tenantId"] = config.entra_tenant_id
    return section
