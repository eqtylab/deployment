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

The [deployment download contract](https://github.com/eqtylab/deployment/blob/main/docs/cloudsmith-release.md#customer-download-contract)
documents the delivery manifest URL and raw package naming. Obtain that manifest
with your prod entitlement and use its artifact locations for the customer
archive and checksum. Verify the archive's SHA-256 before extracting it. The
archive contains chart packages, examples, and `values-cloudsmith.yaml`.

Until your version has a verified delivery, continue using the existing GHCR
chart, image credentials, and `govctl init --artifact-source github`.

## Authenticate Helm and Kubernetes

Helm credentials and Kubernetes image pull credentials are separate. With Helm
3.20 or later, load your prod entitlement into `CLOUDSMITH_ENTITLEMENT_TOKEN`
through your secret manager, then add the native Helm repository:

```bash
printf '%s' "$CLOUDSMITH_ENTITLEMENT_TOKEN" | helm repo add cloudsmith-prod \
  https://dl.cloudsmith.io/basic/eqtylab/prod/helm/charts/ \
  --username token --password-stdin
helm repo update cloudsmith-prod
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

Alternatively, `govctl init` generates Cloudsmith registry settings by default for verified
releases. It inherits the selected release chart’s image tags and digests instead
of setting `latest`.
Fill the entitlement-token placeholder through your existing secret-management
system if using Helm-managed secrets. Use `govctl init --artifact-source github`
for internal installations. Custom registry hosts also require the full image
repository prefix; the interactive generator asks for both.

## Install

Substitute a delivered stable version and your environment configuration:

```bash
helm upgrade --install governance-platform \
  cloudsmith-prod/governance-platform \
  --version <version> --namespace governance --create-namespace \
  --values values.yaml --values values-cloudsmith.yaml
```

For Helm-managed secrets, also supply your protected secrets values file. The
Cloudsmith overlay sets the registry host and entitlement username but contains
no token and does not enable secret creation. Keep its image prefix and secret
host settings consistent. All eight EQTY runtime images use Cloudsmith while
the release's existing digest pins are preserved.

The original `release-manifest.yaml` and `chart-digests.yaml` retain GHCR build
references. Use `cloudsmith-delivery.json` for distribution locations and native
Helm package identifiers. Chart archive SHA-256s and image digests must match
their original release artifacts.

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
