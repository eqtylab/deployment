"""Render the same charts for customers and internal installations; no registry I/O."""

import json
import base64
from pathlib import Path
import subprocess
import unittest

import yaml

ROOT = next(
    p
    for p in Path(__file__).resolve().parents
    if (p / "charts/governance-platform/Chart.yaml").is_file()
)


class CloudsmithRenderTests(unittest.TestCase):
    def render(self, cloudsmith=False, secrets=False):
        args = [
            "helm",
            "template",
            "distribution-test",
            str(ROOT / "charts/governance-platform"),
            "--namespace",
            "governance",
            "--values",
            str(ROOT / "charts/governance-platform/examples/values-gateway.yaml"),
            "--set",
            "eqty-pdfgen.enabled=true",
            "--set-string",
            "auth-service.image.digest=sha256:" + "a" * 64,
            "--set-string",
            "gateway-stack.llmGateway.image.digest=sha256:" + "b" * 64,
        ]
        if secrets:
            args += [
                "--values",
                str(ROOT / "charts/governance-platform/examples/secrets-sample.yaml"),
            ]
            args += [
                "--set",
                "global.secrets.database.values.gatewayDsn=postgres://test:test@postgres/guardian?sslmode=disable",
            ]
        if cloudsmith:
            args += [
                "--values",
                str(
                    ROOT / "charts/governance-platform/examples/values-cloudsmith.yaml"
                ),
            ]
        result = subprocess.run(args, capture_output=True, text=True, check=True)
        return [d for d in yaml.safe_load_all(result.stdout) if d]

    def test_customer_prefix_preserves_internal_and_upstream_image_sources(self):
        def images(docs):
            found = {}

            def walk(value):
                if isinstance(value, dict):
                    if isinstance(value.get("image"), str):
                        found[value.get("name", "")] = value["image"]
                    for child in value.values():
                        walk(child)
                elif isinstance(value, list):
                    for child in value:
                        walk(child)

            walk(docs)
            return found

        internal, customer = images(self.render()), images(self.render(True))
        changed = set()
        for name, reference in internal.items():
            if reference.startswith("ghcr.io/eqtylab/"):
                self.assertEqual(
                    customer[name],
                    reference.replace(
                        "ghcr.io/eqtylab/", "docker.cloudsmith.io/eqtylab/prod/", 1
                    ),
                )
                changed.add(reference)
            else:
                self.assertEqual(customer[name], reference, name)
        self.assertEqual(len(changed), 8)

    def test_helm_managed_secret_has_cloudsmith_host_and_username(self):
        docs = self.render(True, True)
        secret = next(
            d
            for d in docs
            if d["kind"] == "Secret"
            and d["metadata"]["name"] == "platform-image-pull-secret"
        )
        config = json.loads(base64.b64decode(secret["data"][".dockerconfigjson"]))
        self.assertEqual(set(config["auths"]), {"docker.cloudsmith.io"})
        self.assertEqual(
            config["auths"]["docker.cloudsmith.io"]["username"], "eqtylab/prod"
        )


if __name__ == "__main__":
    unittest.main()
