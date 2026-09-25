"""Mirror a prepared stable release. Uploads require an explicitly enabled CI job."""

import argparse
import json
import os
from pathlib import Path
import tempfile
import time
from urllib.parse import quote

import jsonschema
import yaml

from cloudsmith_release import (
    CHART_REPOSITORY,
    DIGEST,
    IMAGE_PREFIX,
    REPOSITORY,
    ROOT,
    asset_identity,
    file_entry,
    image_entries,
    referrers,
    raw_package_name,
    release,
    require,
    resolve,
    run,
    safe_name,
    sha256,
    unpack_charts,
    validate_manifest,
    write_json,
)

WORKFLOW = "eqtylab/deployment/.github/workflows/mirror-cloudsmith-release.yaml@refs/heads/main"


def require_publish_context(env):
    require(
        env.get("CLOUDSMITH_PUBLISH_ENABLED") == "true"
        and env.get("CLOUDSMITH_PUBLISH_REQUESTED") == "true",
        "Cloudsmith publishing is disabled",
    )
    require(
        env.get("GITHUB_REPOSITORY") == REPOSITORY
        and env.get("GITHUB_REF") == "refs/heads/main"
        and env.get("GITHUB_WORKFLOW_REF") == WORKFLOW
        and env.get("GITHUB_EVENT_NAME") in ("workflow_run", "workflow_dispatch"),
        "Publishing requires the deployment mirror workflow on main",
    )


def check_oci(destination, expected):
    actual = resolve(destination, missing=True)
    require(
        actual is None or actual == expected,
        f"Conflicting immutable destination: {destination}",
    )
    return actual


def copy_oci(source, destination, digest):
    check_oci(destination, digest)
    # Re-run recursive copy even for an existing image: a previous attempt may
    # have stopped after the subject but before its referrers were uploaded.
    run(["oras", "cp", "--recursive", source, destination])
    require(resolve(destination) == digest, f"Copied digest mismatch: {destination}")
    destination_repo = destination.rsplit(":", 1)[0]
    for digest in referrers(source):
        require(
            resolve(f"{destination_repo}@{digest}") == digest, "Missing copied referrer"
        )
        require(
            digest in referrers(destination), "Missing destination referrer association"
        )
    return destination_repo


def cloudsmith_package(format_name, name, version, expected_sha256):
    result = json.loads(
        run(
            [
                "cloudsmith",
                "list",
                "packages",
                "eqtylab/prod",
                "--output-format",
                "json",
                "--page-all",
                "--query",
                f"format:{format_name} name:^{name}$ version:^{version}$",
            ]
        )
    )
    # The CLI returns a paginated list under data when JSON output is selected.
    packages = result["data"]
    require(isinstance(packages, list), "Unexpected Cloudsmith package response")
    packages = [
        p
        for p in packages
        if p["name"] == name and p["version"] == version and p["format"] == format_name
    ]
    require(len(packages) <= 1, f"Duplicate Cloudsmith {format_name} package: {name}")
    if not packages:
        return None
    package = packages[0]
    require(
        package["checksum_sha256"] == expected_sha256,
        f"Conflicting {format_name} package: {name}",
    )
    require(
        not package.get("is_sync_failed")
        and not package.get("is_quarantined")
        and not package.get("policy_violated"),
        f"Cloudsmith blocked package: {name}",
    )
    return package


def raw_package(entry, version):
    return cloudsmith_package("raw", entry["packageName"], version, entry["sha256"])


def helm_package(chart):
    return cloudsmith_package("helm", chart["name"], chart["version"], chart["sha256"])


def publish_raw(entry, version, work):
    if raw_package(entry, version) is None:
        run(
            [
                "cloudsmith",
                "push",
                "raw",
                "eqtylab/prod",
                str(work / entry["path"]),
                "--name",
                entry["packageName"],
                "--version",
                version,
                "--no-republish",
            ]
        )
    for _ in range(30):
        package = raw_package(entry, version)
        if (
            package
            and package.get("is_sync_completed")
            and package.get("is_downloadable")
        ):
            # Use the authenticated repository URL, never an entitlement URL.
            return {
                "name": entry["name"],
                "packageName": entry["packageName"],
                "version": version,
                "sha256": entry["sha256"],
                "packageId": package["slug_perm"],
                "url": "https://dl.cloudsmith.io/basic/eqtylab/prod/raw/names/"
                + quote(entry["packageName"], safe="")
                + "/versions/"
                + version
                + "/"
                + quote(entry["name"], safe=""),
            }
        time.sleep(10)
    raise RuntimeError(
        f"Cloudsmith package did not become downloadable: {entry['name']}"
    )


def chart_checksum(name, expected, version):
    # API sync can finish before the native Helm index reaches the CDN.
    reference = "cloudsmith-prod/" + name
    for _ in range(30):
        run(["helm", "repo", "update", "cloudsmith-prod"])
        entries = json.loads(
            run(["helm", "search", "repo", reference, "--versions", "--output", "json"])
        )
        require(isinstance(entries, list), "Unexpected Helm search response")
        if any(
            entry["name"] == reference and entry["version"] == version
            for entry in entries
        ):
            break
        time.sleep(10)
    else:
        raise RuntimeError(
            f"Cloudsmith chart did not appear in Helm index: {name} {version}"
        )
    with tempfile.TemporaryDirectory() as directory:
        run(
            [
                "helm",
                "pull",
                reference,
                "--version",
                version,
                "--destination",
                directory,
            ]
        )
        files = list(Path(directory).glob("*.tgz"))
        require(
            len(files) == 1 and sha256(files[0]) == expected,
            "Cloudsmith chart checksum mismatch",
        )


def publish_chart(chart, work):
    if helm_package(chart) is None:
        run(
            [
                "cloudsmith",
                "push",
                "helm",
                "eqtylab/prod",
                str(work / chart["path"]),
                "--no-republish",
            ]
        )
    for _ in range(30):
        package = helm_package(chart)
        if (
            package
            and package.get("is_sync_completed")
            and package.get("is_downloadable")
        ):
            chart_checksum(chart["name"], chart["sha256"], chart["version"])
            return {
                **{k: v for k, v in chart.items() if k != "path"},
                "format": "helm",
                "packageId": package["slug_perm"],
            }
        time.sleep(10)
    raise RuntimeError(f"Cloudsmith chart did not become downloadable: {chart['name']}")


def github_asset(path, data):
    existing = next((a for a in data["assets"] if a["name"] == path.name), None)
    if existing:
        require(
            existing.get("digest") == "sha256:" + sha256(path),
            f"Conflicting GitHub asset: {path.name}",
        )
        return
    run(["gh", "release", "upload", data["tag_name"], str(path), "--repo", REPOSITORY])


def validate_inventory(inventory, work):
    require(inventory.get("schemaVersion") == 2, "Prepare a new native Helm inventory")
    version = inventory["version"]
    data, commit = release(version)
    require(
        inventory["release"]["id"] == data["id"]
        and inventory["release"]["commit"] == commit,
        "Release identity changed after preparation",
    )
    require(inventory["release"]["tag"] == data["tag_name"], "Release tag mismatch")
    original = {a["name"]: a for a in asset_identity(data)}
    for entry in inventory["files"]:
        safe_name(entry["name"])
        require(
            entry["path"] == "assets/" + entry["name"]
            and entry["packageName"] == raw_package_name(entry["name"]),
            "Unsafe raw artifact path",
        )
        require(
            sha256(work / entry["path"]) == entry["sha256"],
            "Prepared asset was modified",
        )
        if entry["name"] in original:
            require(
                original.pop(entry["name"])["digest"] == "sha256:" + entry["sha256"],
                "GitHub release asset changed after preparation",
            )
        else:
            require(
                entry["name"].startswith("cloudsmith-provenance-"),
                "Unexpected prepared file",
            )
    require(not original, "Prepared inventory omits GitHub release assets")
    require(
        sha256(work / "assets/release-manifest.yaml")
        == inventory["release"]["manifestSha256"],
        "Manifest checksum mismatch",
    )
    manifest = yaml.safe_load((work / "assets/release-manifest.yaml").read_text())
    validate_manifest(manifest, version)
    expected_images = image_entries(manifest)
    require(
        [{k: i[k] for k in expected_images[0]} for i in inventory["images"]]
        == expected_images,
        "Prepared image inventory differs from release manifest",
    )
    digests = yaml.safe_load((work / "assets/chart-digests.yaml").read_text())
    with tempfile.TemporaryDirectory() as directory:
        expected_charts = unpack_charts(
            work / f"assets/governance-platform-v{version}.tar.gz",
            manifest,
            digests,
            Path(directory),
        )
    require(
        inventory["charts"] == expected_charts,
        "Prepared chart inventory differs from release package",
    )
    for image in inventory["images"]:
        require(
            image["source"].startswith("ghcr.io/eqtylab/")
            and image["source"].endswith("@" + image["digest"])
            and DIGEST.fullmatch(image["digest"]),
            "Unsafe image source",
        )
        basename = image["source"].split("@")[0].rsplit("/", 1)[1]
        require(
            image["destination"] == f"{IMAGE_PREFIX}/{safe_name(basename)}:{version}",
            "Unsafe image destination",
        )
        for attachment in image["attachments"]:
            source_repo = image["source"].split("@")[0]
            destination_repo = image["destination"].rsplit(":", 1)[0]
            require(
                DIGEST.fullmatch(attachment["digest"])
                and attachment["source"] == source_repo + "@" + attachment["digest"]
                and attachment["destination"]
                in [
                    destination_repo + ":" + image["digest"].replace(":", "-") + "." + k
                    for k in ("sig", "att", "sbom")
                ],
                "Unsafe signature destination",
            )
    for chart in inventory["charts"]:
        name, chart_version = safe_name(chart["name"]), safe_name(chart["version"])
        require(
            chart["path"] == f"charts/{name}-{chart_version}.tgz"
            and chart["destination"] == CHART_REPOSITORY,
            "Unsafe chart destination",
        )
        require(
            sha256(work / chart["path"]) == chart["sha256"],
            "Prepared chart was modified",
        )
    return data


def publish(work):
    require_publish_context(os.environ)
    inventory = json.loads((work / "inventory.json").read_text())
    data = validate_inventory(inventory, work)
    version = inventory["version"]
    # Preflight every destination before the first upload. Only a real missing
    # manifest/package permits creation; 401/403 and transport failures stop here.
    for image in inventory["images"]:
        print(f"Checking image destination {image['destination']}", flush=True)
        require(
            referrers(image["source"]) == image["referrers"],
            "Source provenance changed; prepare again",
        )
        check_oci(image["destination"], image["digest"])
        for attachment in image["attachments"]:
            check_oci(attachment["destination"], attachment["digest"])
    for chart in inventory["charts"]:
        print(
            f"Checking native Helm chart {chart['name']} {chart['version']}", flush=True
        )
        helm_package(chart)
    for entry in inventory["files"]:
        raw_package(entry, version)

    delivery = {
        "schemaVersion": 2,
        "version": version,
        "release": inventory["release"],
        "images": [],
        "charts": [],
        "files": [],
    }
    for image in inventory["images"]:
        print(f"Mirroring image {image['name']}", flush=True)
        copy_oci(image["source"], image["destination"], image["digest"])
        for attachment in image["attachments"]:
            copy_oci(
                attachment["source"], attachment["destination"], attachment["digest"]
            )
        require(
            set(image["referrers"]).issubset(referrers(image["destination"])),
            "Missing provenance referrers",
        )
        delivery["images"].append(image)
    for chart in inventory["charts"]:
        print(f"Mirroring chart {chart['name']} {chart['version']}", flush=True)
        delivery["charts"].append(publish_chart(chart, work))
    for entry in inventory["files"]:
        print(f"Mirroring release file {entry['name']}", flush=True)
        if entry["name"].startswith("cloudsmith-provenance-"):
            github_asset(work / entry["path"], data)
        delivery["files"].append(publish_raw(entry, version, work))
    # The marker is deterministic, contains no signed download URLs, and is
    # written only after all expected artifacts have been verified.
    schema = json.loads((ROOT / "schemas/cloudsmith-delivery.schema.json").read_text())
    jsonschema.validate(delivery, schema)
    marker = work / "assets/cloudsmith-delivery.json"
    write_json(marker, delivery)
    # Do not announce a completed mirror if source release assets changed while
    # the copy was running. Generated provenance assets are additive and ignored.
    data = validate_inventory(inventory, work)
    existing_marker = next(
        (a for a in data["assets"] if a["name"] == marker.name), None
    )
    if existing_marker:
        require(
            existing_marker.get("digest") == "sha256:" + sha256(marker),
            "Conflicting GitHub delivery marker",
        )
    publish_raw(file_entry(marker), version, work)
    github_asset(marker, data)
    print(f"Verified Cloudsmith delivery for v{version}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    try:
        publish(args.work)
    except (
        ValueError,
        KeyError,
        OSError,
        RuntimeError,
        jsonschema.ValidationError,
    ) as error:
        parser.exit(1, f"Cloudsmith publication failed: {error}\n")


if __name__ == "__main__":
    main()
