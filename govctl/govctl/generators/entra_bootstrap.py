"""Entra bootstrap values generator."""

from typing import Any

from govctl.core.models import PlatformConfig
from govctl.utils.yaml import dump_yaml_with_header


def generate_entra_bootstrap(config: PlatformConfig) -> str:
    """Generate entra-bootstrap values.yaml content based on configuration."""
    domain = config.domain
    tenant_id = config.entra_tenant_id or "YOUR_ENTRA_TENANT_ID"

    data: dict[str, Any] = {
        "bootstrap": {
            "enabled": True,
            "image": {
                "repository": "mcr.microsoft.com/azure-cli",
                "tag": "latest",
                "pullPolicy": "IfNotPresent",
            },
            "backoffLimit": 3,
            "ttlSecondsAfterFinished": 300,
            "activeDeadlineSeconds": 600,
            "resources": {
                "limits": {"cpu": "500m", "memory": "512Mi"},
                "requests": {"cpu": "100m", "memory": "256Mi"},
            },
        },
        "entra": {
            "tenantId": tenant_id,
            "domain": domain,
            "servicePrincipalSecret": {
                "name": "entra-bootstrap-sp",
                "clientIdKey": "client-id",
                "clientSecretKey": "client-secret",
            },
        },
        "apps": {
            "frontend": {
                "displayName": "Governance Platform Frontend",
                "redirectUris": [
                    f"https://{domain}",
                    "http://localhost:5173",
                ],
            },
            "backend": {
                "displayName": "Governance Platform Backend",
            },
            "worker": {
                "displayName": "Governance Worker",
            },
        },
    }

    return dump_yaml_with_header(data, "bootstrap", config)
