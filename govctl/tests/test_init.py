"""govctl init picks per-cloud defaults and protects existing generated files."""

from pathlib import Path
import re
import stat
import sys
import tempfile
import unittest
from unittest import mock

from click.testing import CliRunner
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from govctl.cli.commands.init import init_cmd
from govctl.cli.display import show_config_summary, show_next_steps
from govctl.cli.prompts import collect_interactive_config
from govctl.core.artifacts import configure_artifacts
from govctl.core.models import (
    AuthProvider,
    CloudProvider,
    KeyManagementProvider,
    PlatformConfig,
)
from govctl.utils.output import console

KEY_MANAGEMENT = {"aws": "aws_kms", "azure": "azure_key_vault", "gcp": "gcp_kms"}


def init(
    out,
    *options,
    cloud="gcp",
    auth="keycloak",
    environment="staging",
    domain="guardian.example.com",
    stdin=None,
):
    return CliRunner().invoke(
        init_cmd,
        [
            *options,
            "--cloud",
            cloud,
            "--domain",
            domain,
            "--environment",
            environment,
            "--auth",
            auth,
            "--output",
            out,
        ],
        input=stdin,
    )


def fake_prompts(answers):
    """Answer prompts whose text contains a key, else accept the default.

    A list answers successive prompts. A prompt with neither an answer nor a
    default fails the test.
    """
    asked = []

    def ask(prompt, **kwargs):
        asked.append((prompt, kwargs))
        for label, answer in answers.items():
            if label in prompt:
                return answer.pop(0) if isinstance(answer, list) else answer
        if "default" not in kwargs:
            raise AssertionError(f"no answer or default for {prompt!r}")
        return kwargs["default"]

    return ask, asked


def interactive(answers, cloud="gcp", environment="staging", auth="keycloak"):
    """Run the interactive prompts with fake answers."""
    ask, asked = fake_prompts(answers)
    with mock.patch(
        "govctl.cli.prompts.Prompt.ask", side_effect=ask
    ), mock.patch.object(console, "quiet", True):
        config = collect_interactive_config(
            cloud, None, environment, auth, "bundled", "cloudsmith"
        )
    return config, asked


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

    def test_environment_flag_is_lowercased(self):
        with tempfile.TemporaryDirectory() as out:
            result = init(out, "-I", environment="Production")
            self.assertEqual(result.exit_code, 0, result.output)
            values = yaml.safe_load((Path(out) / "values-production.yaml").read_text())
        self.assertEqual(values["global"]["environmentType"], "production")
        self.assertFalse(values["postgresql"]["enabled"])

    def test_invalid_environment_flag_is_rejected_in_both_modes(self):
        for mode in ("-I", "-i"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as out:
                result = init(out, mode, environment="My Env/x")
                self.assertEqual(result.exit_code, 2, result.output)
                self.assertIn("--environment", result.output)
                self.assertEqual(list(Path(out).iterdir()), [])

    def test_invalid_domain_flag_is_rejected_in_both_modes(self):
        for mode in ("-I", "-i"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as out:
                result = init(out, mode, domain="not a domain")
                self.assertEqual(result.exit_code, 2, result.output)
                self.assertIn("--domain", result.output)

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


class InteractiveTests(unittest.TestCase):
    def test_domain_has_no_default_and_is_required(self):
        config, asked = interactive(
            {
                "[bold]Domain": ["", "not a domain", "guardian.example.com"],
                "GCP Project ID": "guardian-prod",
            }
        )
        domain_prompts = [
            kwargs for prompt, kwargs in asked if "[bold]Domain" in prompt
        ]
        self.assertEqual(config.domain, "guardian.example.com")
        self.assertEqual(len(domain_prompts), 3)
        for kwargs in domain_prompts:
            self.assertNotIn("default", kwargs)

    def test_placeholder_inputs_have_no_default(self):
        for cloud, auth, label in (
            ("azure", "keycloak", "Azure Key Vault URL"),
            ("gcp", "keycloak", "GCP Project ID"),
            ("gcp", "auth0", "Auth0 Domain"),
        ):
            with self.subTest(label=label):
                answers = {
                    "[bold]Domain": "guardian.example.com",
                    "Azure Key Vault URL": ["", "https://guardian.vault.azure.net/"],
                    "GCP Project ID": ["", "guardian-prod"],
                    "Auth0 Domain": ["", "guardian.us.auth0.com"],
                }
                _, asked = interactive(answers, cloud=cloud, auth=auth)
                prompts = [kwargs for prompt, kwargs in asked if label in prompt]
                self.assertEqual(len(prompts), 2)
                for kwargs in prompts:
                    self.assertNotIn("default", kwargs)

    def test_sovereign_key_vault_url_is_accepted(self):
        config, _ = interactive(
            {
                "[bold]Domain": "guardian.example.com",
                "Azure Key Vault URL": "https://guardian.vault.usgovcloudapi.net/",
            },
            cloud="azure",
        )
        self.assertEqual(
            config.azure_key_vault_url, "https://guardian.vault.usgovcloudapi.net/"
        )

    def test_environment_prompt_is_validated_and_lowercased(self):
        ask, asked = fake_prompts(
            {
                "[bold]Domain": "guardian.example.com",
                "[bold]Environment": ["My Env/x", "Production"],
                "GCP Project ID": "guardian-prod",
            }
        )
        with mock.patch(
            "govctl.cli.prompts.Prompt.ask", side_effect=ask
        ), mock.patch.object(console, "quiet", True):
            config = collect_interactive_config(
                "gcp", None, None, "keycloak", None, "cloudsmith"
            )
        self.assertEqual(config.environment, "production")
        database = [kwargs for prompt, kwargs in asked if "Database Mode" in prompt]
        self.assertEqual(database[0]["default"], "external")

    def test_keycloak_url_trailing_slash_is_stripped(self):
        config, _ = interactive(
            {
                "[bold]Domain": "guardian.example.com",
                "GCP Project ID": "guardian-prod",
                "Keycloak URL": "https://auth.example.com/keycloak/",
            }
        )
        self.assertEqual(config.keycloak_url, "https://auth.example.com/keycloak")

    def test_registry_host_may_include_a_port(self):
        config, _ = interactive(
            {
                "[bold]Domain": "guardian.example.com",
                "GCP Project ID": "guardian-prod",
                "Registry URL": "registry.example.com:5000",
                "image repository prefix": "registry.example.com:5000/eqtylab",
            }
        )
        self.assertEqual(config.image_registry_url, "registry.example.com:5000")
        self.assertEqual(
            config.image_repository_prefix, "registry.example.com:5000/eqtylab"
        )

    def test_aws_kms_iam_role_defaults_to_the_s3_choice(self):
        for s3, kms, expected in (
            ("no", None, False),
            ("yes", None, True),
            ("yes", "no", False),
            ("no", "yes", True),
        ):
            with self.subTest(s3=s3, kms=kms):
                answers = {
                    "[bold]Domain": "guardian.example.com",
                    "AWS S3 access via IAM role": s3,
                }
                if kms:
                    answers["AWS KMS access via IAM role"] = kms
                config, _ = interactive(answers, cloud="aws")
                self.assertEqual(config.aws_kms_use_iam_role, expected)

    def test_aws_kms_iam_role_is_asked_only_on_aws(self):
        _, asked = interactive(
            {
                "[bold]Domain": "guardian.example.com",
                "Key Management Provider": "aws_kms",
            },
            cloud="gcp",
        )
        self.assertFalse(any("AWS KMS access" in prompt for prompt, _ in asked))

    def test_summary_shows_aws_kms_access_mode(self):
        for use_iam_role, label in (
            (True, "IAM role (IRSA / instance profile)"),
            (False, "static access keys"),
        ):
            with self.subTest(use_iam_role=use_iam_role):
                config = PlatformConfig(
                    cloud_provider=CloudProvider.AWS,
                    domain="guardian.example.com",
                    environment="staging",
                    auth_provider=AuthProvider.KEYCLOAK,
                    key_management_provider=KeyManagementProvider.AWS_KMS,
                    aws_kms_use_iam_role=use_iam_role,
                )
                with console.capture() as capture:
                    show_config_summary(config)
                self.assertRegex(
                    capture.get(), rf"AWS KMS Access +│ {re.escape(label)}"
                )

    def test_summary_shows_s3_access_mode(self):
        for use_iam_role, label in (
            (True, "IAM role (IRSA / instance profile)"),
            (False, "static access keys"),
        ):
            with self.subTest(use_iam_role=use_iam_role):
                config = PlatformConfig(
                    cloud_provider=CloudProvider.AWS,
                    domain="guardian.example.com",
                    environment="staging",
                    auth_provider=AuthProvider.KEYCLOAK,
                    aws_s3_use_iam_role=use_iam_role,
                )
                with console.capture() as capture:
                    show_config_summary(config)
                self.assertIn("AWS S3 Access", capture.get())
                self.assertIn(label, capture.get())

    def test_bootstrap_step_creates_the_namespace(self):
        config = PlatformConfig(
            cloud_provider=CloudProvider.GCP,
            domain="guardian.example.com",
            environment="staging",
            auth_provider=AuthProvider.KEYCLOAK,
        )
        configure_artifacts(config, "cloudsmith")
        with console.capture() as capture:
            show_next_steps(
                config,
                Path("values.yaml"),
                Path("secrets.yaml"),
                Path("bootstrap.yaml"),
            )
        output = capture.get()
        self.assertIn("./charts/keycloak-bootstrap", output)
        self.assertIn("-n guardian --create-namespace --wait", output)
        self.assertIn("not published to Cloudsmith", output)

    def test_summary_labels_a_custom_registry(self):
        config = PlatformConfig(
            cloud_provider=CloudProvider.GCP,
            domain="guardian.example.com",
            environment="staging",
            auth_provider=AuthProvider.KEYCLOAK,
        )
        configure_artifacts(config, "cloudsmith")
        config.image_registry_url = "mirror.example.com"
        config.image_repository_prefix = "mirror.example.com/eqtylab"
        with console.capture() as capture:
            show_config_summary(config)
        self.assertIn("custom registry (cloudsmith image tags)", capture.get())


if __name__ == "__main__":
    unittest.main()
