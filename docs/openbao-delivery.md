# Optional OpenBao custody delivery

OpenBao is optional and development-only. The `governance-platform` chart does
not install custody as a dependency. A compatible application release and
explicit OpenBao values are required even when the custody archive is supplied.
Packaging and render checks do not qualify a live deployment.

## Selection and independent versions

Omitting `charts.openbaoCustody` from a release manifest excludes custody from
both OCI publication and the connected customer package. Existing manifests keep
that behavior. If OpenBao is selected for such a package, the operator supplies
and qualifies an external endpoint. Other signing backends are unaffected.

To supply custody, a release maintainer adds this entry to a **new** candidate
manifest after choosing compatible artifacts (example only):

```yaml
charts:
  openbaoCustody:
    name: openbao-custody
    version: 0.1.0
    oci: oci://ghcr.io/eqtylab/charts/openbao-custody
```

The version must match `charts/openbao-custody/Chart.yaml`, independently of the
platform version. The wrapper currently pins OpenBao chart **0.29.5**, server
**2.6.2**, and Kubernetes **1.30+**. This does not raise the platform or external
endpoint minimum. Do not add custody to the platform's version equality loop,
its image tag loop, or the umbrella dependency list.

When selected, the normal release workflow packages/publishes
`openbao-custody-<wrapper-version>.tgz`, records its own version, package SHA-256
and OCI digest in `chart-digests.yaml`, and includes it in the connected tarball.
`publish=false` creates packages without OCI/GitHub publication and explicitly
records `ociDigest: dry-run`. Existing OCI versions are pulled for packaging;
the final archive check rejects any payload drift from a fresh package of the
checked source (tar timestamps and metadata YAML formatting may differ).
Actual chart/image digests and architecture compatibility still belong in the
candidate evidence. A tag or a successful render is not release approval.

Supplied custody plus `build_airgap=true` is refused: custody image mirroring,
source/notices, and offline installation are not qualified by this workflow.
The existing external-only air-gap scaffold remains unchanged: the air-gap
tarball carries platform charts, the manifest and the image mirror script only.
It contains no custody chart, no `scripts/openbao/` directory and no
`OPENBAO.md`. An air-gap customer who selects OpenBao therefore operates a
customer-managed OpenBao and takes the operator script, policy template and
README from the connected package for the same release, or from
`scripts/openbao/` in this repository at that release tag.

## Customer package and operator setup

The connected package includes these paths whether or not custody is
selected, preserving relative imports (the air-gap package does not):

```text
OPENBAO.md
scripts/openbao/configure-auth.sh
scripts/openbao/policies/guardian-auth.hcl
scripts/openbao/README.md
scripts/helpers/output.sh
```

For supplied custody, inspect the README and examples inside its chart archive
before installing it as a separate release. Use an explicit private kubeconfig
and owned cluster/namespace for development. Choose storage, TLS and seal
custodians before initialization. Disabling OpenBao in the platform does not
uninstall custody, delete its PVCs, destroy keys or migrate existing identities.

Run `bash scripts/openbao/configure-auth.sh --help` from the extracted package.
Use operator credentials separately from Auth; follow the included script
README for reviewer topology and TLS trust. The script requires Bash, `bao`
for writes, and Python 3 for external endpoint validation. The packaged
`policies/guardian-auth.hcl` is byte-identical to the synced source tree at the
release tag, and `scripts/openbao/README.md` in the same package is the
authoritative description of what it grants; this document does not restate
the grant list, so the two cannot disagree. Tokens have no default policy.

Match Auth's ServiceAccount, namespace, audience, auth mount/role and Transit
mount to the script arguments. Configure the selected endpoint and CA in Auth
values. The custody archive contains the runbook and examples; it does not
include application credentials or perform operator initialization.

## Maintainer checks

From a clean deployment checkout, use Helm 3.20.0 (the CI version), Python 3.12+,
PyYAML 6.0.3, jsonschema 4.26.0, and Mike Farah yq:

```bash
helm repo add openbao https://openbao.github.io/openbao-helm
helm dependency build charts/openbao-custody
python3 -B scripts/openbao/test-custody-chart.py
python3 -B -m unittest discover -s scripts/release -p 'test_*.py' -v
python3 -B scripts/release/custody_distribution.py validate-manifests releases/v*/release-manifest.yaml
```

CI runs locked dependency builds before linting or packaging, the synced custody
render/NOTES/archive tests, historical and opt-in manifest regressions, and the
actual release workflow's dry-run chart/customer-package steps using temporary
platform chart fixtures and the real custody chart. The extracted-package check
runs the distributed operator script in dry-run mode, compares its policy/helper
bytes to source, checks optional inclusion and chart hashes/locks, and renders
the supplied archive without a cluster. It also runs in the release workflow
before customer archive publication. No credentials or live fixtures are needed.

Charts, `govctl/`, `docs/{auth0,entra,keycloak}/`, `docs/cloudsmith.md`, and
`scripts/openbao/` are owned upstream and synced from
`eqtylab/guardian-infrastructure`. The [Cloudsmith operator runbook](cloudsmith-release.md)
owns the raw package naming and delivery URL/schema contract. The workflow, schema and
`scripts/release/` distribution checks are owned here; keep them outside synced
directories so a source sync cannot remove the downstream validation.
