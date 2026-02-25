"""Interactive prompts for govctl CLI."""

from rich.prompt import Prompt, Confirm

from govctl.core.models import PlatformConfig, CloudProvider, AuthProvider
from govctl.utils.output import console


def collect_interactive_config(
    cloud: str | None,
    domain: str | None,
    environment: str | None,
    auth: str | None,
) -> PlatformConfig:
    """Collect configuration interactively."""
    console.print()

    # Cloud provider
    if cloud:
        cloud_provider = CloudProvider(cloud.lower())
    else:
        cloud_choice = Prompt.ask(
            "[bold]Cloud provider[/bold]",
            choices=["gcp", "aws", "azure"],
            default="gcp",
        )
        cloud_provider = CloudProvider(cloud_choice)

    # Domain
    if domain:
        domain_value = domain
    else:
        domain_value = Prompt.ask(
            "[bold]Domain[/bold]",
            default="governance.example.com",
        )

    # Environment
    if environment:
        env = environment.lower()
    else:
        env = Prompt.ask(
            "[bold]Environment[/bold]",
            default="staging",
        )

    # Auth provider
    if auth:
        auth_provider = AuthProvider(auth.lower())
    else:
        auth_choice = Prompt.ask(
            "[bold]Auth provider[/bold]",
            choices=["auth0", "keycloak", "entra"],
            default="keycloak",
        )
        auth_provider = AuthProvider(auth_choice)

    # Create base config
    config = PlatformConfig(
        cloud_provider=cloud_provider,
        domain=domain_value,
        environment=env,
        auth_provider=auth_provider,
    )

    # Cloud region (only needed for AWS)
    if cloud_provider == CloudProvider.AWS:
        config.cloud_region = Prompt.ask(
            "[bold]AWS region[/bold]",
            default="us-east-1",
        )

    # Collect provider-specific details
    console.print()
    console.print("[bold]Provider-specific configuration:[/bold]")

    # Azure Key Vault (required for DID keys)
    if Confirm.ask("\n  Configure Azure Key Vault for DID keys?", default=True):
        config.azure_key_vault_url = Prompt.ask(
            "  Azure Key Vault URL",
            default="https://your-keyvault.vault.azure.net/",
        )
        config.azure_tenant_id = Prompt.ask(
            "  Azure Tenant ID",
            default="",
        )

    # Auth-specific
    if auth_provider == AuthProvider.AUTH0:
        config.auth0_domain = Prompt.ask(
            "  Auth0 domain",
            default="your-tenant.us.auth0.com",
        )
        config.auth0_audience = Prompt.ask(
            "  Auth0 audience/API identifier",
            default=f"https://{domain_value}",
        )
    elif auth_provider == AuthProvider.KEYCLOAK:
        keycloak_default = f"https://{domain_value}/keycloak"
        config.keycloak_url = Prompt.ask(
            "  Keycloak URL",
            default=keycloak_default,
        )
        config.keycloak_realm = Prompt.ask(
            "  Keycloak realm",
            default="governance",
        )
    elif auth_provider == AuthProvider.ENTRA:
        config.entra_tenant_id = Prompt.ask(
            "  Entra tenant ID",
            default="",
        )
        config.entra_client_id = Prompt.ask(
            "  Entra client ID (app registration)",
            default="",
        )

    # Image registry
    console.print()
    console.print("[bold]Image registry configuration:[/bold]")
    config.image_registry_url = Prompt.ask(
        "  Registry URL",
        default="ghcr.io",
    )
    config.image_registry_username = Prompt.ask(
        "  Registry username",
        default="",
    )
    config.image_registry_email = Prompt.ask(
        "  Registry email",
        default="",
    )

    return config
