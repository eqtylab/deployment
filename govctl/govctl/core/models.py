"""Configuration models for govctl."""

from dataclasses import dataclass
from enum import Enum


class CloudProvider(str, Enum):
    AWS = "aws"
    AZURE = "azure"
    GCP = "gcp"


class AuthProvider(str, Enum):
    AUTH0 = "auth0"
    ENTRA = "entra"
    KEYCLOAK = "keycloak"


class KeyManagementProvider(str, Enum):
    AWS_KMS = "aws_kms"
    AZURE_KEY_VAULT = "azure_key_vault"
    GCP_KMS = "gcp_kms"


class DatabaseMode(str, Enum):
    BUNDLED = "bundled"
    EXTERNAL = "external"


# Placeholder for an Auth0 tenant domain that was not supplied
AUTH0_DOMAIN_PLACEHOLDER = "YOUR_AUTH0_DOMAIN.us.auth0.com"

# Mapping of cloud provider to storage provider
CLOUD_TO_STORAGE = {
    CloudProvider.AWS: "aws_s3",
    CloudProvider.AZURE: "azure_blob",
    CloudProvider.GCP: "gcs",
}

# Mapping of cloud provider to default key management provider
CLOUD_TO_KEY_MANAGEMENT = {
    CloudProvider.AWS: KeyManagementProvider.AWS_KMS,
    CloudProvider.AZURE: KeyManagementProvider.AZURE_KEY_VAULT,
    CloudProvider.GCP: KeyManagementProvider.GCP_KMS,
}


@dataclass
class PlatformConfig:
    """Configuration for the Guardian Platform."""

    # Core settings
    cloud_provider: CloudProvider
    domain: str
    environment: str
    auth_provider: AuthProvider

    # Database mode (bundled Bitnami PostgreSQL or external managed PostgreSQL)
    database_mode: DatabaseMode = DatabaseMode.BUNDLED

    # Cloud region
    cloud_region: str = ""

    # AWS S3 access mode: when True, use the IAM role credential chain (IRSA /
    # instance profile) instead of static access keys, and skip the platform-aws-s3 secret
    aws_s3_use_iam_role: bool = False

    # Optional overrides
    release_name: str = "guardian-platform"
    namespace: str = "guardian"

    # Key management
    key_management_provider: KeyManagementProvider = (
        KeyManagementProvider.AZURE_KEY_VAULT
    )

    # AWS KMS-specific
    aws_kms_region: str = ""
    aws_kms_endpoint: str = ""
    aws_kms_alias_prefix: str = ""

    # Azure Key Vault-specific
    azure_key_vault_url: str = ""
    azure_tenant_id: str = ""

    # GCP KMS-specific
    gcp_kms_project_id: str = ""
    gcp_kms_location_id: str = ""
    gcp_kms_key_ring_id: str = "eqtylab-did"

    # Auth0-specific
    auth0_domain: str = ""
    auth0_audience: str = ""

    # Entra-specific
    entra_tenant_id: str = ""

    # Keycloak-specific
    keycloak_url: str = ""
    keycloak_realm: str = "guardian"

    # Image registry
    # Direct callers retain the existing internal defaults; init selects its profile.
    artifact_source: str = "github"
    image_repository_prefix: str = ""
    image_registry_url: str = "ghcr.io"
    image_registry_username: str = ""
    image_registry_email: str = ""

    # Derived settings
    @property
    def storage_provider(self) -> str:
        """Get the storage provider based on cloud provider."""
        return CLOUD_TO_STORAGE[self.cloud_provider]

    @property
    def auth0_tenant_domain(self) -> str:
        """Get the Auth0 tenant domain, or a placeholder when it is not set."""
        return self.auth0_domain or AUTH0_DOMAIN_PLACEHOLDER

    @property
    def auth0_api_identifier(self) -> str:
        """Get the Guardian API identifier, defaulting to the platform URL."""
        return self.auth0_audience or f"https://{self.domain}"

    @property
    def keycloak_base_url(self) -> str:
        """Get the Keycloak URL, defaulting to /keycloak on the platform domain."""
        return self.keycloak_url or f"https://{self.domain}/keycloak"
