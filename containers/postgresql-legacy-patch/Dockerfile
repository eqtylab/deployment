# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=docker.io/bitnamilegacy/postgresql:17.5.0-debian-12-r17
FROM ${BASE_IMAGE}

USER root

# Refresh Debian 12 packages in the frozen legacy image while preserving the
# Bitnami PostgreSQL entrypoint and filesystem layout expected by the chart.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
 && DEBIAN_FRONTEND=noninteractive apt-get purge -y --auto-remove \
      gnupg2 \
      sqlite3 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

ARG PATCH_IMAGE_SOURCE=https://github.com/eqtylab/deployment/tree/main/containers/postgresql-legacy-patch
LABEL org.opencontainers.image.title="postgresql-legacy-patch" \
      org.opencontainers.image.description="Temporary patched fork of Bitnami Legacy PostgreSQL 17 for Governance Platform client deployments" \
      org.opencontainers.image.source="${PATCH_IMAGE_SOURCE}" \
      org.opencontainers.image.base.name="${BASE_IMAGE}"

USER 1001
