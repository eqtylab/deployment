# Cloudsmith release mirroring

GitHub remains the build and internal distribution system. The deployment
publisher finishes chart publication, packages, attestations, and the GitHub
release before emitting `stable-publication-<run-attempt>`. The separate
`mirror-cloudsmith-release.yaml` workflow verifies that receipt and prepares an
inventory using only GitHub/GHCR reads. No receipt is emitted for prereleases or
packaging previews.

The mirror and packaging workflows, `scripts/release/`, and this runbook are
maintained in `eqtylab/deployment`. The infrastructure sync copies selected
customer paths (including charts, release manifests, and `docs/cloudsmith.md`),
but does not overwrite these deployment-owned files.

Publishing is disabled unless the **repository variable**
`CLOUDSMITH_PUBLISH_ENABLED` is exactly `true`. Manual dispatch defaults to
`publish=false`; automatic runs publish only after this variable is enabled.
Neither merging these changes nor previewing a release authenticates to
Cloudsmith while the flag is disabled.

## Required configuration

Following [EQTY's Cloudsmith conventions](https://github.com/eqtylab/cloudsmith),
create service account `github_deployment_ci` with download and upload access to
`eqtylab/prod`. Do not grant package deletion or overwrite privileges. Configure
two OIDC policies with provider `https://token.actions.githubusercontent.com`,
that account, and these claims (one policy per event):

```json
{
  "aud": "https://github.com/eqtylab",
  "repository": "eqtylab/deployment",
  "ref": "refs/heads/main",
  "workflow_ref": "eqtylab/deployment/.github/workflows/mirror-cloudsmith-release.yaml@refs/heads/main",
  "event_name": "workflow_run"
}
```

The second policy uses `"event_name": "workflow_dispatch"`; all other claims
are identical. Do not reuse Guardian's Viper account or broaden its policy.
The Cloudsmith repository's policy README is generated from live settings;
it must not be edited to pretend a policy is installed.

Grant deployment Actions read access to the Guardian runtime image packages in
GHCR, including their signature/attestation tags. The workflow uses its own
`GITHUB_TOKEN` with `packages: read`, not a personal registry token. Its publishing
job additionally uses `contents: write` for additive delivery/provenance assets
and `id-token: write` for short-lived Cloudsmith OIDC credentials.

For each runtime image below, open **Package settings > Manage Actions access**,
add `eqtylab/deployment`, and select the **Read** role. Package access inherited
from `eqtylab/guardian` does not grant the deployment workflow access. A successful
`oras login ghcr.io` confirms authentication, not permission to read these images.

- [auth-service](https://github.com/orgs/eqtylab/packages/container/auth-service/settings)
- [governance-service](https://github.com/orgs/eqtylab/packages/container/governance-service/settings)
- [governance-studio](https://github.com/orgs/eqtylab/packages/container/governance-studio/settings)
- [integrity-service](https://github.com/orgs/eqtylab/packages/container/integrity-service/settings)
- [eqty-pdfgen](https://github.com/orgs/eqtylab/packages/container/eqty-pdfgen/settings)
- [guardian-llm-gateway](https://github.com/orgs/eqtylab/packages/container/guardian-llm-gateway/settings)
- [guardian-control-plane](https://github.com/orgs/eqtylab/packages/container/guardian-control-plane/settings)
- [guardian-console](https://github.com/orgs/eqtylab/packages/container/guardian-console/settings)

The grant covers the image and its signature/attestation tags within that
package. Check all eight to avoid fixing one only to fail on the next image.
Private chart packages selected by the release also need deployment Actions
access; charts published by deployment normally already have it. Keep the
packages private and retain their existing access grants.

See GitHub's [package Actions access documentation](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility#ensuring-workflow-access-to-your-package).
These grants are GitHub package settings, not repository files or Cloudsmith
policies. After correcting only package permissions, the failed mirror run can
be rerun; no release rebuild or new tag is needed. A local preview using a
developer's credentials cannot validate the workflow token's access.

The Cloudsmith action and CLI are pinned. The action masks the temporary token
and exports it for registry clients; registry logins use stdin and isolated
runner-temp credential files. Source code is always checked out from the trusted
mirror workflow commit on main, never from the triggering run's artifacts.

## Preview and activation

1. Merge the infrastructure customer configuration changes and sync the selected
   shared paths into deployment alongside the publisher changes. Keep the flag
   absent or false.
2. Dispatch the mirror workflow on main with a published stable `version` and
   `publish=false`. Inspect the `cloudsmith-inventory` Actions artifact and job
   summary. This downloads release files and verifies images and provenance,
   but never calls Cloudsmith.
3. After separate authorization, configure OIDC/GHCR access, enable the flag,
   and dispatch that version with `publish=true`. Verify customer entitlement
   access and the Helm install path before customer handoff. This live test has
   deliberately not been performed as part of implementation.
4. Subsequent successful stable publications mirror automatically. Disabling
   the flag stops future publishing jobs; it does not cancel a job already
   uploading or remove existing artifacts.

There is no automatic historical backfill. Manual promotion enforces the same
stable version, approved tagged manifest, published release, and main ancestry
requirements as automatic promotion. Historical releases without Guardian source
metadata or GitHub asset checksums need a new release, not a bypass.

## Retry a failed delivery or mirror a historical release

After merging a workflow fix, dispatch the mirror from **main** with the existing
published version. GitHub's **Re-run jobs** uses the original workflow commit,
so it will not pick up a fix merged after that run. Do not rerun the packaging
workflow or move the release tag to retry a Cloudsmith delivery.

For example, preview the existing `platform/v1.2.1` release:

```bash
gh workflow run mirror-cloudsmith-release.yaml \
  --repo eqtylab/deployment --ref main \
  -f version=1.2.1 -f publish=false
gh run list --repo eqtylab/deployment \
  --workflow mirror-cloudsmith-release.yaml --event workflow_dispatch --limit 5
```

Inspect that run's `cloudsmith-inventory` artifact and summary. When the required
OIDC policies and GHCR package access above are configured, enable publishing
and dispatch the same version:

```bash
gh variable set CLOUDSMITH_PUBLISH_ENABLED --repo eqtylab/deployment --body true
gh workflow run mirror-cloudsmith-release.yaml \
  --repo eqtylab/deployment --ref main \
  -f version=1.2.1 -f publish=true
```

Enabling the variable also enables automatic mirroring of subsequent successful
stable publications. A successful preview alone does not upload anything.

For a historical release, replace `1.2.1` in both dispatches with its version
(for example, `1.2.0`), keeping `--ref main`. Manual dispatch reads that version's
existing release assets and approved tagged manifest; it does not require the
original Actions run or publication receipt to remain available. The same
integrity requirements apply, including Guardian source metadata, image
signatures, asset checksums, and recorded chart OCI digests. Older releases that
lack these inputs cannot be backfilled by bypassing verification.

Delivery is complete only when the publish job succeeds and
`cloudsmith-delivery.json` is attached to that GitHub release. If publishing is
skipped, check that the repository variable is exactly `true` and the dispatch
used `publish=true`. For an interrupted upload, dispatch the same version again;
matching existing artifacts are reused.

## Integrity and retries

Charts are uploaded with `cloudsmith push helm` to the native Helm repository at
`https://dl.cloudsmith.io/basic/eqtylab/prod/helm/charts/`. Images remain under
`docker.cloudsmith.io/eqtylab/prod/<name>:<version>`. Native Helm packages and
Docker images are separate package formats, so shared names and versions do not
collide. The previous `helm.oci.cloudsmith.io` endpoint returned HTTP 500 during
chart lookups, before any artifacts were uploaded.

The publish job authenticates the native Helm repository using its short-lived
Cloudsmith OIDC credential. Each chart must finish processing and appear in the
Helm index before it is pulled and its archive checksum is verified. The job
waits up to five minutes for each stage, including index propagation to the CDN.

For historical releases, follow the current installation guide and locations in
`cloudsmith-delivery.json`. Older packaged instructions may still mention the
Helm OCI endpoint. The original release archives and checksums remain unchanged.

Images are copied by digest with ORAS, including all platforms and OCI
referrers. Cosign 2.x `.sig`, `.att`, and `.sbom` tags are inventoried and copied
explicitly. Source signatures must verify against Guardian's image build
workflow. Charts use their released archive bytes and recorded GHCR digests;
the delivery manifest records each native Helm package ID, repository, name,
version, and identical archive checksum alongside its original GHCR source.

All original GitHub release assets are copied as versioned raw packages. Names
are lowercase filenames, prefixed with `governance-platform-` only if that prefix
is not already present. For example, the archive package is
`governance-platform-v1.2.0.tar.gz`; the manifest package is
`governance-platform-release-manifest.yaml`. Available GitHub attestation bundles are also
exported as raw packages and attached additively to the GitHub release.
The original signed manifests, archives, and checksums are not rewritten.

The schema-validated `cloudsmith-delivery.json` completion marker (schema version
2 for native Helm delivery) is published
after verification and retained on GitHub. It has deterministic contents and
credential-free download URLs. The marker is absent for incomplete deliveries.
Cloudsmith is not transactional: partial artifacts can exist before the marker.

Retry the **mirror workflow**, not the packaging workflow. A shared per-version
concurrency group serializes the packaging workflow and automatic/manual mirror
publishing, including tag-triggered and manually dispatched packaging attempts. Identical existing artifacts
are reused; conflicting hashes, authentication failures, quarantined Helm or raw
packages, and unexpected registry errors stop the run. No force overwrite or
delete operation is used. A mismatch requires investigation or a new release
version. The source publisher rejects versions with an existing delivery marker before
chart publication and again before GitHub asset replacement. Its pre-delivery
`--clobber` behavior cannot replace a completed delivery; publish a new version
instead. Retry partial deliveries through the mirror, preserving the source bytes.

Upstream runtime images and separately hosted documentation snapshots are not
mirrored. Custody keeps its independent version and is included only when
selected. Viper's independent publication workflow is unaffected.

## Customer download contract

This repository owns raw package naming, the delivery schema, and download URLs.
The infrastructure-owned `docs/cloudsmith.md` links here so changes to this
contract do not require two independently maintained descriptions.

Raw packages use the naming rule above and the platform version. The delivery
manifest has this credential-free authenticated URL:

```text
https://dl.cloudsmith.io/basic/eqtylab/prod/raw/names/governance-platform-cloudsmith-delivery.json/versions/<version>/cloudsmith-delivery.json
```

Use HTTP basic authentication with username `token` and the prod entitlement as
password, through an approved credential store. The manifest records original
sources, image digests and attachments, native Helm repository and package
identifiers, chart archive hashes, and raw file names, package identifiers,
hashes and download URLs. The
archive and checksum package names are their lowercase filenames without an
extra `governance-platform-` prefix. Original checksum contents retain the release
publisher's `dist/` paths.

## Local validation

```bash
python -B -m unittest discover -s scripts/release -p 'test_*.py' -v
actionlint .github/workflows/mirror-cloudsmith-release.yaml .github/workflows/release-platform-package.yaml
```

Install `PyYAML==6.0.3` and `jsonschema==4.26.0` for the unit tests. The optional
registry integration test uses two disposable localhost registries and pinned
ORAS; it never contacts Cloudsmith. Helm CI also checks Cloudsmith render paths.
