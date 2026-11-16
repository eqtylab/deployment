"""LLM Gateway section generator."""

from typing import Any

from guardctl.core.artifacts import runtime_image_values

from guardctl.core.models import PlatformConfig


def generate_llm_gateway_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the llm-gateway section of values.yaml."""
    # Disabled, as in the chart; enable it with examples/values-gateway.yaml
    section: dict[str, Any] = {"enabled": False}
    section.update(runtime_image_values(config))

    return section
