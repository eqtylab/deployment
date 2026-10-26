"""Secrets.yaml generator."""

import base64
import re
import secrets
from typing import Any

from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

from govctl.core.models import (
    PlatformConfig,
    CloudProvider,
    AuthProvider,
    DatabaseMode,
    KeyManagementProvider,
)
from govctl.utils.yaml import (
    LiteralStr,
    dump_yaml_with_header,
    optional,
    required,
)


def _generate_secret(length: int = 44) -> str:
    """Generate a cryptographically secure random secret of length base64 characters."""
    return base64.b64encode(secrets.token_bytes(length)).decode()[:length]


def _generate_db_secret(length: int = 32) -> str:
    """Generate a cryptographically secure hex token.

    Uses only [0-9a-f] characters, safe for inclusion in URIs such as
    PostgreSQL connection strings.
    """
    return secrets.token_hex(length)


def _generate_rsa_private_key(bits: int = 2048) -> str:
    """Generate an RSA private key in PEM format."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=bits)
    pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()
    return LiteralStr(pem)


def generate_secrets(config: PlatformConfig) -> str:
    """Generate secrets.yaml content based on configuration."""
    secrets: dict[str, Any] = {
        "global": {
            "secrets": _generate_secrets_section(config),
        }
    }

    yaml_output = dump_yaml_with_header(secrets, "secrets", config)
    if config.database_mode == DatabaseMode.BUNDLED:
        yaml_output = re.sub(
            r"^( +gatewayDsn: .*)$",
            rf"\1  # Host assumes Helm release name {config.release_name}; "
            "change it for another release name",
            yaml_output,
            count=1,
            flags=re.MULTILINE,
        )
    return yaml_output


def _gateway_dsn(config: PlatformConfig, password: str) -> str:
    """Build the guardian_gateway DSN consumed by the gateway-stack subchart.

    The gateway reads a full connection string rather than user/password fields,
    so the generated password is repeated here. Change both together.

    Only used when gateway-stack is enabled; the umbrella writes this key into
    the platform database Secret only in that case.
    """
    if config.database_mode == DatabaseMode.EXTERNAL:
        host = "TODO-set-managed-pg-host.example.com"
        # Encrypted, server certificate not verified
        ssl_mode = "require"
    else:
        # Bundled Bitnami PostgreSQL resolves to "{Release.Name}-postgresql"
        host = f"{config.release_name}-postgresql"
        ssl_mode = "disable"

    return f"postgres://postgres:{password}@{host}:5432/guardian_gateway?sslmode={ssl_mode}"


def _generate_secrets_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the secrets section based on configuration."""
    db_password = _generate_db_secret()
    secrets: dict[str, Any] = {
        "create": True,
        # Auth provider
        "auth": {
            "provider": config.auth_provider.value,
        },
        # Database (always required)
        "database": {
            "secretName": "platform-database",
            "values": {
                "username": "postgres",
                "password": db_password,
                # Only consumed when gateway-stack is enabled
                "gatewayDsn": _gateway_dsn(config, db_password),
            },
        },
        # Auth service secrets (always required)
        "authService": {
            "secretName": "platform-auth-service",
            "values": {
                "apiSecret": _generate_secret(),
                "jwtSecret": _generate_secret(),
            },
        },
        # Image registry (always required)
        "imageRegistry": {
            "secretName": "platform-image-pull-secret",
            "registry": config.image_registry_url or "ghcr.io",
            "values": {
                "username": config.image_registry_username
                or required(
                    "GitHub username"
                    if config.image_registry_url == "ghcr.io"
                    else "Registry username"
                ),
                "password": required(
                    "Cloudsmith prod entitlement token"
                    if config.image_registry_url == "docker.cloudsmith.io"
                    else (
                        "GitHub PAT with read:packages scope"
                        if config.image_registry_url == "ghcr.io"
                        else "Registry pull credential"
                    )
                ),
                "email": config.image_registry_email or "",
            },
        },
    }

    # Auth provider secrets
    if config.auth_provider == AuthProvider.AUTH0:
        secrets["auth"]["auth0"] = {
            "secretName": "platform-auth0",
            "values": {
                "clientId": required("Auth0 M2M Client ID"),
                "clientSecret": required("Auth0 M2M Client Secret"),
                "mgmtClientId": required("Auth0 Management API Client ID"),
                "mgmtClientSecret": required("Auth0 Management API Client Secret"),
            },
        }
    elif config.auth_provider == AuthProvider.ENTRA:
        secrets["auth"]["entra"] = {
            "secretName": "platform-entra",
            "values": {
                "clientId": required("Entra App Registration Client ID"),
                "clientSecret": required("Entra App Registration Client Secret"),
                "tenantId": config.entra_tenant_id or required("Entra Tenant ID"),
                "graphClientId": required("Microsoft Graph API Client ID"),
                "graphClientSecret": required("Microsoft Graph API Client Secret"),
            },
        }
    elif config.auth_provider == AuthProvider.KEYCLOAK:
        secrets["auth"]["keycloak"] = {
            "secretName": "platform-keycloak",
            "values": {
                "serviceAccountClientId": "guardian-platform-backend",
                "serviceAccountClientSecret": required("Keycloak client secret"),
                "tokenExchangePrivateKey": _generate_rsa_private_key(),
            },
        }

    # Governance worker (always required)
    secrets["governanceWorker"] = {
        "secretName": "platform-governance-worker",
        "values": {
            "encryptionKey": _generate_secret(),
            "clientId": required("Worker service account client ID"),
            "clientSecret": required("Worker service account client secret"),
        },
    }

    # Storage secrets based on cloud provider
    secrets["storage"] = {}
    if config.cloud_provider == CloudProvider.AWS:
        # Skip the static-credentials secret when using IAM role access (IRSA);
        # the AWS SDK resolves credentials from the role's default chain instead
        if not config.aws_s3_use_iam_role:
            secrets["storage"]["aws_s3"] = {
                "secretName": "platform-aws-s3",
                "values": {
                    "accessKeyId": required("AWS Access Key ID"),
                    "secretAccessKey": required("AWS Secret Access Key"),
                },
            }
    elif config.cloud_provider == CloudProvider.AZURE:
        secrets["storage"]["azure_blob"] = {
            "secretName": "platform-azure-blob",
            "values": {
                "accountKey": required("Azure Storage Account Key"),
                "connectionString": optional("Azure Storage Connection String"),
            },
        }
    elif config.cloud_provider == CloudProvider.GCP:
        secrets["storage"]["gcs"] = {
            "secretName": "platform-gcs",
            "values": {
                "serviceAccountJson": required(
                    "Base64-encoded GCP service account JSON"
                ),
            },
        }

    # Key Management (required for DID keys)
    secrets["keyManagement"] = {
        "provider": config.key_management_provider.value,
    }

    if config.key_management_provider == KeyManagementProvider.AWS_KMS:
        secrets["keyManagement"]["aws_kms"] = {
            "secretName": "platform-aws-kms",
            "values": {
                "accessKeyId": required("AWS Access Key ID for KMS"),
                "secretAccessKey": required("AWS Secret Access Key for KMS"),
                "sessionToken": "",
            },
        }
    elif config.key_management_provider == KeyManagementProvider.AZURE_KEY_VAULT:
        secrets["keyManagement"]["azure_key_vault"] = {
            "secretName": "platform-azure-key-vault",
            "values": {
                "clientId": required("Azure AD App Client ID"),
                "clientSecret": required("Azure AD App Client Secret"),
                "tenantId": config.azure_tenant_id or required("Azure Tenant ID"),
                "vaultUrl": config.azure_key_vault_url
                or required("Azure Key Vault URL"),
            },
        }
    elif config.key_management_provider == KeyManagementProvider.GCP_KMS:
        secrets["keyManagement"]["gcp_kms"] = {
            "secretName": "platform-gcp-kms",
            "values": {
                "serviceAccountJson": optional(
                    "Base64-encoded GCP service account JSON; leave empty for Workload Identity"
                ),
            },
        }

    return secrets
