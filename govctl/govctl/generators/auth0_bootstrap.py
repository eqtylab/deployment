"""Auth0 bootstrap values generator."""

from typing import Any

from govctl.core.models import PlatformConfig
from govctl.utils.yaml import dump_yaml_with_header


def generate_auth0_bootstrap(config: PlatformConfig) -> str:
    """Generate auth0-bootstrap values.yaml content based on configuration."""
    domain = config.domain
    auth0_domain = config.auth0_domain or "YOUR_AUTH0_DOMAIN.us.auth0.com"
    api_identifier = config.auth0_audience or f"https://{domain}"
    admin_email = f"admin@{domain}"

    data: dict[str, Any] = {
        "bootstrap": {
            "enabled": True,
            "image": {
                "repository": "dwdraju/alpine-curl-jq",
                "tag": "latest",
                "pullPolicy": "IfNotPresent",
            },
            "args": ["/scripts/bootstrap.sh"],
            "backoffLimit": 3,
            "ttlSecondsAfterFinished": 300,
            "activeDeadlineSeconds": 600,
            "resources": {
                "limits": {"cpu": "500m", "memory": "256Mi"},
                "requests": {"cpu": "100m", "memory": "128Mi"},
            },
        },
        "auth0": {
            "domain": auth0_domain,
            "managementSecret": {
                "name": "auth0-management",
                "clientIdKey": "client-id",
                "clientSecretKey": "client-secret",
            },
            "api": {
                "name": "Governance Platform API",
                "identifier": api_identifier,
                "tokenLifetime": 86400,
                "allowOfflineAccess": False,
            },
        },
        "applications": {
            "frontend": {
                "name": "Governance Platform Frontend",
                "callbacks": [
                    f"https://{domain}/callback",
                    "http://localhost:5173/callback",
                ],
                "logoutUrls": [
                    f"https://{domain}",
                    "http://localhost:5173",
                ],
                "webOrigins": [
                    f"https://{domain}",
                    "http://localhost:5173",
                ],
            },
            "backend": {
                "name": "Governance Platform Backend",
                "apiScopes": [
                    "read:organizations",
                    "write:organizations",
                    "read:projects",
                    "write:projects",
                    "read:evaluations",
                    "write:evaluations",
                    "governance:declarations:create",
                    "integrity:statements:create",
                ],
                "managementApiScopes": [
                    "read:users",
                    "update:users",
                    "create:users",
                    "read:roles",
                    "create:role_members",
                ],
            },
            "worker": {
                "name": "Governance Worker",
                "apiScopes": [
                    "governance:declarations:create",
                    "integrity:statements:create",
                ],
            },
        },
        "scopes": [
            {
                "name": "governance:declarations:create",
                "description": "Create governance declarations",
            },
            {
                "name": "integrity:statements:create",
                "description": "Create integrity statements",
            },
            {
                "name": "read:organizations",
                "description": "Read access to organizations",
            },
            {
                "name": "write:organizations",
                "description": "Write access to organizations",
            },
            {"name": "read:projects", "description": "Read access to projects"},
            {"name": "write:projects", "description": "Write access to projects"},
            {"name": "read:evaluations", "description": "Read access to evaluations"},
            {"name": "write:evaluations", "description": "Write access to evaluations"},
        ],
        "users": {
            "admin": {
                "enabled": True,
                "email": admin_email,
                "firstName": "Platform",
                "lastName": "Admin",
                "connection": "Username-Password-Authentication",
                "secretName": "platform-admin",
                "secretKey": "password",
            },
            "testUsers": {
                "enabled": False,
                "users": [],
            },
        },
    }

    return dump_yaml_with_header(data, "bootstrap", config)
