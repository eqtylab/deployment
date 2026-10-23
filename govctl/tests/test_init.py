"""govctl init picks per-cloud defaults and protects existing generated files."""

from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest import mock

from click.testing import CliRunner
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from govctl.cli.commands.init import init_cmd
from govctl.core.models import AuthProvider, CloudProvider, PlatformConfig

KEY_MANAGEMENT = {"aws": "aws_kms", "azure": "azure_key_vault", "gcp": "gcp_kms"}


def init(out, *options, cloud="gcp", auth="keycloak", stdin=None):
    return CliRunner().invoke(
        init_cmd,
        [
            *options,
            "--cloud",
            cloud,
            "--domain",
            "guardian.example.com",
            "--environment",
            "staging",
            "--auth",
            auth,
            "--output",
            out,
        ],
        input=stdin,
    )


class InitTests(unittest.TestCase):
    def test_key_management_follows_cloud_in_non_interactive_mode(self):
        for cloud, provider in KEY_MANAGEMENT.items():
            with self.subTest(cloud=cloud), tempfile.TemporaryDirectory() as out:
                result = init(out, "-I", cloud=cloud)
                self.assertEqual(result.exit_code, 0, result.output)
                values = yaml.safe_load((Path(out) / "values-staging.yaml").read_text())
                self.assertEqual(
                    values["auth-service"]["config"]["keyManagement"]["provider"],
                    provider,
                )

    def test_auth0_api_identifier_defaults_to_platform_url(self):
        with tempfile.TemporaryDirectory() as out:
            result = init(out, "-I", auth="auth0")
            self.assertEqual(result.exit_code, 0, result.output)
            values = yaml.safe_load((Path(out) / "values-staging.yaml").read_text())
            bootstrap = yaml.safe_load(
                (Path(out) / "bootstrap-staging.yaml").read_text()
            )
        auth0 = values["auth-service"]["config"]["idp"]["auth0"]
        self.assertEqual(auth0["apiIdentifier"], "https://guardian.example.com")
        self.assertTrue(auth0["managementAudience"].endswith("/api/v2/"))
        self.assertEqual(
            values["guardian"]["config"]["auth0Audience"],
            "https://guardian.example.com",
        )
        self.assertEqual(
            bootstrap["auth0"]["api"]["identifier"], "https://guardian.example.com"
        )

    def test_secrets_file_is_owner_only(self):
        with tempfile.TemporaryDirectory() as out:
            self.assertEqual(init(out, "-I").exit_code, 0)
            mode = stat.S_IMODE((Path(out) / "secrets-staging.yaml").stat().st_mode)
        self.assertEqual(mode, 0o600)

    def test_existing_files_are_not_overwritten_without_force(self):
        with tempfile.TemporaryDirectory() as out:
            secrets = Path(out) / "secrets-staging.yaml"
            self.assertEqual(init(out, "-I").exit_code, 0)
            original = secrets.read_text()

            result = init(out, "-I")
            self.assertNotEqual(result.exit_code, 0)
            self.assertIn("--force", result.output)
            self.assertEqual(secrets.read_text(), original)

            self.assertEqual(init(out, "-I", "--force").exit_code, 0)
            self.assertNotEqual(secrets.read_text(), original)

    def test_interactive_overwrite_defaults_to_no(self):
        config = PlatformConfig(
            cloud_provider=CloudProvider.GCP,
            domain="guardian.example.com",
            environment="staging",
            auth_provider=AuthProvider.KEYCLOAK,
        )
        with tempfile.TemporaryDirectory() as out:
            secrets = Path(out) / "secrets-staging.yaml"
            self.assertEqual(init(out, "-I").exit_code, 0)
            original = secrets.read_text()
            with mock.patch(
                "govctl.cli.commands.init.collect_interactive_config",
                return_value=config,
            ):
                # Confirm the summary, then accept the overwrite prompt's default
                result = init(out, stdin="y\n\n")
            self.assertEqual(result.exit_code, 0, result.output)
            self.assertIn("already exist", result.output)
            self.assertIn("Aborted", result.output)
            self.assertEqual(secrets.read_text(), original)


if __name__ == "__main__":
    unittest.main()
