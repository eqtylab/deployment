# PostgreSQL Legacy Patch Image

This directory builds a temporary patched fork of the PostgreSQL image that is
running in the client environment today.

## Base image

The client scan reported:

- image name: `docker.io/bitnamilegacy/postgresql:17-debian-12`
- image label version: `17.5.0`

To avoid drift from the floating `17-debian-12` tag, the Dockerfile defaults to
the matching versioned legacy image:

- `docker.io/bitnamilegacy/postgresql:17.5.0-debian-12-r17`

That keeps the Bitnami PostgreSQL 17 layout and entrypoint intact while pulling
in newer Debian 12 security fixes during the rebuild.

## What this image changes

- Starts from the same Bitnami legacy PostgreSQL 17 image line.
- Runs `apt-get dist-upgrade` to pull current Debian 12 security updates.
- Removes `gnupg2` and `sqlite3`, which were flagged in the scan and are not
  required for normal PostgreSQL runtime.

## Build

Build and push an amd64 image to your registry:

```bash
docker buildx build \
  --platform linux/amd64 \
  --build-arg BASE_IMAGE=docker.io/bitnamilegacy/postgresql:17.5.0-debian-12-r17 \
  --tag <registry>/<repo>/postgresql:17.5.0-debian-12-r17-p1 \
  --push \
  containers/postgresql-legacy-patch
```

Or use the helper script:

```bash
PUSH=1 ./containers/postgresql-legacy-patch/build.sh \
  <registry>/<repo>/postgresql:17.5.0-debian-12-r17-p1
```

If you want to override the base image explicitly:

```bash
PUSH=1 ./containers/postgresql-legacy-patch/build.sh \
  <registry>/<repo>/postgresql:17.5.0-debian-12-r17-p1 \
  docker.io/bitnamilegacy/postgresql:17.5.0-debian-12-r17
```

## Capture the digest

After pushing, record the digest and use it in Helm:

```bash
docker buildx imagetools inspect <registry>/<repo>/postgresql:17.5.0-debian-12-r17-p1
```

## Helm override

Use the rebuilt image in your client values:

```yaml
postgresql:
  image:
    registry: <registry>
    repository: <repo>/postgresql
    tag: 17.5.0-debian-12-r17-p1
```

If you add digest support later, prefer pinning the digest as well.

## Verification

Before rolling to the client namespace:

1. Run the rebuilt image in a non-production namespace.
2. Mount a restored copy of the PostgreSQL volume or restore from backup.
3. Confirm PostgreSQL starts cleanly and accepts connections.
4. Rescan the pushed image with the same scanner the client is using.
