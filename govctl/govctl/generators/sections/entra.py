"""Entra section generator."""

from typing import Any

from govctl.core.models import PlatformConfig


def generate_entra_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the entra post-install hook section of values.yaml."""
    return {
        "createOrganization": True,
        "organizationName": "governance",
        "displayName": "Governance Platform",
        "createPlatformAdmin": True,
        "platformAdminEmail": "YOUR_ENTRA_ADMIN_EMAIL",  # Must exist in your Entra tenant
        "tenantId": config.entra_tenant_id or "YOUR_ENTRA_TENANT_ID",
    }
