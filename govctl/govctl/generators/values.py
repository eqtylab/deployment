"""Values.yaml generator."""

from typing import Any

from govctl.core.models import AuthProvider, DatabaseMode, PlatformConfig
from govctl.utils.yaml import dump_yaml_sections, file_header, required
from govctl.generators.sections.auth_service import generate_auth_service_section
from govctl.generators.sections.eqty_pdfgen import generate_eqty_pdfgen_section
from govctl.generators.sections.gateway_stack import generate_gateway_stack_section
from govctl.generators.sections.governance_service import (
    generate_governance_service_section,
)
from govctl.generators.sections.guardian import (
    generate_guardian_section,
)
from govctl.generators.sections.integrity_service import (
    generate_integrity_service_section,
)
from govctl.generators.sections.postgresql import generate_postgresql_section
from govctl.generators.sections.keycloak import generate_keycloak_section
from govctl.generators.sections.entra import generate_entra_section
from govctl.generators.sections.auth0 import generate_auth0_section


def generate_values(config: PlatformConfig) -> str:
    """Generate values.yaml content based on configuration."""
    sections: list[tuple[str, str, str, dict[str, Any]]] = [
        (
            "global",
            "Global Configuration",
            "Shared configuration values used across all services.",
            _generate_global_section(config),
        ),
        (
            "auth-service",
            "Auth Service",
            "Override values for the auth-service Helm chart.",
            generate_auth_service_section(config),
        ),
        (
            "eqty-pdfgen",
            "PDFGen",
            "Override values for the eqty-pdfgen Helm chart.",
            generate_eqty_pdfgen_section(config),
        ),
        (
            "gateway-stack",
            "Gateway Stack",
            "Override values for the gateway-stack Helm chart.",
            generate_gateway_stack_section(config),
        ),
        (
            "governance-service",
            "Governance Service",
            "Override values for the governance-service Helm chart.",
            generate_governance_service_section(config),
        ),
        (
            "guardian",
            "Guardian",
            "Override values for the Guardian chart.",
            generate_guardian_section(config),
        ),
        (
            "integrity-service",
            "Integrity Service",
            "Override values for the integrity-service Helm chart.",
            generate_integrity_service_section(config),
        ),
        (
            "postgresql",
            "PostgreSQL",
            "Override values for the postgresql Helm chart.",
            generate_postgresql_section(config),
        ),
    ]

    if config.auth_provider == AuthProvider.AUTH0:
        sections.append(
            (
                "auth0",
                "Auth0",
                "Post-install organization and admin-user setup for Auth0.",
                generate_auth0_section(config),
            )
        )
    elif config.auth_provider == AuthProvider.ENTRA:
        sections.append(
            (
                "entra",
                "Entra",
                "Post-install organization and admin-user setup for Entra.",
                generate_entra_section(config),
            )
        )
    elif config.auth_provider == AuthProvider.KEYCLOAK:
        sections.append(
            (
                "keycloak",
                "Keycloak",
                "Post-install organization and admin-user setup for Keycloak.",
                generate_keycloak_section(config),
            )
        )

    return file_header("values", config) + dump_yaml_sections(sections)


def _generate_global_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the global section of values.yaml."""
    section: dict[str, Any] = {
        "environmentType": config.environment,
        "domain": config.domain,
    }
    if config.image_repository_prefix:
        section["imageRepositoryPrefixOverride"] = config.image_repository_prefix

    if config.database_mode == DatabaseMode.EXTERNAL:
        # Placeholders for cloud-managed PostgreSQL.
        # See charts/guardian-platform/examples/values-external-postgres.yaml
        # and charts/guardian-platform/README.md (Cloud-Managed PostgreSQL Configuration)
        # for provider-specific notes (AWS RDS, Azure Flexible Server, GCP Cloud SQL).
        section["postgresql"] = {
            "host": required("Managed PostgreSQL host"),
            "port": 5432,
            "database": "governance",
            "username": "postgres",
            "sslMode": "verify-full",
            "sslRootCert": {
                "secretName": "postgres-ca",
                "key": "ca.crt",
            },
        }

    return section
