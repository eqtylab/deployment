# OpenBao operator scripts

Administrative setup for Guardian Auth's OpenBao Transit provider. These run
with operator credentials; the Auth runtime never holds them.

## `configure-auth.sh`

Configures one OpenBao server for one Auth deployment:

1. enables a dedicated Transit mount (default `guardian-did`),
2. writes the scoped runtime policy from `policies/guardian-auth.hcl` with the
   mount substituted. It grants exactly four paths: P-256 key
   create/read/update and prehashed JWS signing under that mount,
   `auth/token/renew-self` for the workload token, and `update` on
   `sys/capabilities-self` so Auth's signing health check can inspect its own
   token's capabilities without the default policy. Nothing else is granted,
   and in particular no lookup of other tokens,
3. enables the Kubernetes auth method (default mount `kubernetes`) and writes
   its API host and local or external reviewer/CA configuration,
4. writes one role bound to exactly Auth's ServiceAccount, namespace and
   projected-token audience with `token_no_default_policy` and short TTLs.

Rerunning is safe: mounts are only enabled when missing, the policy and role
are updated in place, and existing keys are never touched. `--dry-run` prints
the `bao` commands.

## Usage

Requires Bash and the `bao` CLI for writes; external endpoint validation also
requires Python 3 (standard library only). Use `--help` for all options.

### In-cluster OpenBao

```bash
BAO_ADDR=https://openbao-custody-active.custody.svc.cluster.local:8200 BAO_TOKEN=... \
  ./configure-auth.sh --service-account governance-auth-service --namespace governance \
  --audience openbao --transit-mount guardian-did --auth-mount kubernetes --role guardian-auth
```

The values must match the auth-service chart: `config.keyManagement.openbao.transitMount`,
`auth.mount`, `auth.role`, `auth.audience`, and `serviceAccount.name`. The
optional separate reviewer identity (`config.keyManagement.openbao.auth.reviewer`)
is created by the chart only when `reviewer.create` is true; see the auth-service chart README, "Kubernetes auth integration".

Initialization, unsealing, storage and seal management belong to the OpenBao
release itself and are not performed here.

Without `--kubernetes-host`, the script writes the API endpoint
`https://kubernetes.default.svc:443`, `disable_local_ca_jwt=false`, and clears
previous reviewer JWT/CA values so OpenBao uses its local files. This supports a
fresh auth mount, with these prerequisites on the **OpenBao server**, regardless
of where the operator runs the script:

- It runs in the target Kubernetes cluster and can reach that API endpoint.
- Its projected service-account token and cluster CA are mounted at
  `/var/run/secrets/kubernetes.io/serviceaccount/{token,ca.crt}`.
- Its own ServiceAccount has `system:auth-delegator`. This is separate from Auth
  and from any reviewer created by the Auth chart; Auth never gets TokenReview
  permissions.

### External OpenBao

```bash
BAO_ADDR=https://openbao.example.internal:8200 \
  ./configure-auth.sh -s governance-auth-service -n governance \
  --kubernetes-host https://api.example.internal:6443 \
  --reviewer-jwt-file ./reviewer.jwt --kubernetes-ca-file ./ca.crt
```

Supply a reviewer JWT for a separate identity with `system:auth-delegator`.
A missing reviewer would fall back to the client JWT; Auth intentionally lacks
that permission, so the script refuses this combination before any writes.
For the API server TLS trust, choose exactly one:

- `--kubernetes-ca-file ./ca.crt` for a private CA, or
- `--kubernetes-system-ca` when the **OpenBao server's** system trust roots
  already trust the API certificate. This clears any previous custom CA.

The API host must be an HTTPS origin. CA/reviewer options without a host are
rejected. Supplied files must exist and be readable, nonempty regular files;
validation also runs with `--dry-run`. Neither JWT contents nor CA contents are
printed. Manage reviewer credential rotation separately. See the
[upstream Kubernetes auth reference](https://openbao.org/docs/auth/kubernetes/).

## Distribution and checks

Keep `scripts/openbao/` (including `policies/guardian-auth.hcl`) and
`scripts/helpers/output.sh` together in their repository-relative layout.
The customer sync workflow copies both. From the source repository, run:

```bash
python3 -B -m unittest discover -s tests -p test_openbao_script.py -v
```

Tests use a fake `bao` CLI to assert zero calls on invalid input, config writes
for both modes, dry-run behavior, and execution from the distributed layout.
They do not contact or modify an OpenBao server. OpenBao remains optional;
this script does not install or deploy it.
