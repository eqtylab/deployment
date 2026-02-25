"""Configuration models for govctl."""

from dataclasses import dataclass
from enum import Enum


class CloudProvider(str, Enum):
    GCP = "gcp"
    AWS = "aws"
    AZURE = "azure"


class AuthProvider(str, Enum):
    AUTH0 = "auth0"
    KEYCLOAK = "keycloak"
    ENTRA = "entra"


# Mapping of cloud provider to storage provider
CLOUD_TO_STORAGE = {
    CloudProvider.GCP: "gcs",
    CloudProvider.AWS: "aws_s3",
    CloudProvider.AZURE: "azure_blob",
}


@dataclass
class PlatformConfig:
    """Configuration for the Governance Studio Platform."""

    # Core settings
    cloud_provider: CloudProvider
    domain: str
    environment: str
    auth_provider: AuthProvider

    # Feature flags
    enable_ingress: bool = True

    # Derived settings (computed from cloud_provider)
    @property
    def storage_provider(self) -> str:
        """Get the storage provider based on cloud provider."""
        return CLOUD_TO_STORAGE[self.cloud_provider]

    # Cloud region
    cloud_region: str = ""

    # Optional overrides
    release_name: str = "governance-platform"
    namespace: str = "governance"

    # Azure-specific
    azure_key_vault_url: str = ""
    azure_tenant_id: str = ""

    # Auth0-specific
    auth0_domain: str = ""
    auth0_audience: str = ""

    # Keycloak-specific
    keycloak_url: str = ""
    keycloak_realm: str = "governance"

    # Entra-specific
    entra_tenant_id: str = ""
    entra_client_id: str = ""

    # Image registry
    image_registry_url: str = "ghcr.io"
    image_registry_username: str = ""
    image_registry_password: str = ""
    image_registry_email: str = ""


@dataclass
class GeneratedFiles:
    """Container for generated file contents."""

    values_yaml: str
    secrets_yaml: str
    output_dir: str
