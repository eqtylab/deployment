"""EQTY PDFGen section generator."""

from typing import Any

from govctl.core.models import PlatformConfig


def generate_eqty_pdfgen_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the eqty-pdfgen section of values.yaml."""
    # EQTY PDFGen is cluster-internal (no ingress) and resolves its signing URL
    # from the release name, so no provider- or auth-specific config is needed.
    # Disabled by default to match the governance-platform chart default; enable
    # per environment as the service is rolled out.
    section: dict[str, Any] = {
        "enabled": False,
        "replicaCount": 2,
        "image": {
            "tag": "latest",
            "pullPolicy": "Always",
        },
    }

    return section
