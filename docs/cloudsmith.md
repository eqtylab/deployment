# Installing a stable release from Cloudsmith

Customers obtain EQTY release images, Helm charts, packages, checksums, and
available provenance from `eqtylab/prod`. Your EQTY contact supplies a prod
entitlement token. Internal environments continue to use GitHub Container
Registry (GHCR). Upstream images such as Postgres, Keycloak, OpenBao, and utility
containers retain their existing registries.

Use an explicit stable version for which `cloudsmith-delivery.json` is present.
It is published only after the mirror verifies all artifacts. A GitHub release,
candidate tag, or successful image build alone does not indicate customer
availability. Cloudsmith publication is initially disabled while this integration
is being commissioned. Prereleases are internal GitHub artifacts.

## Download the customer package

Use the Cloudsmith repository setup instructions with your entitlement token.
Raw assets use the package name `governance-platform-<lowercase-filename>` and the platform
version. For example, the authenticated URL for the delivery manifest is:

```text
https://dl.cloudsmith.io/basic/eqtylab/prod/raw/names/governance-platform-cloudsmith-delivery.json/versions/<version>/cloudsmith-delivery.json
```

The delivery manifest lists the original GitHub sources and Cloudsmith locations,
digests, raw package names, versions, checksums, and credential-free download URLs.
Download `governance-platform-v<version>.tar.gz` and its checksum using the same
URL pattern. Verify the SHA-256 of the downloaded archive before extracting it.
Original checksum files retain their `dist/` paths from the release publisher;
compare the recorded hash to the downloaded file or reproduce that directory.
The archive contains chart packages, examples, and `values-cloudsmith.yaml`.

Use an entitlement-aware credential store or HTTP basic authentication with
username `token` and the entitlement token as password. Do not embed tokens in
URLs, saved scripts, shell history, or support logs.

## Authenticate Helm and Kubernetes

Helm credentials and Kubernetes image pull credentials are separate. Log Helm in
and enter the entitlement token at the password prompt:

```bash
helm registry login helm.oci.cloudsmith.io --username eqtylab/prod
```

Create the namespace and a registry secret before installation. The following
uses a temporary Docker configuration so existing registry credentials are not
included in the Kubernetes Secret:

```bash
kubectl create namespace governance --dry-run=client -o yaml | kubectl apply -f -
pull_config=$(mktemp -d)
chmod 700 "$pull_config"
docker --config "$pull_config" login docker.cloudsmith.io --username eqtylab/prod
kubectl -n governance create secret generic platform-image-pull-secret \
  --type=kubernetes.io/dockerconfigjson \
  --from-file=.dockerconfigjson="$pull_config/config.json" \
  --dry-run=client -o yaml | kubectl apply -f -
docker --config "$pull_config" logout docker.cloudsmith.io
rm -f "$pull_config/config.json"
rmdir "$pull_config"
```

Alternatively, `govctl init` generates Cloudsmith registry settings by default.
Fill the entitlement-token placeholder through your existing secret-management
system if using Helm-managed secrets. Use `govctl init --artifact-source github`
for internal installations. Custom registry hosts also require the full image
repository prefix; the interactive generator asks for both.

## Install

Substitute a delivered stable version and your environment configuration:

```bash
helm upgrade --install governance-platform \
  oci://helm.oci.cloudsmith.io/eqtylab/prod/governance-platform \
  --version <version> --namespace governance --create-namespace \
  --values values.yaml --values values-cloudsmith.yaml
```

For Helm-managed secrets, also supply your protected secrets values file. The
Cloudsmith overlay sets the registry host and entitlement username but contains
no token and does not enable secret creation. Keep its image prefix and secret
host settings consistent. All eight EQTY runtime images use Cloudsmith while
the release's existing digest pins are preserved.

The original `release-manifest.yaml` and `chart-digests.yaml` retain GHCR build
references. Use `cloudsmith-delivery.json` for distribution locations. Helm
registry manifest digests may differ between registries; chart archive SHA-256s
must match. Image digests must be identical.

The optional `openbao-custody` chart is delivered only when selected by the
release manifest, using its own version. It does not enable OpenBao in the
platform and does not mirror upstream OpenBao images. Follow `OPENBAO.md` in the
customer package for its existing qualification limits.

## Provenance and support

Image signatures, scan attestations, and OCI referrers accompany the mirrored
images. Their signed payloads retain the original builder and source identity;
mirroring does not claim a new build. Exported GitHub attestation bundles are
distributed as `cloudsmith-provenance-*.jsonl` raw files when available. They can
be verified with `gh attestation verify <artifact> --repo eqtylab/deployment
--bundle <bundle-file>`.

Give support the version, delivery manifest, failing artifact reference, and
error message. Do not send registry credentials. ImagePullBackOff can indicate
a missing secret, a dev token used against prod, or a revoked entitlement.
