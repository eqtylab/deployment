"""Interactive prompts for govctl CLI."""

from rich.prompt import Prompt, Confirm

from govctl.core.models import PlatformConfig, CloudProvider, AuthProvider
from govctl.utils.naming import generate_domain_code
from govctl.utils.validate import (
    is_valid_aws_region,
    is_valid_domain,
    is_valid_email,
    is_valid_https_url,
    is_valid_keyvault_url,
    is_valid_realm,
    is_valid_uuid,
)
from govctl.utils.output import console


def collect_interactive_config(
    cloud: str | None,
    domain: str | None,
    environment: str | None,
    auth: str | None,
) -> PlatformConfig:
    """Collect configuration interactively."""
    console.print()

    # --- Domain ---
    if domain:
        domain_value = domain
    else:
        while True:
            domain_value = Prompt.ask(
                "[bold]Domain[/bold]",
                default=f"governance.{generate_domain_code()}.eqtylab.io",
            )
            if is_valid_domain(domain_value):
                break
            console.print(
                "[red]Invalid domain format. Please enter a valid domain (e.g. governance.example.eqtylab.io)[/red]"
            )

    # --- Environment ---
    if environment:
        env = environment.lower()
    else:
        env = Prompt.ask(
            "[bold]Environment[/bold]",
            default="development",
        )

    # --- Cloud provider ---
    console.print()
    console.print("[bold]Cloud Configuration:[/bold]")
    if cloud:
        cloud_provider = CloudProvider(cloud.lower())
    else:
        cloud_choice = Prompt.ask(
            "  Cloud Provider",
            choices=["gcp", "aws", "azure"],
            default="gcp",
        )
        cloud_provider = CloudProvider(cloud_choice)

    if cloud_provider == CloudProvider.AWS:
        while True:
            aws_region = Prompt.ask(
                "  AWS Region",
                default="us-east-1",
            )
            if is_valid_aws_region(aws_region):
                break
            console.print(
                "[red]Invalid AWS region format. Expected format: us-east-1, eu-west-2, etc.[/red]"
            )

    # Create base config
    config = PlatformConfig(
        cloud_provider=cloud_provider,
        domain=domain_value,
        environment=env,
        auth_provider=AuthProvider.KEYCLOAK,  # placeholder, set below
    )

    if cloud_provider == CloudProvider.AWS:
        config.cloud_region = aws_region

    # --- Auth provider ---
    console.print()
    console.print("[bold]Auth Configuration:[/bold]")
    if auth:
        auth_provider = AuthProvider(auth.lower())
    else:
        auth_choice = Prompt.ask(
            "  Auth Provider",
            choices=["auth0", "keycloak", "entra"],
            default="keycloak",
        )
        auth_provider = AuthProvider(auth_choice)
    config.auth_provider = auth_provider

    if auth_provider == AuthProvider.AUTH0:
        while True:
            auth0_domain = Prompt.ask(
                "  Auth0 Domain",
                default="your-tenant.us.auth0.com",
            )
            if is_valid_domain(auth0_domain):
                break
            console.print(
                "[red]Invalid domain format. Expected format: your-tenant.us.auth0.com[/red]"
            )
        config.auth0_domain = auth0_domain
        while True:
            auth0_audience = Prompt.ask(
                "  Auth0 Audience/API Identifier",
                default=f"https://{auth0_domain}/api/v2/",
            )
            if is_valid_https_url(auth0_audience) and auth0_audience.endswith(
                "/api/v2/"
            ):
                break
            console.print(
                "[red]Invalid Auth0 audience. Expected format: https://your-tenant.us.auth0.com/api/v2/[/red]"
            )
        config.auth0_audience = auth0_audience
    elif auth_provider == AuthProvider.KEYCLOAK:
        keycloak_default = f"https://{domain_value}/keycloak"
        while True:
            keycloak_url = Prompt.ask(
                "  Keycloak URL",
                default=keycloak_default,
            )
            if is_valid_https_url(keycloak_url):
                break
            console.print(
                "[red]Invalid URL format. Expected an HTTPS URL (e.g. https://your-domain.com/keycloak)[/red]"
            )
        config.keycloak_url = keycloak_url
        while True:
            keycloak_realm = Prompt.ask(
                "  Keycloak Realm",
                default="governance",
            )
            if is_valid_realm(keycloak_realm):
                break
            console.print(
                "[red]Invalid realm name. Use only letters, numbers, hyphens, and underscores.[/red]"
            )
        config.keycloak_realm = keycloak_realm
    elif auth_provider == AuthProvider.ENTRA:
        while True:
            entra_tenant_id = Prompt.ask(
                "  Entra Tenant ID",
                default="",
            )
            if not entra_tenant_id or is_valid_uuid(entra_tenant_id):
                break
            console.print(
                "[red]Invalid UUID format. Expected format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx[/red]"
            )
        config.entra_tenant_id = entra_tenant_id

    # Azure Key Vault (required for DID keys)
    if Confirm.ask("\n  Configure Azure Key Vault for DID keys?", default=True):
        while True:
            keyvault_url = Prompt.ask(
                "  Azure Key Vault URL",
                default="https://your-keyvault.vault.azure.net/",
            )
            if is_valid_keyvault_url(keyvault_url):
                break
            console.print(
                "[red]Invalid Key Vault URL. Expected format: https://{vault-name}.vault.azure.net/[/red]"
            )
        config.azure_key_vault_url = keyvault_url
        while True:
            kv_tenant_id = Prompt.ask(
                "  Azure Key Vault Tenant ID",
                default="",
            )
            if not kv_tenant_id or is_valid_uuid(kv_tenant_id):
                break
            console.print(
                "[red]Invalid UUID format. Expected format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx[/red]"
            )
        config.azure_tenant_id = kv_tenant_id

    # --- Image registry ---
    console.print()
    console.print("[bold]Image Registry Configuration:[/bold]")
    while True:
        registry_url = Prompt.ask(
            "  Registry URL",
            default="ghcr.io",
        )
        if is_valid_domain(registry_url):
            break
        console.print(
            "[red]Invalid domain format. Expected format: ghcr.io, registry.example.com, etc.[/red]"
        )
    config.image_registry_url = registry_url
    config.image_registry_username = Prompt.ask(
        "  Registry Username",
        default="",
    )
    while True:
        registry_email = Prompt.ask(
            "  Registry Email",
            default="",
        )
        if not registry_email or is_valid_email(registry_email):
            break
        console.print(
            "[red]Invalid email format. Expected format: user@example.com[/red]"
        )
    config.image_registry_email = registry_email

    return config
