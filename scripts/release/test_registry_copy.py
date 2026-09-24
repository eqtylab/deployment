"""Opt-in transport test against two disposable localhost registries only."""

import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import uuid

import cloudsmith_release as source
import publish_cloudsmith as publisher


@unittest.skipUnless(
    os.environ.get("CLOUDSMITH_LOCAL_REGISTRY_TEST") == "1",
    "requires disposable localhost registries on 15381 and 15382",
)
class RegistryCopyTests(unittest.TestCase):
    def test_index_referrers_legacy_attachments_and_partial_retry(self):
        repository = "mirror-test-" + uuid.uuid4().hex
        original = f"localhost:15381/{repository}"
        mirror = f"localhost:15382/{repository}"
        command = source.run

        def local_run(args, **kwargs):
            # Production always uses TLS. The override exists only in this test.
            if args[0] == "oras":
                args = args + (
                    ["--from-plain-http", "--to-plain-http"]
                    if args[1] == "cp"
                    else ["--plain-http"]
                )
            return command(args, **kwargs)

        with (
            tempfile.TemporaryDirectory() as work,
            patch.object(source, "run", side_effect=local_run),
            patch.object(publisher, "run", side_effect=local_run),
        ):
            directory = Path(work)
            for architecture in ("amd64", "arm64"):
                config = directory / f"{architecture}.json"
                config.write_text(
                    json.dumps(
                        {
                            "architecture": architecture,
                            "os": "linux",
                            "rootfs": {"type": "layers", "diff_ids": []},
                        }
                    )
                )
                local_run(
                    [
                        "oras",
                        "push",
                        f"{original}:linux-{architecture}",
                        "--config",
                        f"{config}:application/vnd.oci.image.config.v1+json",
                    ]
                )
            local_run(
                [
                    "oras",
                    "manifest",
                    "index",
                    "create",
                    original + ":1.2.3",
                    "linux-amd64",
                    "linux-arm64",
                ]
            )
            digest = source.resolve(original + ":1.2.3")
            evidence = directory / "evidence.json"
            evidence.write_text('{"fixture":"local-only provenance bytes"}')
            local_run(
                [
                    "oras",
                    "attach",
                    "--artifact-type",
                    "application/vnd.eqty.test+json",
                    original + "@" + digest,
                    "evidence.json",
                ],
                cwd=directory,
            )
            attached = source.referrers(original + "@" + digest)
            self.assertEqual(len(attached), 1)
            # Simulate interruption after copying the index but before attachments.
            local_run(["oras", "cp", original + "@" + digest, mirror + ":1.2.3"])
            publisher.copy_oci(original + "@" + digest, mirror + ":1.2.3", digest)
            self.assertEqual(source.resolve(mirror + ":1.2.3"), digest)
            self.assertEqual(source.referrers(mirror + ":1.2.3"), attached)
            index = json.loads(
                local_run(["oras", "manifest", "fetch", mirror + ":1.2.3"])
            )
            self.assertEqual(len(index["manifests"]), 2)
            for item in index["manifests"]:
                self.assertEqual(
                    source.resolve(mirror + "@" + item["digest"]), item["digest"]
                )
            # Cosign 2.x uses these independent tags rather than OCI referrers.
            for suffix in ("sig", "att", "sbom"):
                tag = digest.replace(":", "-") + "." + suffix
                local_run(
                    ["oras", "push", original + ":" + tag, "evidence.json"],
                    cwd=directory,
                )
                evidence_digest = source.resolve(original + ":" + tag)
                publisher.copy_oci(
                    original + "@" + evidence_digest,
                    mirror + ":" + tag,
                    evidence_digest,
                )
                self.assertEqual(source.resolve(mirror + ":" + tag), evidence_digest)
            # Retry is idempotent and a conflicting existing tag is rejected.
            publisher.copy_oci(original + "@" + digest, mirror + ":1.2.3", digest)
            with self.assertRaisesRegex(ValueError, "Conflicting"):
                publisher.copy_oci(original + "@" + digest, mirror + ":" + tag, digest)


if __name__ == "__main__":
    unittest.main()
