"""Init command for govctl."""

import os
from pathlib import Path

import click
from rich.panel import Panel
from rich.prompt import Confirm

from govctl.core.models import (
    CLOUD_TO_KEY_MANAGEMENT,
    AuthProvider,
    CloudProvider,
    DatabaseMode,
    PlatformConfig,
)
from govctl.core.artifacts import configure_artifacts
from govctl.generators.values import generate_values
from govctl.generators.secrets import generate_secrets
from govctl.generators.keycloak_bootstrap import generate_keycloak_bootstrap
from govctl.generators.entra_bootstrap import generate_entra_bootstrap
from govctl.generators.auth0_bootstrap import generate_auth0_bootstrap

from govctl.utils.output import console
from govctl.utils.validate import is_valid_domain, is_valid_environment
from govctl.cli.prompts import ENVIRONMENT_FORMAT, collect_interactive_config
from govctl.cli.display import show_config_summary, show_next_steps

BOOTSTRAP_GENERATORS = {
    AuthProvider.AUTH0: generate_auth0_bootstrap,
    AuthProvider.ENTRA: generate_entra_bootstrap,
    AuthProvider.KEYCLOAK: generate_keycloak_bootstrap,
}


def write_private(path: Path, content: str) -> None:
    """Write content to path readable only by the owner (mode 0600)."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(content)


def validate_domain_option(
    ctx: click.Context, param: click.Parameter, value: str | None
) -> str | None:
    """Validate the --domain flag as a DNS name."""
    if value is None:
        return None
    value = value.strip()
    if not is_valid_domain(value):
        raise click.BadParameter(
            f"{value!r} is not a valid domain (e.g. guardian.example.com)"
        )
    return value


def validate_environment_option(
    ctx: click.Context, param: click.Parameter, value: str | None
) -> str | None:
    """Lowercase the --environment flag and validate it as a DNS label."""
    if value is None:
        return None
    value = value.strip().lower()
    if not is_valid_environment(value):
        raise click.BadParameter(f"{value!r} is not valid: {ENVIRONMENT_FORMAT}")
    return value


@click.command("init")
@click.option(
    "--cloud",
    "-c",
    type=click.Choice(["aws", "azure", "gcp"], case_sensitive=False),
    help="Cloud provider",
)
@click.option(
    "--domain",
    "-d",
    callback=validate_domain_option,
    help="Domain name (e.g., guardian.example.com)",
)
@click.option(
    "--environment",
    "-e",
    callback=validate_environment_option,
    help="Environment name, lowercased; letters, digits, and hyphens (e.g., development, staging, production)",
)
@click.option(
    "--auth",
    "-a",
    type=click.Choice(["auth0", "entra", "keycloak"], case_sensitive=False),
    help="Authentication provider",
)
@click.option(
    "--database",
    "-D",
    type=click.Choice(["bundled", "external"], case_sensitive=False),
    help="Database mode (bundled Bitnami PostgreSQL or external managed PostgreSQL)",
)
@click.option(
    "--artifact-source",
    type=click.Choice(["cloudsmith", "github"], case_sensitive=False),
    default="cloudsmith",
    show_default=True,
    help="Cloudsmith for customer releases; GitHub for internal installations",
)
@click.option(
    "--output",
    "-o",
    type=click.Path(),
    default="output",
    help="Output directory for generated files",
)
@click.option(
    "--interactive/--no-interactive",
    "-i/-I",
    default=True,
    help="Run in interactive mode",
)
@click.option(
    "--force",
    "-f",
    is_flag=True,
    help="Overwrite existing generated files without asking",
)
def init_cmd(
    cloud: str | None,
    domain: str | None,
    environment: str | None,
    auth: str | None,
    database: str | None,
    artifact_source: str,
    output: str,
    interactive: bool,
    force: bool,
):
    """Initialize a new Guardian Platform deployment.

    Generates values-{env}.yaml, secrets-{env}.yaml, and bootstrap-{env}.yaml
    files based on your configuration. Existing files are only replaced after
    confirmation, or with --force.

    Examples:

        # Interactive mode (default)
        govctl init

        # Non-interactive mode
        govctl init -I --cloud gcp --domain guardian.example.com --environment staging --auth keycloak

        # Regenerate over existing files (replaces generated secrets)
        govctl init -I --force --cloud gcp --domain guardian.example.com --environment staging --auth keycloak

        # Output to specific directory
        govctl init -o ./my-deployment
    """
    console.print(
        Panel.fit(
            "[bold blue]Guardian Platform Configuration[/bold blue]\n"
            "Generate Helm values for your deployment",
            border_style="blue",
        )
    )

    # Collect configuration
    if interactive:
        config = collect_interactive_config(
            cloud, domain, environment, auth, database, artifact_source.lower()
        )
    else:
        if not all([cloud, domain, environment, auth]):
            raise click.UsageError(
                "All options (--cloud, --domain, --environment, --auth) are required in non-interactive mode"
            )
        db_mode = (
            DatabaseMode(database.lower())
            if database
            else (
                DatabaseMode.EXTERNAL
                if environment == "production"
                else DatabaseMode.BUNDLED
            )
        )
        cloud_provider = CloudProvider(cloud.lower())
        config = PlatformConfig(
            cloud_provider=cloud_provider,
            domain=domain,
            environment=environment,
            auth_provider=AuthProvider(auth.lower()),
            database_mode=db_mode,
            key_management_provider=CLOUD_TO_KEY_MANAGEMENT[cloud_provider],
        )
        configure_artifacts(config, artifact_source.lower())

    # Show summary
    show_config_summary(config)

    if interactive and not Confirm.ask(
        "\n[bold]Generate files with this configuration?[/bold]"
    ):
        console.print("[yellow]Aborted.[/yellow]")
        return

    # Generate files
    output_path = Path(output)
    values_file = output_path / f"values-{config.environment}.yaml"
    secrets_file = output_path / f"secrets-{config.environment}.yaml"
    bootstrap_file = output_path / f"bootstrap-{config.environment}.yaml"

    # Existing files are replaced only after confirmation or with --force
    existing = [f for f in (values_file, secrets_file, bootstrap_file) if f.exists()]
    if existing and not force:
        names = ", ".join(str(f) for f in existing)
        if not interactive:
            raise click.ClickException(
                f"{names} already exist. Pass --force to overwrite them."
            )
        if not Confirm.ask(
            f"\n[bold yellow]{names} already exist. Overwrite them with newly "
            "generated secrets?[/bold yellow]",
            default=False,
        ):
            console.print("[yellow]Aborted.[/yellow]")
            return

    output_path.mkdir(parents=True, exist_ok=True)

    values_file.write_text(generate_values(config))
    write_private(secrets_file, generate_secrets(config))
    bootstrap_file.write_text(BOOTSTRAP_GENERATORS[config.auth_provider](config))

    console.print()
    console.print("[bold green]Files generated successfully![/bold green]")
    console.print()
    console.print(f"  [cyan]{values_file}[/cyan]")
    console.print(f"  [cyan]{secrets_file}[/cyan]")
    console.print(f"  [cyan]{bootstrap_file}[/cyan]")
    console.print()

    show_next_steps(config, values_file, secrets_file, bootstrap_file)
