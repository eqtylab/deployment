# Cloudsmith release mirroring

GitHub remains the build and internal distribution system. The deployment
publisher finishes chart publication, packages, attestations, and the GitHub
release before emitting `stable-publication-<run-attempt>`. The separate
`mirror-cloudsmith-release.yaml` workflow verifies that receipt and prepares an
inventory using only GitHub/GHCR reads. No receipt is emitted for prereleases or
packaging previews.

Publishing is disabled unless the **repository variable**
`CLOUDSMITH_PUBLISH_ENABLED` is exactly `true`. Manual dispatch defaults to
`publish=false`; automatic runs publish only after this variable is enabled.
Neither merging these changes nor previewing a release authenticates to
Cloudsmith while the flag is disabled.

## Configuration to perform later

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

## Integrity and retries

Images are copied by digest with ORAS, including all platforms and OCI
referrers. Cosign 2.x `.sig`, `.att`, and `.sbom` tags are inventoried and copied
explicitly. Source signatures must verify against Guardian's image build
workflow. Charts use their released archive bytes and recorded GHCR digests;
the destination OCI digest and identical archive checksum are recorded.

All original GitHub release assets are copied as versioned raw packages named
`governance-platform-<lowercase-filename>`. Available GitHub attestation bundles are also
exported as raw packages and attached additively to the GitHub release.
The original signed manifests, archives, and checksums are not rewritten.

The schema-validated `cloudsmith-delivery.json` completion marker is published
after verification and retained on GitHub. It has deterministic contents and
credential-free download URLs. The marker is absent for incomplete deliveries.
Cloudsmith is not transactional: partial artifacts can exist before the marker.

Retry the **mirror workflow**, not the packaging workflow. Per-version
concurrency serializes automatic/manual mirrors. Identical existing artifacts
are reused; conflicting hashes, authentication failures, quarantined raw
packages, and unexpected registry errors stop the run. No force overwrite or
delete operation is used. A mismatch requires investigation or a new release
version. The source publisher's existing `--clobber` behavior is not a retry
mechanism for Cloudsmith; changing released source bytes causes mirroring to
fail rather than replacing customer artifacts.

Upstream runtime images and separately hosted documentation snapshots are not
mirrored. Custody keeps its independent version and is included only when
selected. Viper's independent publication workflow is unaffected.

## Local validation

```bash
python -B -m unittest discover -s scripts/release -p 'test_*.py' -v
actionlint .github/workflows/mirror-cloudsmith-release.yaml .github/workflows/release-platform-package.yaml
```

Install `PyYAML==6.0.3` and `jsonschema==4.26.0` for the unit tests. The optional
registry integration test uses two disposable localhost registries and pinned
ORAS; it never contacts Cloudsmith. Helm CI also checks Cloudsmith render paths.
