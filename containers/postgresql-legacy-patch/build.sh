#!/usr/bin/env bash

set -euo pipefail

IMAGE_REF="${1:-}"
BASE_IMAGE="${2:-docker.io/bitnamilegacy/postgresql:17.5.0-debian-12-r17}"
PLATFORM="${PLATFORM:-linux/amd64}"
PUSH="${PUSH:-0}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${IMAGE_REF}" ]]; then
  echo "usage: $0 <registry/repository:tag> [base-image]" >&2
  exit 1
fi

OUTPUT_FLAG="--load"
if [[ "${PUSH}" == "1" ]]; then
  OUTPUT_FLAG="--push"
fi

docker buildx build \
  --pull \
  --platform "${PLATFORM}" \
  --build-arg BASE_IMAGE="${BASE_IMAGE}" \
  --tag "${IMAGE_REF}" \
  "${OUTPUT_FLAG}" \
  "${SCRIPT_DIR}"
