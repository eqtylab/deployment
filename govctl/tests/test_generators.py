"""Values and bootstrap generators mark operator input and follow the configuration."""

from pathlib import Path
import sys
import unittest

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from govctl.cli.commands.init import BOOTSTRAP_GENERATORS
from govctl.core.artifacts import configure_artifacts
from govctl.core.models import (
    CLOUD_TO_KEY_MANAGEMENT,
    AuthProvider,
    CloudProvider,
    DatabaseMode,
    PlatformConfig,
)
from govctl.generators.auth0_bootstrap import generate_auth0_bootstrap
from govctl.generators.entra_bootstrap import generate_entra_bootstrap
from govctl.generators.keycloak_bootstrap import generate_keycloak_bootstrap
from govctl.generators.secrets import generate_secrets
from govctl.generators.values import generate_values
from govctl.utils.yaml import dump_yaml, optional, required


def config(
    cloud=CloudProvider.GCP,
    auth=AuthProvider.KEYCLOAK,
    environment="staging",
    **kwargs,
):
    result = PlatformConfig(
        cloud_provider=cloud,
        auth_provider=auth,
        domain="guardian.example.com",
        environment=environment,
        key_management_provider=CLOUD_TO_KEY_MANAGEMENT[cloud],
        **kwargs,
    )
    configure_artifacts(result, "cloudsmith")
    return result


class MarkerTests(unittest.TestCase):
    def test_long_labels_are_not_folded(self):
        label = "A very long label " * 20 + "with it's apostrophe"
        output = dump_yaml({"a": {"b": {"c": required(label), "d": optional(label)}}})
        self.assertNotIn("__REQUIRED__", output)
        self.assertNotIn("__OPTIONAL__", output)
        self.assertIn(f"c: ''  # REQUIRED: {label}\n", output)
        self.assertIn(f"d: ''  # OPTIONAL: {label}\n", output)
        self.assertEqual(yaml.safe_load(output)["a"]["b"], {"c": "", "d": ""})

    def test_no_marker_leaks_for_any_combination(self):
        for cloud in CloudProvider:
            for auth in AuthProvider:
                for mode in DatabaseMode:
                    with self.subTest(cloud=cloud, auth=auth, mode=mode):
                        c = config(cloud, auth, database_mode=mode)
                        for output in (
                            generate_values(c),
                            generate_secrets(c),
                            BOOTSTRAP_GENERATORS[auth](c),
                        ):
                            self.assertNotIn("__REQUIRED__", output)
                            self.assertNotIn("__OPTIONAL__", output)
                            yaml.safe_load(output)


class ValuesTests(unittest.TestCase):
    def test_values_that_the_charts_require_are_marked(self):
        cases = [
            (
                config(CloudProvider.GCP),
                "projectId: ''  # REQUIRED: GCP KMS project ID",
            ),
            (
                config(CloudProvider.GCP),
                "locationId: ''  # REQUIRED: GCP KMS location",
            ),
            (
                config(auth=AuthProvider.ENTRA),
                "platformAdminEmail: ''  # REQUIRED: Platform admin email",
            ),
            (
                config(auth=AuthProvider.AUTH0),
                "  domain: ''  # REQUIRED: Auth0 tenant domain",
            ),
            (
                config(database_mode=DatabaseMode.EXTERNAL),
                "host: ''  # REQUIRED: Managed PostgreSQL host",
            ),
        ]
        for c, line in cases:
            with self.subTest(line=line):
                self.assertIn(line, generate_values(c))

    def test_supplied_values_replace_the_markers(self):
        c = config(
            auth=AuthProvider.ENTRA,
            gcp_kms_project_id="guardian-prod",
            gcp_kms_location_id="us",
            entra_tenant_id="123e4567-e89b-12d3-a456-426614174000",
        )
        values = yaml.safe_load(generate_values(c))
        gcp_kms = values["auth-service"]["config"]["keyManagement"]["gcp_kms"]
        self.assertEqual(gcp_kms["projectId"], "guardian-prod")
        self.assertEqual(gcp_kms["locationId"], "us")
        self.assertEqual(values["entra"]["tenantId"], c.entra_tenant_id)
        self.assertEqual(
            values["governance-service"]["config"]["entraTenantId"], c.entra_tenant_id
        )

    def test_unknown_entra_tenant_falls_back_to_the_secret(self):
        values = yaml.safe_load(generate_values(config(auth=AuthProvider.ENTRA)))
        self.assertNotIn("tenantId", values["entra"])
        self.assertNotIn("entraTenantId", values["governance-service"]["config"])

    def test_governance_log_level_uses_the_chart_default(self):
        values = yaml.safe_load(generate_values(config()))
        self.assertNotIn("logLevel", values["governance-service"]["config"])

    def test_auth0_verifies_the_issuer(self):
        values = yaml.safe_load(generate_values(config(auth=AuthProvider.AUTH0)))
        self.assertFalse(
            values["auth-service"]["config"]["idp"]["skipIssuerVerification"]
        )

    def test_keycloak_url_is_used_by_the_hook_and_issuer(self):
        c = config(keycloak_url="https://auth.example.com/keycloak/")
        values = yaml.safe_load(generate_values(c))
        self.assertEqual(values["keycloak"]["url"], "https://auth.example.com/keycloak")
        self.assertEqual(
            values["auth-service"]["config"]["idp"]["issuer"],
            "https://auth.example.com/keycloak/realms/guardian",
        )

    def test_keycloak_hook_keeps_the_chart_default_without_a_url(self):
        values = yaml.safe_load(generate_values(config()))
        self.assertNotIn("url", values["keycloak"])


class SecretsTests(unittest.TestCase):
    def test_gcp_kms_service_account_is_optional(self):
        secrets = generate_secrets(config(CloudProvider.GCP))
        self.assertIn("serviceAccountJson: ''  # OPTIONAL:", secrets)
        self.assertIn("Workload Identity", secrets)

    def test_bundled_gateway_dsn_notes_the_release_name(self):
        secrets = generate_secrets(config())
        dsn_line = next(l for l in secrets.splitlines() if "gatewayDsn:" in l)
        self.assertIn("# Host assumes Helm release name guardian-platform", dsn_line)
        self.assertTrue(
            yaml.safe_load(secrets)["global"]["secrets"]["database"]["values"][
                "gatewayDsn"
            ].endswith("?sslmode=disable")
        )


class BootstrapTests(unittest.TestCase):
    def frontend_urls(self, c):
        auth0 = yaml.safe_load(generate_auth0_bootstrap(c))["applications"]["frontend"]
        entra = yaml.safe_load(generate_entra_bootstrap(c))["apps"]["frontend"]
        keycloak = yaml.safe_load(generate_keycloak_bootstrap(c))["clients"]["frontend"]
        return [
            *auth0["callbacks"],
            *auth0["logoutUrls"],
            *auth0["webOrigins"],
            *entra["redirectUris"],
            *keycloak["redirectUris"],
            *keycloak["webOrigins"],
        ]

    def test_localhost_is_only_allowed_in_development(self):
        for environment, expected in (
            ("development", True),
            ("dev", True),
            ("staging", False),
            ("production", False),
        ):
            with self.subTest(environment=environment):
                urls = self.frontend_urls(config(environment=environment))
                self.assertEqual(
                    any("localhost" in url for url in urls), expected, urls
                )
                self.assertIn("https://guardian.example.com", urls)

    def test_keycloak_bootstrap_url(self):
        default = yaml.safe_load(generate_keycloak_bootstrap(config()))
        self.assertEqual(default["keycloak"]["url"], "http://keycloak:8080/keycloak")
        custom = yaml.safe_load(
            generate_keycloak_bootstrap(
                config(keycloak_url="https://auth.example.com/keycloak/")
            )
        )
        self.assertEqual(custom["keycloak"]["url"], "https://auth.example.com/keycloak")
        self.assertEqual(custom["keycloak"]["realm"]["name"], "guardian")

    def test_auth0_bootstrap(self):
        c = config(auth=AuthProvider.AUTH0, auth0_domain="tenant.us.auth0.com")
        bootstrap = yaml.safe_load(generate_auth0_bootstrap(c))
        self.assertEqual(bootstrap["auth0"]["domain"], "tenant.us.auth0.com")
        self.assertEqual(
            bootstrap["auth0"]["api"]["identifier"], "https://guardian.example.com"
        )
        self.assertEqual(
            bootstrap["users"]["admin"]["email"], "admin@guardian.example.com"
        )
        self.assertEqual(len(bootstrap["scopes"]), 8)

    def test_entra_bootstrap(self):
        placeholder = yaml.safe_load(generate_entra_bootstrap(config()))
        self.assertEqual(placeholder["entra"]["tenantId"], "YOUR_ENTRA_TENANT_ID")
        tenant = "123e4567-e89b-12d3-a456-426614174000"
        bootstrap = yaml.safe_load(
            generate_entra_bootstrap(config(entra_tenant_id=tenant))
        )
        self.assertEqual(bootstrap["entra"]["tenantId"], tenant)
        self.assertNotIn("domain", bootstrap["entra"])
        self.assertIn(
            "https://guardian.example.com",
            bootstrap["apps"]["frontend"]["redirectUris"],
        )


if __name__ == "__main__":
    unittest.main()
