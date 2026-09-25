"""Release boundaries and failure handling without live service credentials."""

import copy
from contextlib import ExitStack, redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import yaml

import cloudsmith_release as source
import publish_cloudsmith as publisher


def fixture(directory, custody=False):
    manifest = yaml.safe_load(
        (source.ROOT / "releases/v1.2.0/release-manifest.yaml").read_text()
    )
    if custody:
        manifest["charts"]["openbaoCustody"] = {
            "name": "openbao-custody",
            "version": "0.1.0",
            "oci": "oci://ghcr.io/eqtylab/charts/openbao-custody",
        }
    assets = directory / "assets"
    assets.mkdir()
    digests = {"charts": {}}
    members = {}
    for chart in manifest["charts"].values():
        package = f"{chart['name']}-{chart['version']}.tgz"
        data = (chart["name"] + " tested chart bytes").encode()
        import hashlib

        digests["charts"][chart["name"]] = {
            "version": chart["version"],
            "oci": chart["oci"],
            "package": package,
            "packageSha256": hashlib.sha256(data).hexdigest(),
            "ociDigest": "sha256:" + "c" * 64,
        }
        members["charts/" + package] = data
    for name, value in (
        ("release-manifest.yaml", manifest),
        ("chart-digests.yaml", digests),
    ):
        data = yaml.safe_dump(value).encode()
        (assets / name).write_bytes(data)
        members[name] = data
    archive = assets / "governance-platform-v1.2.0.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        for name, data in members.items():
            entry = tarfile.TarInfo("governance-platform-v1.2.0/" + name)
            entry.size = len(data)
            tar.addfile(entry, io.BytesIO(data))
    (assets / (archive.name + ".sha256")).write_text(
        source.sha256(archive) + "  dist/" + archive.name + "\n"
    )
    charts = source.unpack_charts(archive, manifest, digests, directory)
    images = source.image_entries(manifest)
    for image in images:
        image.update(attachments=[], referrers=[])
    files = [source.file_entry(p) for p in sorted(assets.iterdir())]
    inventory = {
        "schemaVersion": 2,
        "version": "1.2.0",
        "release": {
            "id": 42,
            "tag": "platform/v1.2.0",
            "commit": "a" * 40,
            "manifestSha256": source.sha256(assets / "release-manifest.yaml"),
        },
        "images": images,
        "charts": charts,
        "files": files,
    }
    source.write_json(directory / "inventory.json", inventory)
    data = {
        "id": 42,
        "tag_name": "platform/v1.2.0",
        "draft": False,
        "prerelease": False,
        "published_at": "2026-09-16T00:00:00Z",
        "assets": [
            {
                "id": i,
                "name": f["name"],
                "digest": "sha256:" + f["sha256"],
                "size": (directory / f["path"]).stat().st_size,
            }
            for i, f in enumerate(files)
        ],
    }
    return manifest, digests, inventory, data


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(redirect_stdout(io.StringIO()))
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.manifest, self.digests, self.inventory, self.data = fixture(
            self.work, custody=True
        )

    def test_completed_deliveries_cannot_be_republished(self):
        for data in (None, self.data):
            with patch.object(source, "api", return_value=data):
                source.check_publish("1.2.0")
        data = copy.deepcopy(self.data)
        data["assets"].append({"name": "cloudsmith-delivery.json"})
        with (
            patch.object(source, "api", return_value=data),
            self.assertRaisesRegex(ValueError, "completed Cloudsmith delivery"),
        ):
            source.check_publish("1.2.0")
        with (
            patch.object(source, "api", side_effect=RuntimeError("unauthorized")),
            self.assertRaises(RuntimeError),
        ):
            source.check_publish("1.2.0")

    def test_raw_names_do_not_repeat_platform_prefix(self):
        for name, expected in (
            ("governance-platform-v1.2.0.tar.gz", "governance-platform-v1.2.0.tar.gz"),
            (
                "governance-platform-v1.2.0.tar.gz.sha256",
                "governance-platform-v1.2.0.tar.gz.sha256",
            ),
            ("CHARTS.sha256", "governance-platform-charts.sha256"),
            (
                "cloudsmith-delivery.json",
                "governance-platform-cloudsmith-delivery.json",
            ),
        ):
            self.assertEqual(source.raw_package_name(name), expected)

    def test_publication_guard_precedes_chart_and_release_writes(self):
        workflow = yaml.load(
            (
                source.ROOT / ".github/workflows/release-platform-package.yaml"
            ).read_text(),
            Loader=yaml.BaseLoader,
        )
        steps = workflow["jobs"]["release"]["steps"]
        guard = next(
            i
            for i, step in enumerate(steps)
            if step.get("name") == "Reject republishing a delivered version"
        )
        charts = next(
            i
            for i, step in enumerate(steps)
            if step.get("name") == "Publish platform charts"
        )
        self.assertLess(guard, charts)
        script = next(
            step["run"]
            for step in steps
            if step.get("name") == "Publish GitHub release"
        )
        self.assertLess(script.index("check-publish"), script.index("--clobber"))
        # Both manual and tag publishers lock the same key as mirror publication.
        self.assertEqual(
            workflow["concurrency"]["group"],
            "platform-release-${{ inputs.version && format('platform/v{0}', inputs.version) || github.ref_name }}",
        )
        mirror = yaml.load(
            (
                source.ROOT / ".github/workflows/mirror-cloudsmith-release.yaml"
            ).read_text(),
            Loader=yaml.BaseLoader,
        )
        self.assertEqual(
            mirror["jobs"]["publish"]["concurrency"]["group"],
            "platform-release-platform/v${{ needs.prepare.outputs.version }}",
        )

    def test_inventory_preserves_all_runtime_images_and_independent_custody(self):
        self.assertEqual(len(self.inventory["images"]), 8)
        self.assertEqual(len(self.inventory["charts"]), 8)
        chart = next(
            c for c in self.inventory["charts"] if c["name"] == "openbao-custody"
        )
        self.assertEqual(chart["version"], "0.1.0")
        for image in self.inventory["images"]:
            self.assertIn(image["digest"], image["source"])
            self.assertTrue(
                image["destination"].startswith("docker.cloudsmith.io/eqtylab/prod/")
            )

    def test_charts_use_native_helm_repository_with_independent_versions(self):
        for chart in self.inventory["charts"]:
            self.assertEqual(
                chart["destination"],
                "https://dl.cloudsmith.io/basic/eqtylab/prod/helm/charts/",
            )
        self.assertEqual(
            next(c for c in self.inventory["charts"] if c["name"] == "openbao-custody")[
                "version"
            ],
            "0.1.0",
        )

    def test_pending_prerelease_and_wrong_version_are_rejected(self):
        for field, value in (
            ("status", "pending"),
            ("status", "rejected"),
            ("releaseType", "prerelease"),
            ("version", "1.2.1"),
        ):
            manifest = copy.deepcopy(self.manifest)
            if field == "status":
                manifest["validation"]["evidence"][field] = value
            else:
                manifest["platform"][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                source.validate_manifest(manifest, "1.2.0")

    def test_version_validation_precedes_network_access(self):
        with patch.object(source, "api") as api:
            for version in ("1.2.0-rc.1", "../1.2.0", "01.2.0", "1.2.0+abc", "v1.2.0"):
                with self.subTest(version=version), self.assertRaises(ValueError):
                    source.release(version)
            api.assert_not_called()

    def test_draft_prerelease_or_unmerged_release_is_rejected(self):
        for change in ({"draft": True}, {"prerelease": True}, {"published_at": None}):
            with (
                patch.object(source, "api", return_value={**self.data, **change}),
                self.assertRaises(ValueError),
            ):
                source.release("1.2.0")
        with (
            patch.object(
                source,
                "api",
                side_effect=[
                    self.data,
                    {"object": {"type": "commit", "sha": "a" * 40}},
                    {"status": "diverged"},
                ],
            ),
            self.assertRaises(ValueError),
        ):
            source.release("1.2.0")

    def test_receipt_is_bound_to_run_attempt_commit_release_and_assets(self):
        receipt = {
            "version": "1.2.0",
            "releaseId": 42,
            "commit": "a" * 40,
            "runId": 100,
            "runAttempt": 2,
            "assets": source.asset_identity(self.data),
        }
        event = {
            "workflow_run": {
                "repository": {"full_name": source.REPOSITORY},
                "head_repository": {"full_name": source.REPOSITORY},
                "path": source.PUBLISH_WORKFLOW,
                "event": "push",
                "conclusion": "success",
                "id": 100,
                "run_attempt": 2,
                "head_sha": "a" * 40,
            }
        }
        source.validate_receipt(receipt, event, self.data, "a" * 40)
        for key, value in (
            ("runId", 101),
            ("runAttempt", 1),
            ("releaseId", 41),
            ("commit", "b" * 40),
            ("assets", []),
        ):
            with self.subTest(key=key), self.assertRaises(ValueError):
                source.validate_receipt(
                    {**receipt, key: value}, event, self.data, "a" * 40
                )
        for key, value in (
            ("event", "pull_request"),
            ("conclusion", "failure"),
            ("path", "other.yaml"),
            ("head_repository", {"full_name": "attacker/fork"}),
        ):
            with self.subTest(key=key), self.assertRaises(ValueError):
                source.validate_receipt(
                    receipt,
                    {"workflow_run": {**event["workflow_run"], key: value}},
                    self.data,
                    "a" * 40,
                )

    def test_prepared_inventory_cannot_omit_or_redirect_artifacts(self):
        with patch.object(publisher, "release", return_value=(self.data, "a" * 40)):
            publisher.validate_inventory(self.inventory, self.work)
            for field in ("images", "charts", "files"):
                changed = copy.deepcopy(self.inventory)
                changed[field].pop()
                with self.subTest(field=field), self.assertRaises(ValueError):
                    publisher.validate_inventory(changed, self.work)
            changed = copy.deepcopy(self.inventory)
            changed["images"][0]["destination"] = "attacker.example/image:1.2.0"
            with self.assertRaises(ValueError):
                publisher.validate_inventory(changed, self.work)
            changed = copy.deepcopy(self.inventory)
            changed["files"][0]["path"] = "../../secret"
            with self.assertRaises(ValueError):
                publisher.validate_inventory(changed, self.work)

    def test_archive_hash_and_paths_are_checked(self):
        altered = copy.deepcopy(self.digests)
        altered["charts"]["auth-service"]["packageSha256"] = "0" * 64
        with self.assertRaises(ValueError):
            source.unpack_charts(
                self.work / "assets/governance-platform-v1.2.0.tar.gz",
                self.manifest,
                altered,
                self.work,
            )
        for path in ("../outside", "/absolute"):
            malicious = self.work / "malicious.tar.gz"
            with tarfile.open(malicious, "w:gz") as tar:
                member = tarfile.TarInfo(path)
                tar.addfile(member, io.BytesIO())
            with self.assertRaises(ValueError):
                source.unpack_charts(malicious, self.manifest, self.digests, self.work)

    def test_disabled_publishing_never_reads_inventory_or_calls_tools(self):
        with (
            patch.dict(os.environ, {}, clear=True),
            patch.object(publisher, "run") as run,
        ):
            with self.assertRaisesRegex(ValueError, "disabled"):
                publisher.publish(self.work / "does-not-exist")
            run.assert_not_called()

    def test_publication_requires_exact_workflow_context(self):
        env = {
            "CLOUDSMITH_PUBLISH_ENABLED": "true",
            "CLOUDSMITH_PUBLISH_REQUESTED": "true",
            "GITHUB_REPOSITORY": source.REPOSITORY,
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_WORKFLOW_REF": publisher.WORKFLOW,
            "GITHUB_EVENT_NAME": "workflow_run",
        }
        publisher.require_publish_context(env)
        for key, value in (
            ("GITHUB_REF", "refs/heads/feature"),
            ("GITHUB_REPOSITORY", "attacker/fork"),
            ("GITHUB_WORKFLOW_REF", "other"),
            ("GITHUB_EVENT_NAME", "pull_request"),
            ("CLOUDSMITH_PUBLISH_REQUESTED", "false"),
            ("CLOUDSMITH_PUBLISH_ENABLED", "false"),
        ):
            with self.subTest(key=key), self.assertRaises(ValueError):
                publisher.require_publish_context({**env, key: value})

    def test_transport_errors_are_not_treated_as_missing(self):
        for stderr in (
            "401 unauthorized",
            "403 denied",
            "connection refused",
            "provider-secret-canary",
        ):
            result = subprocess.CompletedProcess([], 1, "", stderr)
            with (
                patch.object(source.subprocess, "run", return_value=result),
                self.assertRaises(RuntimeError) as error,
            ):
                source.resolve("registry.example/image:v1", missing=True)
            self.assertNotIn(stderr, str(error.exception))
        result = subprocess.CompletedProcess(
            [],
            1,
            "",
            "Error response from registry: failed to resolve digest: registry.example/image:v1: not found\n",
        )
        with patch.object(source.subprocess, "run", return_value=result):
            self.assertIsNone(source.resolve("registry.example/image:v1", missing=True))

    def test_registry_server_errors_keep_status_without_provider_output(self):
        for stderr in (
            'HEAD "https://registry.example/?token=secret-canary": response status code 500: Internal Server Error',
            "Error response from registry: 500: Internal Server Error: secret-canary",
            "response status code 503: manifest unknown secret-canary",
        ):
            with (
                self.subTest(stderr=stderr),
                patch.object(
                    source.subprocess,
                    "run",
                    return_value=subprocess.CompletedProcess([], 1, "", stderr),
                ),
                self.assertRaisesRegex(RuntimeError, "HTTP 50[03]") as error,
            ):
                source.resolve("registry.example/chart:1.2.1", missing=True)
            self.assertNotIn("secret-canary", str(error.exception))
            self.assertNotIn("https://", str(error.exception))

    def test_ghcr_access_denials_explain_package_permissions_without_secrets(self):
        for detail in (
            "401 Unauthorized",
            "403 Forbidden",
            "DENIED: permission_denied: read_package",
            "insufficient_scope: authorization failed",
            "DENIED: manifest unknown",  # Denial must win over optional absence.
        ):
            result = subprocess.CompletedProcess(
                [], 1, "", detail + " https://registry.example/?token=secret-canary"
            )
            with (
                self.subTest(detail=detail),
                patch.object(source.subprocess, "run", return_value=result),
                self.assertRaises(RuntimeError) as error,
            ):
                source.resolve("ghcr.io/eqtylab/auth-service:1.2.1", missing=True)
            message = str(error.exception)
            self.assertIn("registry access denied", message)
            self.assertIn("Manage Actions access", message)
            self.assertIn("eqtylab/deployment needs Read access", message)
            self.assertNotIn("secret-canary", message)
            self.assertNotIn(detail, message)

    def test_destination_access_denial_does_not_suggest_ghcr_permissions(self):
        result = subprocess.CompletedProcess([], 1, "", "403 Forbidden")
        with (
            patch.object(source.subprocess, "run", return_value=result),
            self.assertRaises(RuntimeError) as error,
        ):
            source.resolve("docker.cloudsmith.io/eqtylab/prod/auth-service:1.2.1")
        self.assertIn("registry access denied", str(error.exception))
        self.assertNotIn("Manage Actions access", str(error.exception))

    def test_conflicting_image_is_never_copied(self):
        with (
            patch.object(publisher, "resolve", return_value="sha256:" + "b" * 64),
            patch.object(publisher, "run") as run,
        ):
            with self.assertRaisesRegex(ValueError, "Conflicting"):
                publisher.copy_oci(
                    "source/image@sha256:" + "a" * 64,
                    "target/image:1.2.0",
                    "sha256:" + "a" * 64,
                )
            run.assert_not_called()

    def test_existing_image_retries_referrer_copy(self):
        digest = "sha256:" + "a" * 64
        with (
            patch.object(publisher, "resolve", return_value=digest),
            patch.object(publisher, "referrers", return_value=[]),
            patch.object(publisher, "run") as run,
        ):
            publisher.copy_oci("source/image@" + digest, "target/image:1.2.0", digest)
            self.assertIn("--recursive", run.call_args.args[0])

    def test_raw_reuse_conflicts_and_quarantine(self):
        entry = self.inventory["files"][0]
        package = {
            "format": "raw",
            "name": entry["packageName"],
            "version": "1.2.0",
            "checksum_sha256": entry["sha256"],
            "is_sync_completed": True,
            "is_downloadable": True,
            "slug_perm": "package-id",
        }
        with patch.object(
            publisher, "run", return_value=json.dumps({"data": [package]})
        ) as run:
            result = publisher.publish_raw(entry, "1.2.0", self.work)
            self.assertEqual(result["sha256"], entry["sha256"])
            self.assertTrue(all(c.args[0][1] == "list" for c in run.call_args_list))
        for changes in (
            {"checksum_sha256": "0" * 64},
            {"is_quarantined": True},
            {"is_sync_failed": True},
        ):
            with (
                patch.object(
                    publisher,
                    "run",
                    return_value=json.dumps({"data": [{**package, **changes}]}),
                ),
                self.assertRaises(ValueError),
            ):
                publisher.raw_package(entry, "1.2.0")

    def test_native_helm_upload_waits_and_preserves_archive(self):
        chart = self.inventory["charts"][0]
        pending = {"is_sync_completed": False}
        complete = {
            "is_sync_completed": True,
            "is_downloadable": True,
            "slug_perm": "native-helm",
        }
        for first in (None, pending, complete):
            with (
                self.subTest(first=first),
                patch.object(
                    publisher, "helm_package", side_effect=[first, pending, complete]
                ),
                patch.object(publisher, "run") as run,
                patch.object(publisher.time, "sleep") as sleep,
                patch.object(publisher, "chart_checksum") as verify,
            ):
                result = publisher.publish_chart(chart, self.work)
            if first is None:
                run.assert_called_once_with(
                    [
                        "cloudsmith",
                        "push",
                        "helm",
                        "eqtylab/prod",
                        str(self.work / chart["path"]),
                        "--no-republish",
                    ]
                )
            else:
                run.assert_not_called()
            verify.assert_called_once_with(
                chart["name"], chart["sha256"], chart["version"]
            )
            sleep.assert_called_once_with(10)
            self.assertEqual(result["packageId"], "native-helm")
            self.assertEqual(result["format"], "helm")
            self.assertNotIn("destinationDigest", result)
            self.assertNotIn("path", result)

    def test_native_helm_conflicts_and_policy_denials_block_reuse(self):
        chart = self.inventory["charts"][0]
        package = {
            "format": "helm",
            "name": chart["name"],
            "version": chart["version"],
            "checksum_sha256": chart["sha256"],
        }
        for changes in (
            {"checksum_sha256": "0" * 64},
            {"is_quarantined": True},
            {"is_sync_failed": True},
            {"policy_violated": True},
        ):
            with (
                self.subTest(changes=changes),
                patch.object(
                    publisher,
                    "run",
                    return_value=json.dumps({"data": [{**package, **changes}]}),
                ) as run,
                self.assertRaises(ValueError),
            ):
                publisher.publish_chart(chart, self.work)
            self.assertTrue(all(c.args[0][1] == "list" for c in run.call_args_list))

    def test_native_helm_waits_for_index_and_checks_downloaded_bytes(self):
        chart = self.inventory["charts"][0]
        reference = "cloudsmith-prod/" + chart["name"]
        for corrupt in (False, True):
            searches = iter([[], [{"name": reference, "version": chart["version"]}]])

            def command(args):
                if args[1:3] == ["repo", "update"]:
                    return ""
                if args[1:3] == ["search", "repo"]:
                    return json.dumps(next(searches))
                self.assertEqual(args[:3], ["helm", "pull", reference])
                destination = Path(args[args.index("--destination") + 1])
                destination.joinpath("chart.tgz").write_bytes(
                    b"corrupt" if corrupt else (self.work / chart["path"]).read_bytes()
                )
                return ""

            with (
                self.subTest(corrupt=corrupt),
                patch.object(publisher, "run", side_effect=command),
                patch.object(publisher.time, "sleep") as sleep,
            ):
                if corrupt:
                    with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                        publisher.chart_checksum(
                            chart["name"], chart["sha256"], chart["version"]
                        )
                else:
                    publisher.chart_checksum(
                        chart["name"], chart["sha256"], chart["version"]
                    )
            sleep.assert_called_once_with(10)

    def test_native_helm_index_timeout_blocks_delivery(self):
        with (
            patch.object(publisher, "run", return_value="[]") as run,
            patch.object(publisher.time, "sleep"),
            self.assertRaisesRegex(RuntimeError, "did not appear in Helm index"),
        ):
            publisher.chart_checksum("auth-service", "0" * 64, "1.2.1")
        self.assertFalse(any(c.args[0][1] == "pull" for c in run.call_args_list))

    def test_native_helm_failures_never_announce_delivery(self):
        for preflight in (True, False):
            with (
                self.subTest(preflight=preflight),
                patch.object(publisher, "require_publish_context"),
                patch.object(publisher, "release", return_value=(self.data, "a" * 40)),
                patch.object(publisher, "check_oci"),
                patch.object(publisher, "referrers", return_value=[]),
                patch.object(publisher, "raw_package", return_value=None),
                patch.object(
                    publisher,
                    "helm_package",
                    side_effect=ValueError("Conflicting helm package")
                    if preflight
                    else None,
                ),
                patch.object(publisher, "copy_oci") as copy,
                patch.object(
                    publisher,
                    "publish_chart",
                    side_effect=RuntimeError("chart checksum mismatch"),
                ) as chart,
                patch.object(publisher, "publish_raw") as raw,
                patch.object(publisher, "github_asset") as github,
                self.assertRaisesRegex(
                    (ValueError, RuntimeError), "Conflicting|checksum"
                ),
            ):
                publisher.publish(self.work)
            if preflight:
                copy.assert_not_called()
                chart.assert_not_called()
            else:
                chart.assert_called_once()
            raw.assert_not_called()
            github.assert_not_called()
            self.assertFalse((self.work / "assets/cloudsmith-delivery.json").exists())

    def test_completion_marker_is_last_and_absent_after_partial_failure(self):
        for fail in (False, True):
            uploaded = []
            marker = self.work / "assets/cloudsmith-delivery.json"
            marker.unlink(missing_ok=True)

            def raw(entry, version, work):
                uploaded.append(entry["name"])
                if fail and len(uploaded) == 2:
                    raise RuntimeError("interrupted upload")
                return {
                    "name": entry["name"],
                    "packageName": entry["packageName"],
                    "version": version,
                    "sha256": entry["sha256"],
                    "packageId": "test-package",
                    "url": "https://dl.cloudsmith.io/basic/eqtylab/prod/raw/names/test",
                }

            with self.subTest(fail=fail), ExitStack() as stack:
                stack.enter_context(patch.object(publisher, "require_publish_context"))
                stack.enter_context(
                    patch.object(
                        publisher, "release", return_value=(self.data, "a" * 40)
                    )
                )
                stack.enter_context(
                    patch.object(
                        publisher, "resolve", return_value="sha256:" + "c" * 64
                    )
                )
                stack.enter_context(patch.object(publisher, "check_oci"))
                stack.enter_context(
                    patch.object(publisher, "referrers", return_value=[])
                )
                stack.enter_context(patch.object(publisher, "copy_oci"))
                stack.enter_context(patch.object(publisher, "chart_checksum"))
                stack.enter_context(
                    patch.object(publisher, "helm_package", return_value=None)
                )
                stack.enter_context(
                    patch.object(
                        publisher,
                        "publish_chart",
                        side_effect=lambda chart, work: {
                            **{k: v for k, v in chart.items() if k != "path"},
                            "format": "helm",
                            "packageId": "native-chart",
                        },
                    )
                )
                stack.enter_context(
                    patch.object(publisher, "raw_package", return_value=None)
                )
                stack.enter_context(
                    patch.object(publisher, "publish_raw", side_effect=raw)
                )
                stack.enter_context(patch.object(publisher, "github_asset"))
                if fail:
                    with self.assertRaisesRegex(RuntimeError, "interrupted"):
                        publisher.publish(self.work)
                    self.assertFalse(marker.exists())
                    self.assertNotIn("cloudsmith-delivery.json", uploaded)
                else:
                    publisher.publish(self.work)
                    self.assertEqual(uploaded[-1], "cloudsmith-delivery.json")
                    self.assertEqual(len(uploaded), len(self.inventory["files"]) + 1)
                    delivery = json.loads(marker.read_text())
                    self.assertEqual(len(delivery["images"]), 8)
                    self.assertNotIn("path", delivery["charts"][0])
                    self.assertNotIn("destinationDigest", delivery["charts"][0])
                    self.assertEqual(delivery["charts"][0]["format"], "helm")
                    self.assertEqual(delivery["schemaVersion"], 2)

    def test_partial_raw_upload_waits_without_republishing(self):
        entry = self.inventory["files"][0]
        pending = {"is_sync_completed": False}
        complete = {
            "is_sync_completed": True,
            "is_downloadable": True,
            "slug_perm": "test",
        }
        with (
            patch.object(
                publisher, "raw_package", side_effect=[pending, pending, complete]
            ),
            patch.object(publisher.time, "sleep"),
            patch.object(publisher, "run") as run,
        ):
            publisher.publish_raw(entry, "1.2.0", self.work)
            run.assert_not_called()

    def test_checksum_file_failure_blocks_preparation(self):
        checksum = self.work / "assets/CHARTS.sha256"
        checksum.write_text("0" * 64 + "  dist/charts/auth-service-1.2.0.tgz\n")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            source.verify_checksums(self.work)

    def test_image_provenance_includes_all_legacy_tags(self):
        image = self.inventory["images"][0]
        digest = "sha256:" + "e" * 64
        with (
            patch.object(source, "resolve", return_value=digest),
            patch.object(source, "run"),
            patch.object(source, "referrers", return_value=[digest]),
        ):
            source.inventory_provenance(image)
        self.assertEqual(
            {a["destination"].rsplit(".", 1)[1] for a in image["attachments"]},
            {"sig", "att", "sbom"},
        )
        self.assertTrue(
            all(a["source"].endswith("@" + digest) for a in image["attachments"])
        )

    def test_no_receipt_on_different_tag_commit(self):
        with (
            patch.dict(os.environ, {"GITHUB_SHA": "b" * 40}),
            patch.object(source, "release", return_value=(self.data, "a" * 40)),
            self.assertRaises(ValueError),
        ):
            source.receipt("1.2.0", self.work / "receipt.json")
        self.assertFalse((self.work / "receipt.json").exists())

    def test_preview_does_not_contain_cloudsmith_calls(self):
        # Exercise the full prepare path, not a separate simplified dry-run implementation.
        out = self.work / "preview"
        assets = self.work / "assets"

        def command(args, **kwargs):
            if args[:3] == ["gh", "release", "download"]:
                name = args[args.index("--pattern") + 1]
                (out / "assets" / name).write_bytes((assets / name).read_bytes())
                return ""
            if "Accept: application/vnd.github.raw+json" in args:
                return yaml.safe_dump(self.manifest)
            if args[:3] == ["oras", "manifest", "fetch"]:
                name = args[-1].split("@", 1)[0].rsplit("/", 1)[1]
                return json.dumps(
                    {
                        "layers": [
                            {
                                "digest": "sha256:"
                                + self.digests["charts"][name]["packageSha256"]
                            }
                        ]
                    }
                )
            self.fail(f"Unexpected preview command: {args[:3]}")

        with (
            patch.object(source, "release", return_value=(self.data, "a" * 40)),
            patch.object(source, "run", side_effect=command),
            patch.object(source, "resolve", side_effect=lambda ref: ref.split("@")[1]),
            patch.object(source, "inventory_provenance"),
            patch.object(source, "export_provenance"),
            patch.dict(os.environ, {}, clear=True),
        ):
            result = source.prepare("1.2.0", out)
        self.assertEqual(len(result["images"]), 8)
        self.assertTrue((out / "inventory.json").is_file())


if __name__ == "__main__":
    unittest.main()
