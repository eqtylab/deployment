"""Keycloak bootstrap values generator."""

from typing import Any

from govctl.core.models import PlatformConfig
from govctl.utils.yaml import dump_yaml_with_header


def generate_bootstrap(config: PlatformConfig) -> str:
    """Generate keycloak-bootstrap values.yaml content based on configuration."""
    domain = config.domain
    realm = config.keycloak_realm

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
            "wait": {
                "enabled": False,
            },
            "resources": {
                "limits": {"cpu": "500m", "memory": "256Mi"},
                "requests": {"cpu": "100m", "memory": "128Mi"},
            },
        },
        "keycloak": {
            "url": "http://keycloak:8080/keycloak",
            "adminUsername": "admin",
            "adminPasswordSecret": {
                "name": "keycloak-admin",
                "key": "password",
            },
            "realm": {
                "name": realm,
                "displayName": "Governance Platform",
                "loginWithEmailAllowed": True,
                "registrationAllowed": False,
                "resetPasswordAllowed": False,
                "rememberMe": True,
                "verifyEmail": False,
                "sslRequired": "external",
                "bruteForceProtected": True,
            },
            "tokens": {
                "accessTokenLifespan": 300,
                "ssoSessionIdleTimeout": 1800,
                "ssoSessionMaxLifespan": 36000,
            },
        },
        "clients": {
            "frontend": {
                "clientId": "governance-platform-frontend",
                "name": "Governance Platform Frontend",
                "description": "Frontend application for Governance Platform",
                "publicClient": True,
                "redirectUris": [
                    f"https://{domain}/*",
                    "http://localhost:5173/*",
                ],
                "webOrigins": [
                    f"https://{domain}",
                    "http://localhost:5173",
                ],
                "defaultScopes": ["openid", "profile", "email", "roles", "sub"],
                "optionalScopes": ["offline_access"],
                "customScopes": [
                    {
                        "name": "sub",
                        "description": "Subject identifier",
                        "mappers": [
                            {
                                "name": "Subject",
                                "protocolMapper": "oidc-sub-mapper",
                                "config": {
                                    "access.token.claim": "true",
                                    "introspection.token.claim": "true",
                                },
                            }
                        ],
                    }
                ],
            },
            "backend": {
                "clientId": "governance-platform-backend",
                "name": "Governance Platform Backend",
                "description": "Backend service for Governance Platform",
                "publicClient": False,
                "serviceAccountsEnabled": True,
                "redirectUris": [
                    f"https://{domain}/authService/*",
                ],
                "webOrigins": [
                    f"https://{domain}",
                ],
                "defaultScopes": ["openid", "profile", "email", "roles"],
            },
            "worker": {
                "clientId": "governance-worker",
                "name": "Governance Worker",
                "description": "Worker service for Governance Platform",
                "publicClient": False,
                "serviceAccountsEnabled": True,
                "defaultScopes": ["openid", "profile", "email", "roles"],
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
                "username": "platform-admin",
                "email": f"admin@{domain}",
                "firstName": "Platform",
                "lastName": "Admin",
                "emailVerified": True,
                "temporaryPassword": False,
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
