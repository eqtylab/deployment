"""Secrets.yaml generator."""

import base64
import secrets
from typing import Any

from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

from govctl.core.models import PlatformConfig, CloudProvider, AuthProvider
from govctl.utils.yaml import dump_yaml_with_header, _LiteralStr


def _generate_secret(length: int = 32) -> str:
    """Generate a cryptographically secure random secret (base64-encoded)."""
    return base64.b64encode(secrets.token_bytes(length)).decode()


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
    return _LiteralStr(pem)


def _required(comment: str) -> str:
    """Mark a value as requiring user input. Post-processed into a YAML comment."""
    return f"__REQUIRED__{comment}"


def _add_yaml_comments(yaml_str: str) -> str:
    """Replace __REQUIRED__ markers with empty values and inline comments."""
    import re

    return re.sub(
        r"'__REQUIRED__(.+?)'",
        r"''  # REQUIRED: \1",
        yaml_str,
    )


def generate_secrets(config: PlatformConfig) -> str:
    """Generate secrets.yaml content based on configuration."""
    secrets: dict[str, Any] = {
        "global": {
            "secrets": _generate_secrets_section(config),
        }
    }

    yaml_output = dump_yaml_with_header(secrets, "secrets", config)
    return _add_yaml_comments(yaml_output)


def _generate_secrets_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the secrets section based on configuration."""
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
                "password": _generate_db_secret(),
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
        # Encryption key (always required)
        "encryption": {
            "secretName": "platform-encryption-key",
            "values": {
                "key": _generate_secret(),
            },
        },
        # Image registry (always required)
        "imageRegistry": {
            "secretName": "platform-image-pull-secret",
            "registry": config.image_registry_url or "ghcr.io",
            "values": {
                "username": config.image_registry_username or "",  # Registry username
                "password": _required("Registry password / PAT with read:packages"),
                "email": config.image_registry_email or "",
            },
        },
    }

    # Auth provider secrets
    if config.auth_provider == AuthProvider.AUTH0:
        secrets["auth"]["auth0"] = {
            "secretName": "platform-auth0",
            "values": {
                "clientId": _required("Auth0 M2M Client ID"),
                "clientSecret": _required("Auth0 M2M Client Secret"),
                "mgmtClientId": _required("Auth0 Management API Client ID"),
                "mgmtClientSecret": _required("Auth0 Management API Client Secret"),
            },
        }
    elif config.auth_provider == AuthProvider.KEYCLOAK:
        secrets["auth"]["keycloak"] = {
            "secretName": "platform-keycloak",
            "values": {
                "serviceAccountClientId": "governance-platform-backend",
                "serviceAccountClientSecret": _required("Keycloak client secret"),
                "tokenExchangePrivateKey": _generate_rsa_private_key(),
            },
        }
    elif config.auth_provider == AuthProvider.ENTRA:
        secrets["auth"]["entra"] = {
            "secretName": "platform-entra",
            "values": {
                "clientId": _required("Entra App Registration Client ID"),
                "clientSecret": _required("Entra App Registration Client Secret"),
                "tenantId": config.entra_tenant_id or _required("Entra Tenant ID"),
                "graphClientId": _required("Microsoft Graph API Client ID"),
                "graphClientSecret": _required("Microsoft Graph API Client Secret"),
            },
        }

    # Governance worker (always required)
    secrets["governanceWorker"] = {
        "secretName": "platform-governance-worker",
        "values": {
            "encryptionKey": _generate_secret(),
            "clientId": _required("Worker service account client ID"),
            "clientSecret": _required("Worker service account client secret"),
        },
    }

    # Storage secrets based on cloud provider
    secrets["storage"] = {}
    if config.cloud_provider == CloudProvider.GCP:
        secrets["storage"]["gcs"] = {
            "secretName": "platform-gcs",
            "values": {
                "serviceAccountJson": _required(
                    "Base64-encoded GCP service account JSON"
                ),
            },
        }
    elif config.cloud_provider == CloudProvider.AWS:
        secrets["storage"]["aws_s3"] = {
            "secretName": "platform-aws-s3",
            "values": {
                "accessKeyId": _required("AWS Access Key ID"),
                "secretAccessKey": _required("AWS Secret Access Key"),
            },
        }
    elif config.cloud_provider == CloudProvider.AZURE:
        secrets["storage"]["azure_blob"] = {
            "secretName": "platform-azure-blob",
            "values": {
                "accountKey": _required("Azure Storage Account Key"),
                "connectionString": _required("Azure Storage Connection String"),
            },
        }

    # Azure Key Vault (required for DID keys - currently only Azure supported)
    secrets["secretManager"] = {
        "provider": "azure_key_vault",
        "azure_key_vault": {
            "enabled": True,
            "secretName": "platform-azure-key-vault",
            "values": {
                "clientId": _required("Azure AD App Client ID"),
                "clientSecret": _required("Azure AD App Client Secret"),
                "tenantId": config.azure_tenant_id or _required("Azure Tenant ID"),
                "vaultUrl": config.azure_key_vault_url
                or _required("Azure Key Vault URL"),
            },
        },
    }

    return secrets
