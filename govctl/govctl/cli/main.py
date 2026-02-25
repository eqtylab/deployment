"""Main CLI entry point for govctl."""

import click

from govctl.cli.commands import init


@click.group()
@click.version_option()
def cli():
    """govctl - Governance Studio Platform CLI.

    Generate Helm values and secrets files for deploying the Governance Studio Platform.
    """
    pass


# Register commands
cli.add_command(init.init_cmd, name="init")
