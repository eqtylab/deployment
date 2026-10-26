"""Input validation utilities for govctl."""

import re


# Valid DNS hostname: dot-separated labels, each 1-63 chars of alphanumeric/hyphens,
# not starting or ending with a hyphen, with a 2+ char TLD.
def is_valid_domain(domain: str) -> bool:
    """Check if a string is a valid DNS domain format."""
    return (
        bool(
            re.compile(
                r"^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$"
            ).match(domain)
        )
        and len(domain) <= 253
    )


# Registry host: a DNS domain with an optional port (e.g. registry.example.com:5000)
def is_valid_registry_host(host: str) -> bool:
    """Check if a string is a valid registry host, with an optional port."""
    name, separator, port = host.partition(":")
    if separator and not (re.fullmatch(r"[0-9]{1,5}", port) and 0 < int(port) <= 65535):
        return False
    return is_valid_domain(name)


# Environment name: a lowercase DNS label (e.g. development, staging, production)
def is_valid_environment(environment: str) -> bool:
    """Check if a string is a valid environment name."""
    return bool(re.compile(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$").match(environment))


# Azure Key Vault URL: https://{vault-name}.vault.azure.net/, or a sovereign cloud
# suffix (vault.azure.cn, vault.usgovcloudapi.net, vault.microsoftazure.de)
def is_valid_keyvault_url(url: str) -> bool:
    """Check if a string is a valid Azure Key Vault URL."""
    return bool(
        re.compile(
            r"^https://[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]\.vault\."
            r"(azure\.net|azure\.cn|usgovcloudapi\.net|microsoftazure\.de)/?$"
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


# AWS region format in any partition (e.g. us-east-1, us-gov-west-1, cn-north-1)
def is_valid_aws_region(region: str) -> bool:
    """Check if a string is a valid AWS region format."""
    return bool(re.compile(r"^[a-z]{2}(-[a-z]+)+-\d+$").match(region))


# Keycloak realm: alphanumeric, hyphens, underscores
def is_valid_realm(realm: str) -> bool:
    """Check if a string is a valid Keycloak realm name."""
    return bool(re.compile(r"^[a-zA-Z0-9_-]+$").match(realm))


# GCP project ID: 6-30 chars, lowercase letters, digits, hyphens; must start with a letter
def is_valid_gcp_project_id(project_id: str) -> bool:
    """Check if a string is a valid GCP project ID."""
    return bool(re.compile(r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$").match(project_id))


# GCP KMS location: a region (us-east1), a multi-region (us, europe, asia),
# a dual-region (nam4, eur4), nam-eur-asia1, or global
def is_valid_gcp_location(location: str) -> bool:
    """Check if a string is a valid GCP location."""
    return bool(
        re.compile(r"^([a-z]+-[a-z]+\d+|[a-z]+\d*|nam-eur-asia1)$").match(location)
    )


# GCP KMS key ring ID: alphanumeric, hyphens, underscores
def is_valid_gcp_key_ring_id(key_ring_id: str) -> bool:
    """Check if a string is a valid GCP KMS key ring ID."""
    return bool(re.compile(r"^[a-zA-Z0-9_-]+$").match(key_ring_id))


# Basic email format
def is_valid_email(email: str) -> bool:
    """Check if a string is a basic valid email format."""
    return bool(re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$").match(email))
