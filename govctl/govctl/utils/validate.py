"""Input validation utilities for govctl."""

import re


# Valid DNS hostname: dot-separated labels, each 1-63 chars of alphanumeric/hyphens,
# not starting or ending with a hyphen, with a 2+ char TLD.
def is_valid_domain(domain: str) -> bool:
    """Check if a string is a valid DNS domain format."""
    return (
        bool(
            re.compile(
                r"^(?!-)[a-zA-Z0-9-]{1,63}(?<!-)"
                r"(\.[a-zA-Z0-9-]{1,63})*"
                r"\.[a-zA-Z]{2,}$"
            ).match(domain)
        )
        and len(domain) <= 253
    )


# Azure Key Vault URL: https://{vault-name}.vault.azure.net/
def is_valid_keyvault_url(url: str) -> bool:
    """Check if a string is a valid Azure Key Vault URL."""
    return bool(
        re.compile(
            r"^https://[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]\.vault\.azure\.net/?$"
        ).match(url)
    )


# UUID v4 format (also accepts other UUID versions)
def is_valid_uuid(value: str) -> bool:
    """Check if a string is a valid UUID format."""
    return bool(
        re.compile(
            r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        ).match(value)
    )


# HTTPS URL format
def is_valid_https_url(url: str) -> bool:
    """Check if a string is a valid HTTPS URL."""
    return bool(
        re.compile(r"^https://[a-zA-Z0-9][a-zA-Z0-9.-]+[a-zA-Z0-9](/[^\s]*)?$").match(
            url
        )
    )


# AWS region format (e.g. us-east-1, eu-west-2, ap-southeast-1)
def is_valid_aws_region(region: str) -> bool:
    """Check if a string is a valid AWS region format."""
    return bool(re.compile(r"^[a-z]{2}-[a-z]+-\d$").match(region))


# Keycloak realm: alphanumeric, hyphens, underscores
def is_valid_realm(realm: str) -> bool:
    """Check if a string is a valid Keycloak realm name."""
    return bool(re.compile(r"^[a-zA-Z0-9_-]+$").match(realm))


# Basic email format
def is_valid_email(email: str) -> bool:
    """Check if a string is a basic valid email format."""
    return bool(re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$").match(email))
