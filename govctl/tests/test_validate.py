"""Input validators accept valid values and reject malformed ones."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from govctl.utils.validate import (
    is_valid_aws_region,
    is_valid_domain,
    is_valid_email,
    is_valid_environment,
    is_valid_gcp_key_ring_id,
    is_valid_gcp_location,
    is_valid_gcp_project_id,
    is_valid_https_url,
    is_valid_keyvault_url,
    is_valid_realm,
    is_valid_registry_host,
    is_valid_uuid,
)

CASES = {
    is_valid_domain: (
        ["guardian.example.com", "a.io", "x-1.example.co.uk"],
        ["", "localhost", "-a.com", "a-.b.com", "a.-b.com", "a b.com", "a.c"],
    ),
    is_valid_registry_host: (
        ["ghcr.io", "registry.example.com:5000", "mirror.example.com:443"],
        [
            "registry.example.com:0",
            "registry.example.com:abc",
            "registry.example.com:65536",
            "registry.example.com:²",
            "ghcr.io:",
            "ghcr.io:5000:1",
            "reg:5000",
            "a b.io",
        ],
    ),
    is_valid_environment: (
        ["development", "dev", "staging", "production", "prod-eu-1", "a"],
        ["", "Production", "My Env/x", "-dev", "dev-", "dev_1", "a" * 64],
    ),
    is_valid_keyvault_url: (
        [
            "https://guardian.vault.azure.net/",
            "https://guardian.vault.azure.net",
            "https://guardian.vault.azure.cn/",
            "https://guardian.vault.usgovcloudapi.net/",
            "https://guardian.vault.microsoftazure.de/",
        ],
        [
            "http://guardian.vault.azure.net/",
            "https://guardian.vault.example.com/",
            "https://ab.vault.azure.net/",
        ],
    ),
    is_valid_aws_region: (
        ["us-east-1", "eu-west-2", "ap-southeast-1", "us-gov-west-1", "cn-north-1"],
        ["", "us-east", "useast1", "US-EAST-1"],
    ),
    is_valid_gcp_location: (
        ["us-east1", "europe-west4", "northamerica-northeast1", "global"]
        + ["us", "europe", "asia", "nam4", "eur4", "nam-eur-asia1"],
        ["", "US", "us_east1", "us-east"],
    ),
    is_valid_gcp_project_id: (
        ["guardian-prod", "abcdef"],
        ["", "abc", "Guardian-prod", "1guardian", "guardian-"],
    ),
    is_valid_gcp_key_ring_id: (["eqtylab-did", "ring_1"], ["", "ring 1"]),
    is_valid_uuid: (
        ["123e4567-e89b-12d3-a456-426614174000"],
        ["", "123e4567e89b12d3a456426614174000"],
    ),
    is_valid_https_url: (
        ["https://guardian.example.com", "https://auth.example.com/keycloak"],
        ["http://guardian.example.com", "guardian.example.com"],
    ),
    is_valid_realm: (["guardian", "guardian_1-a"], ["", "guardian realm"]),
    is_valid_email: (["admin@example.com"], ["", "admin", "admin@example"]),
}


class ValidatorTests(unittest.TestCase):
    def test_validators(self):
        for validator, (valid, invalid) in CASES.items():
            for value in valid:
                with self.subTest(validator=validator.__name__, value=value):
                    self.assertTrue(validator(value))
            for value in invalid:
                with self.subTest(validator=validator.__name__, value=value):
                    self.assertFalse(validator(value))


if __name__ == "__main__":
    unittest.main()
