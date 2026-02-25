"""Init command for govctl."""

from pathlib import Path

import click
from rich.panel import Panel
from rich.prompt import Confirm

from govctl.core.models import PlatformConfig, CloudProvider, AuthProvider
from govctl.generators.values import generate_values
from govctl.generators.secrets import generate_secrets
from govctl.generators.bootstrap import generate_bootstrap

from govctl.utils.output import console
from govctl.cli.prompts import collect_interactive_config
from govctl.cli.display import show_config_summary, show_next_steps


@click.command("init")
@click.option(
    "--cloud",
    "-c",
    type=click.Choice(["gcp", "aws", "azure"], case_sensitive=False),
    help="Cloud provider",
)
@click.option(
    "--domain",
    "-d",
    help="Domain name (e.g., governance.example.com)",
)
@click.option(
    "--environment",
    "-e",
    help="Environment name (e.g., development, staging, production)",
)
@click.option(
    "--auth",
    "-a",
    type=click.Choice(["auth0", "keycloak", "entra"], case_sensitive=False),
    help="Authentication provider",
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
def init_cmd(
    cloud: str | None,
    domain: str | None,
    environment: str | None,
    auth: str | None,
    output: str,
    interactive: bool,
):
    """Initialize a new Governance Studio Platform deployment.

    Generates values.yaml and secrets.yaml files based on your configuration.

    Examples:

        # Interactive mode (default)
        govctl init

        # Non-interactive mode
        govctl init --cloud gcp --domain governance.example.com --environment staging --auth keycloak

        # Output to specific directory
        govctl init -o ./my-deployment
    """
    console.print(
        Panel.fit(
            "[bold blue]Governance Studio Platform Configuration[/bold blue]\n"
            "Generate Helm values for your deployment",
            border_style="blue",
        )
    )

    # Collect configuration
    if interactive:
        config = collect_interactive_config(cloud, domain, environment, auth)
    else:
        if not all([cloud, domain, environment, auth]):
            raise click.UsageError(
                "All options (--cloud, --domain, --environment, --auth) are required in non-interactive mode"
            )
        config = PlatformConfig(
            cloud_provider=CloudProvider(cloud.lower()),
            domain=domain,
            environment=environment.lower(),
            auth_provider=AuthProvider(auth.lower()),
        )

    # Show summary
    show_config_summary(config)

    if interactive and not Confirm.ask(
        "\n[bold]Generate files with this configuration?[/bold]"
    ):
        console.print("[yellow]Aborted.[/yellow]")
        return

    # Generate files
    output_path = Path(output)
    output_path.mkdir(parents=True, exist_ok=True)

    values_content = generate_values(config)
    secrets_content = generate_secrets(config)

    values_file = output_path / f"values-{config.environment}.yaml"
    secrets_file = output_path / f"secrets-{config.environment}.yaml"

    values_file.write_text(values_content)
    secrets_file.write_text(secrets_content)

    bootstrap_file = None
    if config.auth_provider == AuthProvider.KEYCLOAK:
        bootstrap_content = generate_bootstrap(config)
        bootstrap_file = output_path / f"bootstrap-{config.environment}.yaml"
        bootstrap_file.write_text(bootstrap_content)

    console.print()
    console.print("[bold green]Files generated successfully![/bold green]")
    console.print()
    console.print(f"  [cyan]{values_file}[/cyan]")
    console.print(f"  [cyan]{secrets_file}[/cyan]")
    if bootstrap_file:
        console.print(f"  [cyan]{bootstrap_file}[/cyan]")
    console.print()

    show_next_steps(config, values_file, secrets_file, bootstrap_file)
