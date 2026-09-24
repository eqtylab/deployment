"""Validate and stage the optional custody handoff without contacting a cluster."""

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
OCI = "oci://ghcr.io/eqtylab/charts/openbao-custody"
OPERATOR_FILES = (
    "scripts/openbao/configure-auth.sh",
    "scripts/openbao/policies/guardian-auth.hcl",
    "scripts/openbao/README.md",
    "scripts/helpers/output.sh",
)


def read_yaml(path):
    return yaml.safe_load(Path(path).read_text())


def run_quietly(args, **kwargs):
    """Run a check with stdout discarded; a failure keeps its stderr for main()."""
    return subprocess.run(
        args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, **kwargs
    )


def describe_failure(error):
    stderr = error.stderr or b""
    if isinstance(stderr, bytes):
        stderr = stderr.decode(errors="replace")
    stderr = stderr.strip()
    return f"{error}\n{stderr}" if stderr else str(error)


def custody_version(manifest, source=None):
    """Absence is external-only; a present but invalid entry must fail closed."""
    charts = manifest["charts"]
    if "openbaoCustody" not in charts:
        return None
    entry = charts["openbaoCustody"]
    if not isinstance(entry, dict) or entry.get("name") != "openbao-custody":
        raise ValueError("charts.openbaoCustody.name must be openbao-custody")
    version = entry.get("version")
    if not isinstance(version, str) or not re.fullmatch(
        r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?",
        version,
    ):
        raise ValueError(
            "charts.openbaoCustody.version must be an explicit chart version"
        )
    if entry.get("oci") != OCI:
        raise ValueError(f"charts.openbaoCustody.oci must be {OCI}")
    if (
        source
        and version
        != read_yaml(source / "charts/openbao-custody/Chart.yaml")["version"]
    ):
        raise ValueError("selected custody version does not match the source chart")
    return version


def required_chart_files(source):
    """Files every packaged custody chart must carry, in lockstep with the source tree."""
    examples = sorted(
        "examples/" + path.name
        for path in (source / "charts/openbao-custody/examples").glob("*.yaml")
    )
    if not examples:
        raise ValueError("source custody chart ships no examples to distribute")
    return ("README.md", "templates/NOTES.txt", "templates/_helpers.tpl", *examples)


def stage_operator_files(source, destination):
    # Copy only public operator inputs, preserving the script's relative imports.
    for name in OPERATOR_FILES:
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, target)
    shutil.copy2(source / "docs/openbao-delivery.md", destination / "OPENBAO.md")


def archive_contents(path):
    """Compare payloads, not tar timestamps/compression or metadata YAML style."""
    files = {}
    with tarfile.open(path) as archive:
        for member in archive.getmembers():
            if member.isdir():
                continue
            if not member.isfile() or member.name in files:
                raise ValueError("custody archive contains a link or duplicate entry")
            content = archive.extractfile(member).read()
            # Helm rewrites chart metadata when packaging. Equivalent formatting
            # across Helm versions is harmless; all other payloads match bytes.
            if Path(member.name).name in ("Chart.yaml", "Chart.lock"):
                content = yaml.safe_load(content)
            files[member.name] = content
    return files


def verify_package(source, package):
    manifest = read_yaml(package / "release-manifest.yaml")
    version = custody_version(manifest, source)
    for name in OPERATOR_FILES:
        packaged = package / name
        if (
            not packaged.is_file()
            or packaged.read_bytes() != (source / name).read_bytes()
        ):
            raise ValueError(f"missing or changed operator file: {name}")
    if not (package / "OPENBAO.md").is_file():
        raise ValueError("missing OPENBAO.md operator handoff")
    # This exercises relative helper/policy imports after distribution. No bao
    # command executes in dry-run mode, even when credentials exist in the shell.
    run_quietly(
        [
            "bash",
            str((package / "scripts/openbao/configure-auth.sh").resolve()),
            "--service-account",
            "package-check-auth",
            "--namespace",
            "package-check",
            "--dry-run",
        ],
        cwd=package,
    )
    archives = list((package / "charts").glob("openbao-custody-*.tgz"))
    digests = read_yaml(package / "chart-digests.yaml")["charts"]
    if version is None:
        if archives or "openbao-custody" in digests:
            raise ValueError(
                "external-only manifest must not distribute a custody chart"
            )
        return

    archive = package / "charts" / f"openbao-custody-{version}.tgz"
    if archives != [archive]:
        raise ValueError("package must contain exactly the selected custody chart")
    digest = digests.get("openbao-custody", {})
    if (
        digest.get("version") != version
        or digest.get("oci") != OCI
        or digest.get("package") != archive.name
        or digest.get("packageSha256")
        != hashlib.sha256(archive.read_bytes()).hexdigest()
    ):
        raise ValueError("custody chart-digests.yaml metadata/checksum mismatch")
    expected = read_yaml(source / "charts/openbao-custody/Chart.yaml")
    lock = read_yaml(source / "charts/openbao-custody/Chart.lock")
    with tarfile.open(archive) as contents:

        def chart_yaml(name):
            return yaml.safe_load(contents.extractfile("openbao-custody/" + name))

        actual = chart_yaml("Chart.yaml")
        for field in ("name", "version", "appVersion", "kubeVersion", "dependencies"):
            if actual[field] != expected[field]:
                raise ValueError(
                    f"packaged custody {field} differs from validated source"
                )
        if chart_yaml("Chart.lock") != lock:
            raise ValueError("packaged custody lock differs from validated source")
        upstream = chart_yaml("charts/openbao/Chart.yaml")
        if upstream["version"] != lock["dependencies"][0]["version"]:
            raise ValueError("packaged upstream chart differs from custody lock")
        for name in required_chart_files(source):
            contents.getmember("openbao-custody/" + name)
    # An existing immutable OCI version may have matching metadata/lock while
    # holding different values, templates, or vendored files. Repackage the
    # validated source and compare every payload before trusting the reused tar.
    with tempfile.TemporaryDirectory(prefix="custody-source-package-") as work:
        run_quietly(
            [
                os.environ.get("HELM", "helm"),
                "package",
                str(source / "charts/openbao-custody"),
                "--destination",
                work,
            ]
        )
        expected_archive = Path(work) / archive.name
        if archive_contents(archive) != archive_contents(expected_archive):
            raise ValueError("custody archive payload differs from validated source")
    run_quietly(
        [
            os.environ.get("HELM", "helm"),
            "template",
            "custody-package-check",
            str(archive),
            "--namespace",
            "custody",
            "--kube-version",
            "1.30.0",
        ]
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT)
    commands = parser.add_subparsers(dest="command", required=True)
    selected = commands.add_parser("selected-version")
    selected.add_argument("manifest", type=Path)
    validate = commands.add_parser("validate-manifests")
    validate.add_argument("manifests", type=Path, nargs="+")
    for name in ("stage", "verify-package"):
        commands.add_parser(name).add_argument("package", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "selected-version":
            print(custody_version(read_yaml(args.manifest), args.source) or "")
        elif args.command == "validate-manifests":
            current = read_yaml(args.source / "charts/governance-platform/Chart.yaml")[
                "version"
            ]
            for path in args.manifests:
                manifest = read_yaml(path)
                source = (
                    args.source if manifest["platform"]["version"] == current else None
                )
                custody_version(manifest, source)
        elif args.command == "stage":
            stage_operator_files(args.source, args.package)
        else:
            verify_package(args.source, args.package)
    except subprocess.CalledProcessError as error:
        parser.exit(
            1, f"custody distribution check failed: {describe_failure(error)}\n"
        )
    except (ValueError, KeyError, OSError, yaml.YAMLError, tarfile.TarError) as error:
        parser.exit(1, f"custody distribution check failed: {error}\n")


if __name__ == "__main__":
    main()
