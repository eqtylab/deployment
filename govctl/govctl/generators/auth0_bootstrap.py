"""Auth0 bootstrap values generator."""

from typing import Any

from govctl.core.models import PlatformConfig
from govctl.generators.shared import api_scopes, local_origins
from govctl.utils.yaml import dump_yaml_with_header


def generate_auth0_bootstrap(config: PlatformConfig) -> str:
    """Generate auth0-bootstrap values.yaml content based on configuration."""
    domain = config.domain
    auth0_domain = config.auth0_tenant_domain
    api_identifier = config.auth0_api_identifier
    admin_email = f"admin@{domain}"

    data: dict[str, Any] = {
        "bootstrap": {
            "enabled": True,
            "image": {
                "repository": "dwdraju/alpine-curl-jq",
                "tag": "latest",
                "pullPolicy": "IfNotPresent",
            },
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
                "name": "Guardian Platform API",
                "identifier": api_identifier,
                "tokenLifetime": 86400,
                "allowOfflineAccess": False,
            },
        },
        "applications": {
            "frontend": {
                "name": "Guardian Platform Frontend",
                "callbacks": [
                    f"https://{domain}",
                    *local_origins(config),
                ],
                "logoutUrls": [
                    f"https://{domain}",
                    *local_origins(config),
                ],
                "webOrigins": [
                    f"https://{domain}",
                    *local_origins(config),
                ],
            },
            "backend": {
                "name": "Guardian Platform Backend",
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
                    "create:users",
                    "update:users",
                    "delete:users",
                    "create:user_tickets",
                    "read:organizations",
                    "create:organizations",
                    "update:organizations",
                    "read:organization_members",
                    "create:organization_members",
                    "delete:organization_members",
                    "update:clients",
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
        "actions": {
            "postLogin": {
                "authService": {
                    "url": f"https://{domain}/authService",
                },
            },
        },
        "scopes": api_scopes(),
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
