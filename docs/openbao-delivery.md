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
The existing external-only air-gap scaffold remains unchanged.

## Customer package and operator setup

Both connected modes include these paths, preserving relative imports:

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
for writes, and Python 3 for external endpoint validation. The policy grants
only dedicated Transit key operations, signing, self-renewal, and
`sys/capabilities-self` update for Auth's health check. Tokens still have no
default policy or other-token capability lookup. The health grant is synced
from guardian-infrastructure commit
`752913f961dc60b51a85cb731c0505e5f5f35f31`.

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
python scripts/openbao/test-custody-chart.py
python -B -m unittest discover -s scripts/release -p 'test_*.py' -v
python scripts/release/custody_distribution.py validate-manifests releases/v*/release-manifest.yaml
```

CI runs locked dependency builds before linting or packaging, the synced custody
render/NOTES/archive tests, historical and opt-in manifest regressions, and the
actual release workflow's dry-run chart/customer-package steps using temporary
platform chart fixtures and the real custody chart. The extracted-package check
runs the distributed operator script in dry-run mode, compares its policy/helper
bytes to source, checks optional inclusion and chart hashes/locks, and renders
the supplied archive without a cluster. It also runs in the release workflow
before customer archive publication. No credentials or live fixtures are needed.

Charts and `scripts/openbao/` are owned upstream and synced from
`eqtylab/guardian-infrastructure`. The workflow, schema and
`scripts/release/` distribution checks are owned here; keep them outside synced
directories so a source sync cannot remove the downstream validation.
