"""Registry presets for customer and internal installations."""

from govctl.core.models import PlatformConfig


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
