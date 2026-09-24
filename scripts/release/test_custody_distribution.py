"""Cluster-free regressions for manifests and the actual packaging workflow."""

import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

import jsonschema
import yaml
from custody_distribution import (
    OCI,
    OPERATOR_FILES,
    ROOT,
    custody_version,
    describe_failure,
    read_yaml,
    required_chart_files,
    stage_operator_files,
    verify_package,
)

SCHEMA = json.loads((ROOT / "schemas/release-manifest.schema.json").read_text())
SELECTED = {"name": "openbao-custody", "version": "0.1.0", "oci": OCI}


def manifest_paths():
    return sorted((ROOT / "releases").glob("v*/release-manifest.yaml"))


def release_order(path):
    """Newest stable last: numeric parts, then stable ahead of any pre-release."""
    match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)(-.+)?", path.parent.name)
    if not match:
        raise ValueError(f"unexpected release directory {path.parent.name}")
    major, minor, patch, prerelease = match.groups()
    return (int(major), int(minor), int(patch), prerelease is None, prerelease or "")


def latest_manifest():
    """The newest released manifest, so fixtures follow the current manifest shape."""
    return read_yaml(max(manifest_paths(), key=release_order))


class ManifestTests(unittest.TestCase):
    def test_every_historical_manifest_remains_external_only(self):
        manifests = manifest_paths()
        self.assertGreater(len(manifests), 0)
        for path in manifests:
            with self.subTest(manifest=path.parent.name):
                manifest = read_yaml(path)
                jsonschema.validate(manifest, SCHEMA)
                # No shipped release selected supplied custody; a later manifest
                # that does must be a deliberate new entry, not a drift here.
                self.assertNotIn("openbaoCustody", manifest["charts"])
                self.assertIsNone(custody_version(manifest, ROOT))

    def test_release_order_places_prereleases_before_their_stable_release(self):
        names = [
            path.parent.name for path in sorted(manifest_paths(), key=release_order)
        ]
        self.assertEqual(names.index("v1.0.0-rc.3") + 1, names.index("v1.0.0"))
        self.assertEqual(
            latest_manifest()["platform"]["version"], names[-1].removeprefix("v")
        )

    def test_opt_in_uses_independent_version(self):
        manifest = latest_manifest()
        manifest["charts"]["openbaoCustody"] = SELECTED.copy()
        jsonschema.validate(manifest, SCHEMA)
        self.assertEqual(custody_version(manifest, ROOT), "0.1.0")
        self.assertNotEqual(custody_version(manifest), manifest["platform"]["version"])

    def test_malformed_entry_cannot_silently_exclude_custody(self):
        for entry in (
            None,
            {},
            "external",
            {**SELECTED, "name": "wrong"},
            {**SELECTED, "version": ""},
            {**SELECTED, "version": "../../escape"},
            {**SELECTED, "oci": "oci://other.example/custody"},
        ):
            with self.subTest(entry=entry):
                manifest = latest_manifest()
                manifest["charts"]["openbaoCustody"] = entry
                with self.assertRaises(jsonschema.ValidationError):
                    jsonschema.validate(manifest, SCHEMA)
                with self.assertRaises(ValueError):
                    custody_version(manifest, ROOT)

    def test_historical_version_valid_but_cannot_package_current_source(self):
        manifest = {"charts": {"openbaoCustody": {**SELECTED, "version": "0.0.1"}}}
        self.assertEqual(custody_version(manifest), "0.0.1")
        with self.assertRaisesRegex(ValueError, "source chart"):
            custody_version(manifest, ROOT)


class PackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workflow = read_yaml(ROOT / ".github/workflows/release-platform-package.yaml")
        cls.steps = {
            step["name"]: step for step in workflow["jobs"]["release"]["steps"]
        }

    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix="custody-delivery-test-")
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.manifest = latest_manifest()
        self.manifest["platform"]["version"] = "9.8.7"
        self.manifest["validation"]["evidence"] = {
            "status": "pending",
            "recordedIn": "synthetic packaging test only",
        }
        # Tiny platform chart fixtures exercise the exact workflow shell without
        # downloading unrelated dependencies or claiming platform qualification.
        for chart in self.manifest["charts"].values():
            chart["version"] = "9.8.7"
            directory = self.root / "charts" / chart["name"]
            directory.mkdir(parents=True)
            (directory / "Chart.yaml").write_text(
                yaml.safe_dump(
                    {
                        "apiVersion": "v2",
                        "name": chart["name"],
                        "version": "9.8.7",
                        "appVersion": "9.8.7",
                    }
                )
            )
        examples = self.root / "charts/governance-platform/examples"
        examples.mkdir()
        (examples / "values.yaml").write_text("{}\n")
        shutil.copy2(ROOT / "charts/governance-platform/examples/values-cloudsmith.yaml", examples)
        shutil.copytree(
            ROOT / "charts/openbao-custody", self.root / "charts/openbao-custody"
        )
        for name in (
            *OPERATOR_FILES,
            "docs/openbao-delivery.md",
            "scripts/release/custody_distribution.py",
        ):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        self.env = {
            **os.environ,
            "PATH": str(Path(sys.executable).parent) + os.pathsep + os.environ["PATH"],
            "VERSION": "9.8.7",
            "MANIFEST": "release-manifest.yaml",
            "PUBLISH": "false",
            "BUILD_AIRGAP": "false",
            "GITHUB_OUTPUT": str(self.root / "outputs"),
            "CUSTODY_VERSION": "",
        }

    def run_step(self, name, success=True):
        result = subprocess.run(
            [
                "bash",
                "--noprofile",
                "--norc",
                "-e",
                "-o",
                "pipefail",
                "-c",
                self.steps[name]["run"],
            ],
            cwd=self.root,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def assemble(self, supplied):
        if supplied:
            self.manifest["charts"]["openbaoCustody"] = SELECTED.copy()
        (self.root / "release-manifest.yaml").write_text(yaml.safe_dump(self.manifest))
        self.run_step("Resolve optional custody release")
        output = (self.root / "outputs").read_text().strip()
        self.assertEqual(output, "version=0.1.0" if supplied else "version=")
        self.env["CUSTODY_VERSION"] = output.removeprefix("version=")
        self.run_step("Publish platform charts")  # PUBLISH=false: real local Helm only.
        self.run_step("Build connected customer package")
        extracted = self.root / "extracted"
        extracted.mkdir()
        with tarfile.open(
            self.root / "dist/governance-platform-v9.8.7.tar.gz"
        ) as archive:
            archive.extractall(extracted, filter="data")
        return extracted / "governance-platform-v9.8.7"

    def test_old_manifest_package_excludes_custody_but_keeps_operator_files(self):
        package = self.assemble(supplied=False)
        verify_package(self.root, package)
        self.assertFalse(list((package / "charts").glob("openbao-custody-*.tgz")))
        for name in OPERATOR_FILES:
            self.assertEqual((package / name).read_bytes(), (ROOT / name).read_bytes())

    def test_supplied_archive_uses_own_version_and_renders_after_extraction(self):
        package = self.assemble(supplied=True)
        verify_package(self.root, package)
        digests = read_yaml(package / "chart-digests.yaml")["charts"]
        self.assertEqual(digests["openbao-custody"]["version"], "0.1.0")
        self.assertEqual(digests["openbao-custody"]["ociDigest"], "dry-run")
        self.assertEqual(digests["governance-platform"]["version"], "9.8.7")
        self.assertTrue((package / "charts/openbao-custody-0.1.0.tgz").is_file())
        self.assertFalse((package / "charts/openbao-custody-9.8.7.tgz").exists())

        # The policy is owned upstream and synced; the package must carry the
        # source tree's bytes exactly rather than any content asserted here.
        policy = package / "scripts/openbao/policies/guardian-auth.hcl"
        self.assertEqual(
            policy.read_bytes(),
            (ROOT / "scripts/openbao/policies/guardian-auth.hcl").read_bytes(),
        )
        with tarfile.open(package / "charts/openbao-custody-0.1.0.tgz") as archive:
            names = set(archive.getnames())
        for name in required_chart_files(ROOT):
            self.assertIn("openbao-custody/" + name, names)
        self.assertTrue(
            any(name.startswith("examples/") for name in required_chart_files(ROOT))
        )

        (package / "scripts/helpers/output.sh").unlink()
        with self.assertRaisesRegex(ValueError, "missing or changed operator file"):
            verify_package(self.root, package)
        stage_operator_files(self.root, package)
        (package / "scripts/openbao/policies/guardian-auth.hcl").write_text(
            "# incomplete policy\n"
        )
        with self.assertRaisesRegex(ValueError, "operator file"):
            verify_package(self.root, package)
        stage_operator_files(self.root, package)

        digests["openbao-custody"]["version"] = "9.8.7"
        (package / "chart-digests.yaml").write_text(yaml.safe_dump({"charts": digests}))
        with self.assertRaisesRegex(ValueError, "metadata/checksum"):
            verify_package(self.root, package)
        self.manifest["charts"].pop("openbaoCustody")
        (package / "release-manifest.yaml").write_text(yaml.safe_dump(self.manifest))
        with self.assertRaisesRegex(ValueError, "external-only"):
            verify_package(self.root, package)

    def test_supplied_airgap_refused_before_publication(self):
        self.manifest["charts"]["openbaoCustody"] = SELECTED.copy()
        (self.root / "release-manifest.yaml").write_text(yaml.safe_dump(self.manifest))
        self.env["BUILD_AIRGAP"] = "true"
        result = self.run_step("Resolve optional custody release", success=False)
        self.assertIn("connected-only", result.stdout)
        self.assertFalse((self.root / "dist").exists())

    def test_reused_archive_checks_payload_even_with_recomputed_checksum(self):
        package = self.assemble(supplied=True)
        archive = package / "charts/openbao-custody-0.1.0.tgz"
        original = archive.read_bytes()
        # Identical immutable content repackaged at another time is accepted.
        # Changed values/templates must fail even with self-consistent metadata.
        for changed in (None, "values.yaml", "templates/_helpers.tpl"):
            with self.subTest(changed=changed):
                with (
                    tarfile.open(fileobj=io.BytesIO(original)) as old,
                    tarfile.open(archive, "w:gz") as new,
                ):
                    for member in old.getmembers():
                        data = (
                            old.extractfile(member).read() if member.isfile() else None
                        )
                        member.mtime += 10
                        if member.name == "openbao-custody/" + str(changed):
                            data += b"\n# changed archive payload\n"
                            member.size = len(data)
                        new.addfile(
                            member, io.BytesIO(data) if data is not None else None
                        )
                digests = read_yaml(package / "chart-digests.yaml")
                digests["charts"]["openbao-custody"]["packageSha256"] = hashlib.sha256(
                    archive.read_bytes()
                ).hexdigest()
                (package / "chart-digests.yaml").write_text(yaml.safe_dump(digests))
                if changed is None:
                    verify_package(self.root, package)
                else:
                    with self.assertRaisesRegex(ValueError, "payload differs"):
                        verify_package(self.root, package)

    def test_subprocess_failures_keep_their_stderr(self):
        error = subprocess.CalledProcessError(
            3, ["helm", "package"], stderr=b"Error: bad chart\n"
        )
        self.assertIn("Error: bad chart", describe_failure(error))
        self.assertIn("exit status 3", describe_failure(error))
        self.assertEqual(
            describe_failure(subprocess.CalledProcessError(1, ["x"])),
            str(subprocess.CalledProcessError(1, ["x"])),
        )
        package = self.assemble(supplied=True)
        # Byte comparison against the (synthetic) source tree runs first, so the
        # failing script must be the source's script as well as the packaged copy.
        failing = "#!/usr/bin/env bash\necho 'synthetic operator failure' >&2\nexit 7\n"
        for root in (self.root, package):
            (root / "scripts/openbao/configure-auth.sh").write_text(failing)
        with self.assertRaises(subprocess.CalledProcessError) as raised:
            verify_package(self.root, package)
        self.assertIn("synthetic operator failure", describe_failure(raised.exception))

    def test_stale_custody_version_refused_before_packaging(self):
        self.manifest["charts"]["openbaoCustody"] = {**SELECTED, "version": "0.0.1"}
        (self.root / "release-manifest.yaml").write_text(yaml.safe_dump(self.manifest))
        self.run_step("Resolve optional custody release", success=False)
        self.assertFalse((self.root / "dist").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
