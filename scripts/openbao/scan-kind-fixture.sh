#!/usr/bin/env bash
# Scan actual rendered resources, retaining the fixture's mandatory image pins.
set -euo pipefail

if [[ $# != 1 ]]; then
  echo "Usage: bash scripts/openbao/scan-kind-fixture.sh OUTPUT_MANIFEST" >&2
  exit 2
fi

if ! command -v trivy >/dev/null 2>&1; then
  echo "trivy is not on PATH; in CI the scan action installs it, so an earlier failure there is the real cause." >&2
  exit 2
fi

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do SOURCE="$(readlink "$SOURCE")"; done
repo_root="$(cd -P "$(dirname "$SOURCE")/../.." && pwd)"

helm template guardian-local "$repo_root/tests/fixtures/openbao-kind" \
  --namespace guardian-openbao-ci-app \
  --values "$repo_root/tests/fixtures/openbao-kind/values-scan.yaml" > "$1"
test -s "$1"
echo "Checking rendered fixture misconfigurations; this does not scan image vulnerabilities."
trivy config --severity HIGH,CRITICAL --exit-code 1 "$1"
