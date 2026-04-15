# PostgreSQL 17.9 Bitnami-Derived Custom Image

This image keeps Bitnami's PostgreSQL runtime layout, scripts, and entrypoint
from the public `bitnamilegacy/postgresql:17.6.0-debian-12-r4` image, but
replaces the PostgreSQL server binaries with an upstream PostgreSQL 17.9 build.
It also preserves Bitnami's bundled `pgaudit` extension so the stock Bitnami
startup path still works.

## Why this exists

Bitnami's public registries currently expose `17.6.0-debian-12-r4` as the
newest public PostgreSQL 17 image we could verify, but Trivy still reports
PostgreSQL CVEs that are fixed in 17.8+.

Bitnami does not appear to publish a public PostgreSQL 17.9 component tarball,
so this build takes the practical fallback path:

- keep Bitnami's entrypoint and container conventions
- preserve Bitnami-added `pgaudit` files expected by the default config
- compile PostgreSQL 17.9 from the official PostgreSQL source release
- install it into `/opt/bitnami/postgresql`
- retain the same Helm/runtime behavior expected by the Bitnami image

## Base image

- runtime base: `docker.io/bitnamilegacy/postgresql:17.6.0-debian-12-r4`
- PostgreSQL source: `https://ftp.postgresql.org/pub/source/v17.9/postgresql-17.9.tar.bz2`

## Build

```bash
docker buildx build \
  --platform linux/amd64 \
  --tag ghcr.io/eqtylab/bitnami-postgresql:17.9-custom-p1 \
  --load \
  containers/postgresql-17.9-bitnami-custom
```

Or use the helper script:

```bash
PUSH=1 ./containers/postgresql-17.9-bitnami-custom/build.sh \
  ghcr.io/eqtylab/bitnami-postgresql:17.9-custom-p1
```

## Verify

After the build:

```bash
docker run --rm --platform linux/amd64 \
  --entrypoint /bin/bash \
  ghcr.io/eqtylab/bitnami-postgresql:17.9-custom-p1 \
  -lc '/opt/bitnami/postgresql/bin/postgres --version'
```

Expected output:

```text
postgres (PostgreSQL) 17.9
```

To smoke test the default startup path:

```bash
docker run -d --platform linux/amd64 \
  --name pg179-smoke \
  -e ALLOW_EMPTY_PASSWORD=yes \
  ghcr.io/eqtylab/bitnami-postgresql:17.9-custom-p1

docker logs pg179-smoke
docker inspect --format '{{.State.Status}} {{.State.ExitCode}}' pg179-smoke
```

When healthy, the logs should include:

```text
LOG:  pgaudit extension initialized
LOG:  starting PostgreSQL 17.9
LOG:  database system is ready to accept connections
```

## Trivy

On the locally validated image, Trivy no longer reported PostgreSQL-specific
HIGH/CRITICAL findings. The remaining HIGH/CRITICAL results were Debian 12
package residuals:

- glibc `CVE-2026-0861`
- openldap `CVE-2023-2953`
- ncurses `CVE-2025-69720`
- sqlite `CVE-2025-7458`
- systemd `CVE-2026-29111`
- zlib `CVE-2023-45853`

## Notes

- This is a custom derivative, not an official Bitnami-supported image.
- It is intended as a controlled bridge while moving off the archived Bitnami
  Legacy line or onto a managed PostgreSQL service.
- The Debian package findings from scanners may still include Bookworm
  residuals that do not yet have vendor backports.
