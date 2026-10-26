"""Keycloak bootstrap values generator."""

from typing import Any

from govctl.core.models import KEYCLOAK_IN_CLUSTER_URL, PlatformConfig
from govctl.generators.shared import api_scopes, local_origins
from govctl.utils.yaml import dump_yaml_with_header


def generate_keycloak_bootstrap(config: PlatformConfig) -> str:
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
            "resources": {
                "limits": {"cpu": "500m", "memory": "256Mi"},
                "requests": {"cpu": "100m", "memory": "128Mi"},
            },
        },
        "keycloak": {
            "url": (
                config.keycloak_base_url
                if config.keycloak_url
                else KEYCLOAK_IN_CLUSTER_URL
            ),
            "adminUsername": "admin",
            "adminPasswordSecret": {
                "name": "keycloak-admin",
                "key": "password",
            },
            "realm": {
                "name": realm,
                "displayName": "Guardian Platform",
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
                "clientId": "guardian-platform-frontend",
                "name": "Guardian Platform Frontend",
                "description": "Frontend application for Guardian Platform",
                "publicClient": True,
                "redirectUris": [
                    f"https://{domain}/*",
                    *local_origins(config, "/*"),
                ],
                "webOrigins": [
                    f"https://{domain}",
                    *local_origins(config),
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
                    },
                    {
                        "name": "platform-audience",
                        "description": "Includes frontend client ID in token audience claim",
                        "mappers": [
                            {
                                "name": "platform-audience-mapper",
                                "protocolMapper": "oidc-audience-mapper",
                                "config": {
                                    "included.client.audience": "guardian-platform-frontend",
                                    "id.token.claim": "false",
                                    "access.token.claim": "true",
                                    "introspection.token.claim": "true",
                                },
                            }
                        ],
                    },
                ],
            },
            "backend": {
                "clientId": "guardian-platform-backend",
                "name": "Guardian Platform Backend",
                "description": "Backend service for Guardian Platform",
                "publicClient": False,
                "serviceAccountsEnabled": True,
                "redirectUris": [
                    f"https://{domain}/authService/*",
                ],
                "webOrigins": [
                    f"https://{domain}",
                ],
                "defaultScopes": ["openid", "profile", "email", "roles"],
                "optionalScopes": ["offline_access"],
            },
            "worker": {
                "clientId": "governance-worker",
                "name": "Governance Worker",
                "description": "Worker service for Guardian Platform",
                "publicClient": False,
                "serviceAccountsEnabled": True,
                "defaultScopes": ["openid", "profile", "email", "roles"],
                "optionalScopes": ["offline_access"],
            },
        },
        "scopes": api_scopes(),
        "userProfile": {
            "attributes": [
                {
                    "name": "picture",
                    "displayName": "Picture",
                    "multivalued": False,
                    "permissions": {
                        "view": ["admin", "user"],
                        "edit": ["admin", "user"],
                    },
                    "validations": {"uri": {"allowedSchemes": ["https"]}},
                },
            ],
        },
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
