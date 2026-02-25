"""Display utilities for CLI output."""

from pathlib import Path

from rich.table import Table

from govctl.core.models import PlatformConfig, AuthProvider
from govctl.utils.output import console


def show_config_summary(config: PlatformConfig) -> None:
    """Display a summary of the configuration."""
    console.print()

    table = Table(title="Configuration Summary", border_style="blue")
    table.add_column("Setting", style="cyan")
    table.add_column("Value", style="green")

    table.add_row("Cloud Provider", config.cloud_provider.value.upper())
    if config.cloud_region:
        table.add_row("Cloud Region", config.cloud_region)
    table.add_row("Domain", config.domain)
    table.add_row("Environment", config.environment)
    table.add_row("Auth Provider", config.auth_provider.value)
    table.add_row("Storage Provider", config.storage_provider)

    if config.azure_key_vault_url:
        table.add_row("Key Vault URL", config.azure_key_vault_url)

    if config.auth_provider == AuthProvider.AUTH0:
        table.add_row("Auth0 Domain", config.auth0_domain)
    elif config.auth_provider == AuthProvider.KEYCLOAK:
        table.add_row("Keycloak URL", config.keycloak_url)
        table.add_row("Keycloak Realm", config.keycloak_realm)
    elif config.auth_provider == AuthProvider.ENTRA:
        table.add_row("Entra Tenant ID", config.entra_tenant_id)
        table.add_row("Entra Client ID", config.entra_client_id)

    # Image registry
    if config.image_registry_url:
        table.add_row("Image Registry", config.image_registry_url)
    if config.image_registry_username:
        table.add_row("Registry Username", config.image_registry_username)

    console.print(table)


def show_next_steps(
    config: PlatformConfig,
    values_file: Path,
    secrets_file: Path,
    bootstrap_file: Path | None = None,
) -> None:
    """Display next steps after file generation."""
    step = 1

    console.print("[bold]Next steps:[/bold]")
    console.print()
    console.print(
        f"  {step}. Fill in any remaining secrets in [cyan]{secrets_file}[/cyan]"
    )
    console.print()
    step += 1

    review_files = f"[cyan]{values_file}[/cyan]"
    if bootstrap_file:
        review_files += f" and [cyan]{bootstrap_file}[/cyan]"
    console.print(f"  {step}. Review {review_files} for correctness")
    console.print()
    step += 1

    console.print(
        f"  {step}. Follow the deployment guide for your auth provider before deploying"
        f"\n     See: https://github.com/eqtylab/deployment/tree/main/docs"
    )
    console.print()
    step += 1

    if bootstrap_file:
        console.print(f"  {step}. Run the Keycloak bootstrap:")
        console.print()
        bootstrap_cmd = (
            f"     helm upgrade --install keycloak-bootstrap ./charts/keycloak-bootstrap \\\n"
            f"       -f {bootstrap_file} \\\n"
            f"       -n {config.namespace} --wait"
        )
        console.print(f"[dim]{bootstrap_cmd}[/dim]")
        console.print()
        step += 1

    console.print(f"  {step}. Deploy the platform:")
    console.print()
    helm_cmd = (
        f"     helm upgrade --install {config.release_name} ./charts/governance-platform \\\n"
        f"       -f {values_file} \\\n"
        f"       -f {secrets_file} \\\n"
        f"       -n {config.namespace} --create-namespace"
    )
    console.print(f"[dim]{helm_cmd}[/dim]")
    console.print()
