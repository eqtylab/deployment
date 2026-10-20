"""Generated gateway DSN uses the right sslmode for each database mode."""

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
from govctl.generators.secrets import generate_secrets


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


if __name__ == "__main__":
    unittest.main()
