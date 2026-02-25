"""Values.yaml generator."""

from typing import Any

from govctl.core.models import AuthProvider, PlatformConfig
from govctl.utils.yaml import dump_yaml_with_header
from govctl.generators.sections.auth_service import generate_auth_service_section
from govctl.generators.sections.governance_service import (
    generate_governance_service_section,
)
from govctl.generators.sections.governance_studio import (
    generate_governance_studio_section,
)
from govctl.generators.sections.integrity_service import (
    generate_integrity_service_section,
)
from govctl.generators.sections.postgresql import generate_postgresql_section
from govctl.generators.sections.keycloak import generate_keycloak_section


def generate_values(config: PlatformConfig) -> str:
    """Generate values.yaml content based on configuration."""
    values: dict[str, Any] = {
        "global": _generate_global_section(config),
        "auth-service": generate_auth_service_section(config),
        "governance-service": generate_governance_service_section(config),
        "governance-studio": generate_governance_studio_section(config),
        "integrity-service": generate_integrity_service_section(config),
        "postgresql": generate_postgresql_section(config),
    }

    if config.auth_provider == AuthProvider.KEYCLOAK:
        values["keycloak"] = generate_keycloak_section(config)

    return dump_yaml_with_header(values, "values", config)


def _generate_global_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the global section of values.yaml."""
    return {
        "environmentType": config.environment,
        "domain": config.domain,
    }
