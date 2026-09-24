"""Customer and internal registry profiles generate consistent Helm inputs."""

from pathlib import Path
import sys
import tempfile
import unittest

from click.testing import CliRunner
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from govctl.cli.commands.init import init_cmd
from govctl.core.artifacts import configure_artifacts
from govctl.core.models import (
    PlatformConfig,
    CloudProvider,
    AuthProvider,
    KeyManagementProvider,
)
from govctl.generators.values import generate_values
from govctl.generators.secrets import generate_secrets


class ArtifactProfileTests(unittest.TestCase):
    def config(self):
        return PlatformConfig(
            cloud_provider=CloudProvider.GCP,
            auth_provider=AuthProvider.KEYCLOAK,
            domain="customer.example.com",
            environment="production",
        )

    def test_cloudsmith_profile_aligns_prefix_host_and_entitlement_username(self):
        config = self.config()
        configure_artifacts(config, "cloudsmith")
        values = yaml.safe_load(generate_values(config))
        secrets = generate_secrets(config)
        credentials = yaml.safe_load(secrets)["global"]["secrets"]["imageRegistry"]
        self.assertEqual(
            values["global"]["imageRepositoryPrefixOverride"],
            "docker.cloudsmith.io/eqtylab/prod",
        )
        self.assertEqual(credentials["registry"], "docker.cloudsmith.io")
        self.assertEqual(credentials["values"]["username"], "eqtylab/prod")
        self.assertEqual(credentials["values"]["password"], "")
        self.assertIn(
            "password: ''  # REQUIRED: Cloudsmith prod entitlement token", secrets
        )

    def test_required_secrets_are_empty_for_all_providers_and_sources(self):
        for auth in AuthProvider:
            for cloud in CloudProvider:
                for source in ("cloudsmith", "github"):
                    with self.subTest(auth=auth, cloud=cloud, source=source):
                        config = self.config()
                        config.auth_provider = auth
                        config.cloud_provider = cloud
                        config.key_management_provider = {
                            CloudProvider.AWS: KeyManagementProvider.AWS_KMS,
                            CloudProvider.AZURE: KeyManagementProvider.AZURE_KEY_VAULT,
                            CloudProvider.GCP: KeyManagementProvider.GCP_KMS,
                        }[cloud]
                        configure_artifacts(config, source)
                        secrets = generate_secrets(config)
                        self.assertNotIn("__REQUIRED__", secrets)
                        self.assertEqual(
                            yaml.safe_load(secrets)["global"]["secrets"][
                                "imageRegistry"
                            ]["values"]["password"],
                            "",
                        )
                        if source == "github":
                            self.assertIn(
                                "GitHub PAT with read:packages scope", secrets
                            )

    def test_cloudsmith_inherits_all_eight_released_image_versions(self):
        def images(value):
            if isinstance(value, dict):
                if "image" in value:
                    yield value["image"]
                for child in value.values():
                    yield from images(child)

        config = self.config()
        for source in ("cloudsmith", "github"):
            configure_artifacts(config, source)
            overrides = list(images(yaml.safe_load(generate_values(config))))
            self.assertEqual(len(overrides), 8)
            for image in overrides:
                if source == "cloudsmith":
                    self.assertNotIn("tag", image)
                    self.assertNotIn("digest", image)
                    self.assertNotIn("repository", image)
                else:
                    self.assertEqual(image["tag"], "latest")

    def test_internal_profile_and_direct_callers_keep_ghcr(self):
        config = self.config()
        for configure in (False, True):
            if configure:
                configure_artifacts(config, "cloudsmith")
                configure_artifacts(config, "github")
            values = yaml.safe_load(generate_values(config))
            self.assertNotIn("imageRepositoryPrefixOverride", values["global"])
            self.assertEqual(config.image_registry_url, "ghcr.io")
            self.assertEqual(config.image_registry_username, "")

    def test_custom_registry_values_are_retained(self):
        config = self.config()
        configure_artifacts(config, "cloudsmith")
        config.image_registry_url = "mirror.customer.example"
        config.image_repository_prefix = "mirror.customer.example/eqty"
        config.image_registry_username = "customer"
        values = yaml.safe_load(generate_values(config))
        credentials = yaml.safe_load(generate_secrets(config))["global"]["secrets"][
            "imageRegistry"
        ]
        self.assertEqual(
            values["global"]["imageRepositoryPrefixOverride"],
            config.image_repository_prefix,
        )
        self.assertEqual(credentials["registry"], config.image_registry_url)

    def test_cli_defaults_to_customer_and_supports_explicit_internal_choice(self):
        for options, host in (
            ([], "docker.cloudsmith.io"),
            (["--artifact-source", "github"], "ghcr.io"),
        ):
            with self.subTest(host=host), tempfile.TemporaryDirectory() as out:
                result = CliRunner().invoke(
                    init_cmd,
                    [
                        "--no-interactive",
                        "--cloud",
                        "gcp",
                        "--domain",
                        "customer.example.com",
                        "--environment",
                        "production",
                        "--auth",
                        "keycloak",
                        "--output",
                        out,
                        *options,
                    ],
                )
                self.assertEqual(
                    result.exit_code, 0, result.output + str(result.exception or "")
                )
                credentials = yaml.safe_load(
                    (Path(out) / "secrets-production.yaml").read_text()
                )["global"]["secrets"]["imageRegistry"]
                self.assertEqual(credentials["registry"], host)
                if host == "docker.cloudsmith.io":
                    self.assertIn("helm.oci.cloudsmith.io", result.output)


if __name__ == "__main__":
    unittest.main()
