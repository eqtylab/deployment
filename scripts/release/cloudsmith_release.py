"""Prepare an immutable platform delivery from GitHub; this module never uploads."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
from urllib.parse import quote

import yaml

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "eqtylab/deployment"
PUBLISH_WORKFLOW = ".github/workflows/release-platform-package.yaml"
IMAGE_PREFIX = "docker.cloudsmith.io/eqtylab/prod"
CHART_REPOSITORY = "https://dl.cloudsmith.io/basic/eqtylab/prod/helm/charts/"
SIGNER = "https://github.com/eqtylab/guardian/.github/workflows/_build-image.yml@refs/heads/main"
DIGEST = re.compile(r"sha256:[a-f0-9]{64}")
STABLE = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")
NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+-]*")
GENERATED = {"cloudsmith-delivery.json"}


def run(args, *, cwd=None, missing=False):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=900)
    if result.returncode:
        # Report a fixed diagnostic, never provider text containing credentials.
        if args[0] == "oras" and re.search(
            r"\b(?:unauthorized|forbidden|denied|insufficient_scope)\b",
            result.stderr,
            re.IGNORECASE,
        ):
            message = f"oras {args[1]} failed: registry access denied"
            if args[:2] == ["oras", "resolve"] and args[2].startswith(
                "ghcr.io/eqtylab/"
            ):
                message += (
                    "; check each source package's Settings > Manage Actions access: "
                    "eqtylab/deployment needs Read access. Workflow packages: read "
                    "and a successful registry login alone do not grant package access"
                )
            raise RuntimeError(message)
        # Authentication, transport errors and policy denials are never absence.
        status = re.search(
            r"(?:response status code |Error response from registry: )([45][0-9]{2})\b",
            result.stderr,
        )
        absent = (
            "(HTTP 404)" in result.stderr
            if args[0] == "gh"
            else bool(
                re.search(r"\b(?:MANIFEST_UNKNOWN|manifest unknown)\b", result.stderr)
            )
            or (
                args[:2] == ["oras", "resolve"]
                and result.stderr.strip()
                == f"Error response from registry: failed to resolve digest: {args[2]}: not found"
            )
        )
        if missing and absent and (status is None or status[1] == "404"):
            return None
        # Do not echo provider output, which can contain signed URLs or tokens.
        detail = f"; HTTP {status[1]}" if status else ""
        raise RuntimeError(
            f"{args[0]} {args[1]} failed (exit {result.returncode}{detail})"
        )
    return result.stdout


def api(path, *, missing=False):
    value = run(["gh", "api", f"repos/{REPOSITORY}/{path}"], missing=missing)
    return json.loads(value) if value is not None else None


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def safe_name(value):
    require(isinstance(value, str) and NAME.fullmatch(value), "Unsafe artifact name")
    return value


def resolve(ref, *, missing=False):
    digest = run(["oras", "resolve", ref], missing=missing)
    if digest is None:
        return None
    digest = digest.strip()
    require(DIGEST.fullmatch(digest), f"Invalid registry digest for {ref}")
    return digest


def release(version):
    require(STABLE.fullmatch(version), "Cloudsmith requires a stable X.Y.Z version")
    data = api(f"releases/tags/{quote('platform/v' + version, safe='')}")
    require(
        not data["draft"] and not data["prerelease"],
        "Release must be published and stable",
    )
    require(
        data["tag_name"] == f"platform/v{version}" and data.get("published_at"),
        "Unpublished release",
    )
    obj = api(f"git/ref/tags/platform/v{version}")["object"]
    for _ in range(8):
        if obj["type"] == "commit":
            break
        require(obj["type"] == "tag", "Release tag does not resolve to a commit")
        obj = api(f"git/tags/{obj['sha']}")["object"]
    require(obj["type"] == "commit", "Too many nested release tags")
    commit = obj["sha"]
    comparison = api(f"compare/{commit}...main")
    require(
        comparison["status"] in ("ahead", "identical"),
        "Release commit is not on deployment main",
    )
    return data, commit


def source_assets(data):
    return [
        asset
        for asset in data["assets"]
        if asset["name"] not in GENERATED
        and not asset["name"].startswith("cloudsmith-provenance-")
    ]


def asset_identity(data):
    return sorted(
        (
            {
                "id": a["id"],
                "name": a["name"],
                "digest": a.get("digest"),
                "size": a["size"],
            }
            for a in source_assets(data)
        ),
        key=lambda a: a["name"],
    )


def check_publish(version):
    """Prevent rebuilding source artifacts once a delivery has been announced."""
    safe_name(version)
    data = api(f"releases/tags/{quote('platform/v' + version, safe='')}", missing=True)
    require(
        data is None
        or not any(a["name"] == "cloudsmith-delivery.json" for a in data["assets"]),
        "This version has a completed Cloudsmith delivery; publish a new version instead",
    )


def receipt(version, destination):
    data, commit = release(version)
    require(
        commit == os.environ["GITHUB_SHA"],
        "Published tag differs from packaging commit",
    )
    write_json(
        destination,
        {
            "version": version,
            "releaseId": data["id"],
            "commit": commit,
            "runId": int(os.environ["GITHUB_RUN_ID"]),
            "runAttempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
            "assets": asset_identity(data),
        },
    )


def validate_receipt(value, event, data, commit):
    upstream = event["workflow_run"]
    require(
        upstream["repository"]["full_name"] == REPOSITORY,
        "Foreign publication repository",
    )
    require(
        upstream["head_repository"]["full_name"] == REPOSITORY,
        "Foreign publication source",
    )
    require(upstream["path"] == PUBLISH_WORKFLOW, "Unexpected publication workflow")
    require(
        upstream["event"] in ("push", "workflow_dispatch")
        and upstream["conclusion"] == "success",
        "Publication run did not succeed",
    )
    require(
        value["runId"] == upstream["id"]
        and value["runAttempt"] == upstream["run_attempt"],
        "Receipt belongs to another publication attempt",
    )
    require(
        value["commit"] == commit == upstream["head_sha"],
        "Receipt source commit mismatch",
    )
    require(
        value["releaseId"] == data["id"]
        and data["tag_name"] == f"platform/v{value['version']}",
        "Receipt release mismatch",
    )
    require(
        value["assets"] == asset_identity(data),
        "Release assets changed after publication",
    )


def validate_manifest(manifest, version):
    require(
        manifest["platform"]["version"] == version
        and manifest["platform"]["releaseType"] == "stable",
        "Manifest must select this stable release",
    )
    require(
        manifest["validation"]["mode"] == "manual"
        and manifest["validation"]["evidence"]["status"] == "approved",
        "Manifest is not approved",
    )
    require(
        manifest["sources"]["guardian"]["repository"] == "eqtylab/guardian",
        "Only Guardian platform releases are supported",
    )


def raw_package_name(name):
    name = safe_name(name).lower()
    return (
        name
        if name.startswith("governance-platform-")
        else "governance-platform-" + name
    )


def file_entry(path):
    return {
        "name": path.name,
        "sha256": sha256(path),
        "path": f"assets/{path.name}",
        "packageName": raw_package_name(path.name),
    }


def unpack_charts(archive, manifest, chart_digests, work):
    """Read only expected regular files; never extract release-supplied paths."""
    version = manifest["platform"]["version"]
    prefix = f"governance-platform-v{version}/"
    with tarfile.open(archive) as tar:
        members = {}
        for member in tar.getmembers():
            path = PurePosixPath(member.name)
            require(
                not path.is_absolute()
                and ".." not in path.parts
                and (member.isdir() or member.isfile()),
                "Unsafe customer archive entry",
            )
            require(member.name not in members, "Duplicate customer archive entry")
            members[member.name] = member
        for name, expected in (
            ("release-manifest.yaml", manifest),
            ("chart-digests.yaml", chart_digests),
        ):
            require(
                yaml.safe_load(tar.extractfile(members[prefix + name])) == expected,
                f"Packaged {name} differs from GitHub release asset",
            )
        selected = {c["name"]: c for c in manifest["charts"].values()}
        require(
            set(selected) == set(chart_digests["charts"]), "Chart inventory mismatch"
        )
        charts = []
        for name, chart in sorted(selected.items()):
            safe_name(name)
            chart_version = safe_name(chart["version"])
            if name != "openbao-custody":
                require(chart_version == version, "Platform chart version mismatch")
            recorded = chart_digests["charts"][name]
            package = f"{name}-{chart_version}.tgz"
            require(
                recorded["package"] == package
                and recorded["version"] == chart_version
                and recorded["oci"]
                == chart["oci"]
                == f"oci://ghcr.io/eqtylab/charts/{name}",
                "Chart source metadata mismatch",
            )
            require(
                DIGEST.fullmatch(recorded["ociDigest"]), "Chart OCI digest is missing"
            )
            target = work / "charts" / package
            target.parent.mkdir(exist_ok=True)
            target.write_bytes(
                tar.extractfile(members[prefix + "charts/" + package]).read()
            )
            require(
                sha256(target) == recorded["packageSha256"],
                "Chart archive checksum mismatch",
            )
            charts.append(
                {
                    "name": name,
                    "version": chart_version,
                    "path": f"charts/{package}",
                    "sha256": recorded["packageSha256"],
                    "source": chart["oci"][6:] + "@" + recorded["ociDigest"],
                    "destination": CHART_REPOSITORY,
                }
            )
    return charts


def image_entries(manifest):
    result = []
    for key, entry in sorted(manifest["images"].items()):
        repository, digest = entry["repository"], entry["digest"]
        require(
            re.fullmatch(r"ghcr.io/eqtylab/[a-z0-9][a-z0-9-]*", repository),
            "Unexpected image source",
        )
        require(DIGEST.fullmatch(digest), "Image digest is missing")
        require(
            entry["tag"] == manifest["platform"]["version"], "Image version mismatch"
        )
        require(
            entry["sourceSha"] == manifest["sources"]["guardian"]["ref"],
            "Image source commit mismatch",
        )
        result.append(
            {
                "name": key,
                "source": f"{repository}@{digest}",
                "digest": digest,
                "destination": f"{IMAGE_PREFIX}/{repository.rsplit('/', 1)[1]}:{entry['tag']}",
            }
        )
    require(result, "No release images")
    require(
        len({i["destination"] for i in result}) == len(result),
        "Duplicate image destination",
    )
    return result


def verify_checksums(work):
    files = {
        p.name: p
        for folder in ("assets", "charts")
        for p in (work / folder).iterdir()
        if p.is_file()
    }
    for path in (work / "assets").glob("*.sha256"):
        for line in path.read_text().splitlines():
            parts = line.split(maxsplit=1)
            require(
                len(parts) == 2 and re.fullmatch(r"[a-f0-9]{64}", parts[0]),
                "Invalid checksum file",
            )
            name = PurePosixPath(parts[1].lstrip(" *")).name
            require(
                name in files and sha256(files[name]) == parts[0],
                f"Release checksum mismatch: {name}",
            )


def inventory_provenance(image):
    source_repository, digest = image["source"].split("@")
    destination_repository = image["destination"].rsplit(":", 1)[0]
    # Guardian currently signs with Cosign 2.x. OCI recursive copy alone misses these tags.
    attachments = []
    for kind in ("sig", "att", "sbom"):
        tag = digest.replace(":", "-") + "." + kind
        attachment_digest = resolve(f"{source_repository}:{tag}", missing=True)
        if attachment_digest:
            attachments.append(
                {
                    "source": f"{source_repository}@{attachment_digest}",
                    "destination": f"{destination_repository}:{tag}",
                    "digest": attachment_digest,
                }
            )
    run(
        [
            "cosign",
            "verify",
            "--certificate-identity",
            SIGNER,
            "--certificate-oidc-issuer",
            "https://token.actions.githubusercontent.com",
            image["source"],
        ]
    )
    image["attachments"] = attachments
    image["referrers"] = referrers(image["source"])


def referrers(reference):
    data = json.loads(run(["oras", "discover", "--format", "json", reference]))
    return sorted(item["digest"] for item in data.get("referrers", []))


def export_provenance(work, files, subjects):
    for path in subjects:
        digest = "sha256:" + sha256(path)
        # Pagination matters for releases that were attested more than once.
        output = run(
            [
                "gh",
                "api",
                "--paginate",
                "--slurp",
                f"repos/{REPOSITORY}/attestations/{digest}",
            ],
            missing=True,
        )
        if output is None:
            continue  # Historical release may predate GitHub attestations.
        bundles = [
            a["bundle"]
            for page in json.loads(output)
            for a in page.get("attestations", [])
        ]
        if not bundles:
            continue
        target = work / "assets" / f"cloudsmith-provenance-{path.name}.jsonl"
        # Ignore transport metadata and duplicates; stable bytes make retries safe.
        target.write_text(
            "\n".join(sorted({json.dumps(b, sort_keys=True) for b in bundles})) + "\n"
        )
        run(
            [
                "gh",
                "attestation",
                "verify",
                str(path),
                "--repo",
                REPOSITORY,
                "--bundle",
                str(target),
            ]
        )
        files.append(file_entry(target))


def prepare(version, work, receipt_path=None):
    event = (
        json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        if receipt_path
        else None
    )
    receipt_data = json.loads(Path(receipt_path).read_text()) if receipt_path else None
    if receipt_data:
        version = receipt_data["version"]
    data, commit = release(version)
    if receipt_data:
        validate_receipt(receipt_data, event, data, commit)
    work.mkdir(parents=True, exist_ok=True)
    assets = work / "assets"
    assets.mkdir(exist_ok=True)
    files = []
    for asset in source_assets(data):
        name = safe_name(asset["name"])
        run(
            [
                "gh",
                "release",
                "download",
                data["tag_name"],
                "--repo",
                REPOSITORY,
                "--pattern",
                name,
                "--dir",
                str(assets),
            ]
        )
        path = assets / name
        require(
            asset.get("digest") == "sha256:" + sha256(path),
            f"GitHub asset checksum mismatch: {name}",
        )
        files.append(file_entry(path))
    manifest = yaml.safe_load((assets / "release-manifest.yaml").read_text())
    validate_manifest(manifest, version)
    tagged = run(
        [
            "gh",
            "api",
            f"repos/{REPOSITORY}/contents/releases/v{version}/release-manifest.yaml?ref={commit}",
            "-H",
            "Accept: application/vnd.github.raw+json",
        ]
    )
    require(
        yaml.safe_load(tagged) == manifest,
        "Release asset differs from approved tagged manifest",
    )
    chart_digests = yaml.safe_load((assets / "chart-digests.yaml").read_text())
    archive = assets / f"governance-platform-v{version}.tar.gz"
    checksum = (assets / (archive.name + ".sha256")).read_text().split()[0]
    require(sha256(archive) == checksum, "Customer package checksum mismatch")
    charts = unpack_charts(archive, manifest, chart_digests, work)
    verify_checksums(work)
    images = image_entries(manifest)
    for image in images:
        print(f"Verifying released image {image['name']}", flush=True)
        require(
            resolve(image["source"]) == image["digest"], "Source image digest mismatch"
        )
        inventory_provenance(image)
    for chart in charts:
        descriptor = json.loads(run(["oras", "manifest", "fetch", chart["source"]]))
        require(
            any(
                layer["digest"] == "sha256:" + chart["sha256"]
                for layer in descriptor["layers"]
            ),
            "Released chart bytes differ from GHCR chart digest",
        )
    export_provenance(work, files, [archive, *(work / c["path"] for c in charts)])
    require(
        len({f["packageName"] for f in files}) == len(files),
        "Raw package name collision",
    )
    result = {
        "schemaVersion": 2,
        "version": version,
        "release": {
            "id": data["id"],
            "tag": data["tag_name"],
            "commit": commit,
            "manifestSha256": sha256(assets / "release-manifest.yaml"),
        },
        "images": images,
        "charts": charts,
        "files": sorted(files, key=lambda f: f["name"]),
    }
    write_json(work / "inventory.json", result)
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            print(f"version={version}", file=output)
    print(
        f"Prepared v{version}: {len(images)} images, {len(charts)} charts, {len(files)} files; no uploads."
    )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    record = commands.add_parser("receipt")
    record.add_argument("version")
    record.add_argument("output", type=Path)
    stage = commands.add_parser("prepare")
    stage.add_argument("--version", default="")
    stage.add_argument("--receipt", type=Path)
    stage.add_argument("--work", type=Path, required=True)
    check = commands.add_parser("check-publish")
    check.add_argument("version")
    args = parser.parse_args()
    try:
        if args.command == "receipt":
            receipt(args.version, args.output)
        elif args.command == "check-publish":
            check_publish(args.version)
        else:
            prepare(args.version, args.work, args.receipt)
    except (
        ValueError,
        KeyError,
        OSError,
        RuntimeError,
        tarfile.TarError,
        yaml.YAMLError,
    ) as error:
        parser.exit(1, f"Cloudsmith preparation failed: {error}\n")


if __name__ == "__main__":
    main()
