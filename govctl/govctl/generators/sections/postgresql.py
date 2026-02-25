"""PostgreSQL section generator."""

from typing import Any

from govctl.core.models import PlatformConfig


def generate_postgresql_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the postgresql section of values.yaml."""
    return {
        "enabled": True,
        "primary": {
            "persistence": {
                "enabled": True,
                "size": "10Gi",
                # Uses cluster default StorageClass when set to "".
                # Override per CSP if needed: GKE="standard", AKS="managed-csi", EKS="gp3"
                "storageClass": "",
            },
            "resources": {
                "requests": {
                    "cpu": "500m",
                    "memory": "1Gi",
                },
                "limits": {
                    "cpu": "2000m",
                    "memory": "2Gi",
                },
            },
        },
    }
