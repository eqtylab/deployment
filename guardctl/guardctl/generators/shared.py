"""Values shared by several generators."""

from typing import Any

from guardctl.core.models import PlatformConfig

# Guardian API scopes, as (name, description)
API_SCOPES = [
    ("governance:declarations:create", "Create governance declarations"),
    ("integrity:statements:create", "Create integrity statements"),
    ("read:organizations", "Read access to organizations"),
    ("write:organizations", "Write access to organizations"),
    ("read:projects", "Read access to projects"),
    ("write:projects", "Write access to projects"),
    ("read:evaluations", "Read access to evaluations"),
    ("write:evaluations", "Write access to evaluations"),
]


def ingress_values(
    config: PlatformConfig,
    paths: list[dict[str, str]],
    annotations: dict[str, str] | None = None,
) -> dict[str, Any]:
    """Generate a HAProxy ingress on the platform domain with cert-manager TLS."""
    return {
        "enabled": True,
        "className": "haproxy",
        "annotations": {
            "cert-manager.io/issuer": "letsencrypt-prod",
            **(annotations or {}),
        },
        "hosts": [
            {
                "host": config.domain,
                "paths": paths,
            }
        ],
        "tls": [
            {
                "secretName": f"{config.environment}-tls-secret",
                "hosts": [config.domain],
            }
        ],
    }


def path_prefix_ingress_values(config: PlatformConfig, prefix: str) -> dict[str, Any]:
    """Generate an ingress that serves a service under /<prefix>, stripping the prefix."""
    return ingress_values(
        config,
        [{"path": f"/{prefix}", "pathType": "Prefix"}],
        {"haproxy.org/path-rewrite": f"^/{prefix}/?(.*) /\\1"},
    )


def local_origins(config: PlatformConfig, suffix: str = "") -> list[str]:
    """Generate the local frontend origin for development environments only."""
    return [f"http://localhost:5173{suffix}"] if config.is_development else []


def api_scopes() -> list[dict[str, str]]:
    """Generate the Guardian API scope definitions for a bootstrap file."""
    return [
        {"name": name, "description": description} for name, description in API_SCOPES
    ]
