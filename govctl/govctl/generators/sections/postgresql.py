"""PostgreSQL section generator."""

from typing import Any

from govctl.core.models import DatabaseMode, PlatformConfig


def generate_postgresql_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the postgresql section of values.yaml."""
    if config.database_mode == DatabaseMode.EXTERNAL:
        return {"enabled": False}

    return {
        "enabled": True,
        "primary": {
            "persistence": {
                "enabled": True,
                "size": "10Gi",
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
