"""EQTY PDFGen section generator."""

from typing import Any

from govctl.core.models import PlatformConfig


def generate_eqty_pdfgen_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the eqty-pdfgen section of values.yaml."""
    # EQTY PDFGen is cluster-internal (no ingress) and resolves its signing URL
    # from the release name. Bound signing is an explicit values override that
    # requires compatible Auth and PDFgen images (Guardian #233/#234), independent
    # of the key-management provider; it is not inherently OpenBao-only.
    # Users can layer config.signingBound/config.timestampUrl and image overrides
    # over generated values. Full generator support for these settings is deferred.
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
