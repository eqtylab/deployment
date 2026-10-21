"""PDFGen section generator."""

from typing import Any

from govctl.core.artifacts import runtime_image_values

from govctl.core.models import PlatformConfig


def generate_eqty_pdfgen_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the eqty-pdfgen section of values.yaml."""
    # PDFGen is cluster-internal (no ingress) and resolves its signing URL
    # from the release name. Bound signing is an explicit values override that
    # requires compatible Auth and PDFgen images (guardian#233/#234), independent
    # of the key-management provider; it is not inherently OpenBao-only.
    # Users can layer config.signingBound/config.timestampUrl and image overrides
    # over generated values. Full generator support for these settings is deferred.
    # Enabled by default to match the guardian-platform chart default.
    section: dict[str, Any] = {
        "enabled": True,
        "replicaCount": 2,
        "image": runtime_image_values(config),
    }

    return section
