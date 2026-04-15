#!/usr/bin/env bash

set -euo pipefail

IMAGE_REF="${1:-}"
PLATFORM="${PLATFORM:-linux/amd64}"
PUSH="${PUSH:-0}"
BASE_IMAGE="${BASE_IMAGE:-docker.io/bitnamilegacy/postgresql:17.6.0-debian-12-r4}"
POSTGRESQL_VERSION="${POSTGRESQL_VERSION:-17.9}"
POSTGRESQL_SOURCE_URL="${POSTGRESQL_SOURCE_URL:-https://ftp.postgresql.org/pub/source/v17.9/postgresql-17.9.tar.bz2}"
POSTGRESQL_SHA256="${POSTGRESQL_SHA256:-3b9a62538a8da151e807a3ddb1198e8605f2032544d78f403ae883d27ecf1ee4}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${IMAGE_REF}" ]]; then
  echo "usage: $0 <registry/repository:tag>" >&2
  exit 1
fi

OUTPUT_FLAG="--load"
if [[ "${PUSH}" == "1" ]]; then
  OUTPUT_FLAG="--push"
fi

docker buildx build \
  --pull \
  --platform "${PLATFORM}" \
  --build-arg BITNAMI_BASE_IMAGE="${BASE_IMAGE}" \
  --build-arg POSTGRESQL_VERSION="${POSTGRESQL_VERSION}" \
  --build-arg POSTGRESQL_SOURCE_URL="${POSTGRESQL_SOURCE_URL}" \
  --build-arg POSTGRESQL_SHA256="${POSTGRESQL_SHA256}" \
  --tag "${IMAGE_REF}" \
  "${OUTPUT_FLAG}" \
  "${SCRIPT_DIR}"
