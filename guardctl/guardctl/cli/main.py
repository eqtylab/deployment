"""Main CLI entry point for guardctl."""

import click

from guardctl.cli.commands import init


@click.group()
@click.version_option()
def cli():
    """guardctl - Guardian Platform CLI.

    Generate Helm values and secrets files for deploying the Guardian Platform.
    """
    pass


# Register commands
cli.add_command(init.init_cmd, name="init")
