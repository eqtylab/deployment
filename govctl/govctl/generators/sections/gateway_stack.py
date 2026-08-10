"""Gateway Stack section generator."""

from typing import Any

from govctl.core.models import PlatformConfig


def generate_gateway_stack_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the gateway-stack section of values.yaml."""
    # The gateway stack (LLM gateway, control plane, and Guardian console) uses
    # its own hostnames and ingress class rather than the shared platform domain,
    # so enabling it needs deployment-specific decisions that govctl does not
    # prompt for: hostnames, TLS, a registration credential signer, and plugin
    # artifact storage. Disabled by default to match the governance-platform
    # chart default.
    #
    # To enable it, layer charts/governance-platform/examples/values-gateway.yaml
    # over this file and see charts/gateway-stack/README.md for the full setup.
    # The generated secrets file already carries the gateway-dsn value the
    # umbrella needs for the guardian_gateway database.
    section: dict[str, Any] = {
        "enabled": False,
        "llmGateway": {
            "image": {
                "tag": "latest",
                "pullPolicy": "Always",
            },
        },
        "controlPlane": {
            "image": {
                "tag": "latest",
                "pullPolicy": "Always",
            },
        },
        "guardianUI": {
            "enabled": False,
            "image": {
                "tag": "latest",
                "pullPolicy": "Always",
            },
        },
    }

    return section
