"""Registry presets for customer and internal installations."""

from typing import Any

from govctl.core.models import PlatformConfig

# Registry hosts that have a preset profile
PRESET_REGISTRY_HOSTS = ("ghcr.io", "docker.cloudsmith.io")


def runtime_image_values(config: PlatformConfig) -> dict[str, Any]:
    """Generate a service's image block, or nothing for Cloudsmith.

    Cloudsmith output keeps the release chart's image tags, digest pins, and
    pull policy (global.imagePullPolicy).
    """
    if config.artifact_source == "cloudsmith":
        return {}
    return {"image": {"tag": "latest", "pullPolicy": "Always"}}


def uses_custom_registry(config: PlatformConfig) -> bool:
    """Check whether images come from a registry host without a preset profile."""
    return config.image_registry_url not in PRESET_REGISTRY_HOSTS


def configure_artifacts(config: PlatformConfig, source: str) -> None:
    config.artifact_source = source
    if source == "cloudsmith":
        config.image_registry_url = "docker.cloudsmith.io"
        config.image_registry_username = "eqtylab/prod"
        config.image_repository_prefix = "docker.cloudsmith.io/eqtylab/prod"
    elif source == "github":
        config.image_registry_url = "ghcr.io"
        config.image_registry_username = ""
        config.image_repository_prefix = ""
    else:
        raise ValueError("artifact source must be cloudsmith or github")
