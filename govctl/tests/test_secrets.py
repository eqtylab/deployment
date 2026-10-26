"""Generated secrets have the requested length and the right gateway DSN."""

from pathlib import Path
import sys
import unittest

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from govctl.core.models import (
    PlatformConfig,
    CloudProvider,
    AuthProvider,
    DatabaseMode,
)
from govctl.generators.secrets import _generate_secret, generate_secrets


class GatewayDsnTests(unittest.TestCase):
    def gateway_dsn(self, database_mode):
        config = PlatformConfig(
            cloud_provider=CloudProvider.GCP,
            auth_provider=AuthProvider.KEYCLOAK,
            domain="customer.example.com",
            environment="production",
            database_mode=database_mode,
        )
        secrets = yaml.safe_load(generate_secrets(config))
        return secrets["global"]["secrets"]["database"]["values"]["gatewayDsn"]

    def test_external_database_gateway_dsn_requires_tls(self):
        dsn = self.gateway_dsn(DatabaseMode.EXTERNAL)
        self.assertTrue(dsn.endswith("/guardian_gateway?sslmode=require"), dsn)

    def test_bundled_database_gateway_dsn_disables_tls(self):
        dsn = self.gateway_dsn(DatabaseMode.BUNDLED)
        self.assertTrue(dsn.endswith("/guardian_gateway?sslmode=disable"), dsn)

    def test_bundled_database_gateway_dsn_targets_the_guardian_platform_postgresql(
        self,
    ):
        dsn = self.gateway_dsn(DatabaseMode.BUNDLED)
        self.assertIn("@guardian-platform-postgresql:5432/", dsn)


class GenerateSecretTests(unittest.TestCase):
    def test_length_is_a_character_count(self):
        for length in (1, 16, 32, 43, 44, 64):
            with self.subTest(length=length):
                self.assertEqual(len(_generate_secret(length)), length)

    def test_default_secret_is_44_base64_characters(self):
        secret = _generate_secret()
        self.assertEqual(len(secret), 44)
        self.assertRegex(secret, r"^[A-Za-z0-9+/]+$")


if __name__ == "__main__":
    unittest.main()
