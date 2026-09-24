# OpenBao Custody

## Description

Separately managed [OpenBao](https://openbao.org) release that holds Guardian
Auth's DID signing keys in a Transit mount. It pins the upstream
[`openbao/openbao`](https://github.com/openbao/openbao-helm) chart (0.29.5,
OpenBao 2.6.2) and configures a cloud-independent baseline: three-node
integrated Raft storage, TLS on every listener, a retained audit volume,
persistent volumes that outlive the Helm release, and no agent injector, CSI
provider or UI.

This chart is **not** a dependency of `governance-platform`. Install it as its
own release in its own namespace so that installing, upgrading or uninstalling
the platform can never touch key material. A customer-managed OpenBao that
meets the same contract (see the Auth chart README, "OpenBao Transit") is an
equally valid endpoint; this chart is the supplied-cluster option.

This is an **optional development integration**, not an approved production
rollout. The operational baseline and runbook below support evaluation; seal,
backup, restore and recovery decisions still require validation before a pilot.

## Configuration Model

Values under `openbao` configure the pinned upstream subchart. Its server HCL
is rendered into a ConfigMap, with TLS supplied through a pre-created Secret.
Helm never initializes or unseals the server or creates Auth's keys. Operators
configure the auth mount, policy and role separately with temporary credentials.

## Prerequisites

- Helm 4.0+ and `kubectl`; the operator steps also require the `bao` CLI.
- Kubernetes 1.30+ for **this supplied custody chart**: pinned upstream chart
  0.29.5 itself declares `kubeVersion: ">= 1.30.0-0"`. The platform minimum
  remains 1.29, and external OpenBao support does not require this chart.
  PVC retention policy was [beta in 1.27](https://kubernetes.io/blog/2023/05/04/kubernetes-1-27-statefulset-pvc-auto-deletion-beta/)
  and [stable in 1.32](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#persistentvolumeclaim-retention),
  not GA in 1.27. On 1.30/1.31 keep the default-enabled
  `StatefulSetAutoDeletePVC` feature gate enabled.
- A default or named StorageClass with `ReadWriteOnce` volumes, and three nodes
  in distinct failure domains for the default anti-affinity.
- A TLS Secret `openbao-custody-tls` in the release namespace with `tls.crt`,
  `tls.key` and `ca.crt`. The certificate must cover the pod, headless and
  service names, for a release in namespace `custody`:

  ```
  openbao-custody, openbao-custody.custody.svc, openbao-custody.custody.svc.cluster.local
  openbao-custody-active, openbao-custody-active.custody.svc, openbao-custody-active.custody.svc.cluster.local
  *.openbao-custody-internal, *.openbao-custody-internal.custody.svc, *.openbao-custody-internal.custody.svc.cluster.local
  127.0.0.1 (IP SAN, for the in-pod CLI)
  ```

  With cert-manager:

  ```yaml
  apiVersion: cert-manager.io/v1
  kind: Certificate
  metadata:
    name: openbao-custody-tls
    namespace: custody
  spec:
    secretName: openbao-custody-tls
    issuerRef: { name: <your-ca-issuer>, kind: ClusterIssuer }
    commonName: openbao-custody
    dnsNames:
      - openbao-custody
      - openbao-custody.custody.svc
      - openbao-custody.custody.svc.cluster.local
      - openbao-custody-active
      - openbao-custody-active.custody.svc
      - openbao-custody-active.custody.svc.cluster.local
      - "*.openbao-custody-internal"
      - "*.openbao-custody-internal.custody.svc"
      - "*.openbao-custody-internal.custody.svc.cluster.local"
    ipAddresses: ["127.0.0.1"]
  ```

  cert-manager writes `ca.crt` for issuers that expose their CA; otherwise add
  it to the Secret yourself. The same `ca.crt` is what the Auth chart mounts
  as `config.keyManagement.openbao.ca`.

## Deployment

```bash
helm repo add openbao https://openbao.github.io/openbao-helm
helm dependency build charts/openbao-custody
helm upgrade --install openbao-custody charts/openbao-custody \
  --namespace custody --create-namespace \
  --values my-custody-values.yaml
```

The pods start sealed and uninitialized; with the default `OrderedReady`
StatefulSet policy, pod 1 is created only after pod 0 is unsealed and ready,
and pod 2 after pod 1. Complete the operator steps below in order.

## Values

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `openbao.fullnameOverride` | string | `openbao-custody` | Stable default; override updates resources, Raft joins and NOTES; also update TLS SANs and Auth address |
| `openbao.global.tlsDisable` | bool | `false` | TLS on API and cluster listeners |
| `openbao.server.image.tag` | string | `2.6.2` | OpenBao version, pinned |
| `openbao.server.ha.replicas` | int | `3` | Raft voters (DECISION: failure domains) |
| `openbao.server.ha.raft.config` | string | HCL | Listener TLS files, Raft `retry_join`, Kubernetes service registration, declarative file audit device |
| `openbao.server.dataStorage` / `openbao.server.auditStorage` | object | Each: `enabled: true`, `size: 10Gi`, `storageClass: null`, `accessMode: ReadWriteOnce` | Persistent data and audit volumes (DECISION: class, size) |
| `openbao.server.persistentVolumeClaimRetentionPolicy` | object | `Retain`/`Retain` | Volumes survive uninstall and scale-down |
| `openbao.server.authDelegator.enabled` | bool | `true` | TokenReview for the Kubernetes auth method |
| `openbao.server.volumes` / `openbao.server.volumeMounts` | list | `openbao-custody-tls` Secret | TLS material under `/openbao/userconfig/openbao-custody-tls` (also mounted in the `helm test` pod) |
| `openbao.server.networkPolicy.enabled` | bool | `false` | Default ingress allows all namespaces on 8200/8201; see restrictive example |
| `openbao.injector.enabled` / `openbao.csi.enabled` / `openbao.ui.enabled` | bool | `false` | Not used by Guardian |

Any upstream value can be set under `openbao.`; see
`helm show values openbao/openbao --version 0.29.5`.
`examples/values-dev-kind.yaml` is a single-node, TLS-disabled profile for
disposable development clusters only. `examples/values-kind-tls.yaml` keeps the
wrapper's TLS/Raft/audit settings with three voters on one disposable host (a
topology simulation, not host-failure HA); do not layer `values-dev-kind.yaml`
over it.

## Configuration Inheritance

This chart has no platform globals or umbrella dependency. All upstream options
are nested under `openbao`, including `openbao.global`. Configure Auth's endpoint,
CA, mount, role and audience in the Auth release separately. Neither release
owns the other's configuration or storage.

### Resource names and certificates

The runbook and Certificate example use release `openbao-custody`, namespace
`custody`, and the default `openbao.fullnameOverride: openbao-custody`. For another
installation, set these shell variables to the **rendered StatefulSet name** and
server namespace from `helm template` or `helm get notes` before running commands:

```bash
CUSTODY_NAME=openbao-custody
CUSTODY_NAMESPACE=custody
```

Naming follows upstream exactly: `fullnameOverride` wins; otherwise
`nameOverride` (default `openbao`) is combined with the release name unless the
release name already contains it. Upstream truncation also applies. NOTES and
the default Raft HCL use those rendered names, including one retry-join target
per configured replica. If you supply your own HCL, maintain its join addresses.

For any name or namespace change, update **all** SANs in the Certificate example
above and Auth's configured address to
`https://<fullname>-active.<namespace>.svc.cluster.local:8200`. The Secret name
and mounted TLS paths stay `openbao-custody-tls` unless you change the volume,
mount, HCL file paths and `BAO_CACERT` together. Avoid `openbao.global.namespace`
overrides; install directly into the intended namespace. If used, the upstream
namespace override also affects NOTES and where the Secret must exist.

Keep the HA server and active service enabled for this integration. Other
upstream operating modes and disabled services require their own runbook.
Changing names on an existing release changes PVC identities: it does not move
or reattach the previous keys. Reinstall using the same namespace and rendered
StatefulSet name with the same storage settings.

### Network policy

By default no NetworkPolicy is created. Merely enabling the default policy
allows every namespace on API port 8200 and cluster port 8201; it does not limit
access to Auth. [examples/values-network-policy.yaml](examples/values-network-policy.yaml)
restricts API ingress to the `governance` namespace, while allowing same-release
Bao peers in the custody namespace on **both** ports (retry-join uses 8200,
Raft and forwarding use 8201).

Adapt the Auth namespace label and the peer `app.kubernetes.io/instance`
(**release** name) and `app.kubernetes.io/name` (`openbao.nameOverride`) labels
before use. `fullnameOverride` does not change either label. The example leaves
egress unrestricted for DNS, TokenReview and service registration. If your
cluster isolates egress, allow those destinations and peer traffic explicitly;
Auth also needs egress to Bao. External operator or monitoring pods need their
own narrowly scoped API ingress rule. NetworkPolicy requires an enforcing CNI;
the local render checks do not prove packet-level enforcement.

## Operator runbook

Everything here is an operator procedure with a short-lived operator token.
Nothing is automated by Auth startup or by Helm hooks; no permanent root
token exists in pods, values or Jobs.

### 1. Initialize (once)

```bash
kubectl -n "$CUSTODY_NAMESPACE" exec "$CUSTODY_NAME-0" -- \
  bao operator init -key-shares=5 -key-threshold=3 -format=json > init.json
```

Distribute the unseal shares to five named custodians, record the threshold
and custody arrangement outside the cluster, and delete `init.json`. The
initial root token is used only for the steps below and revoked at the end.

### 2. Unseal every replica

```bash
# Default three replicas. Repeat the prompted command for each required share.
# Wait for each pod to exist before continuing to the next ordinal.
for i in 0 1 2; do
  kubectl -n "$CUSTODY_NAMESPACE" exec -it "$CUSTODY_NAME-$i" -- bao operator unseal
  kubectl -n "$CUSTODY_NAMESPACE" exec -it "$CUSTODY_NAME-$i" -- bao operator unseal
  kubectl -n "$CUSTODY_NAMESPACE" exec -it "$CUSTODY_NAME-$i" -- bao operator unseal
done
```

Pods 1 and 2 join the Raft cluster through `retry_join` and only need
unsealing. Every restart of a pod requires unsealing again under the Shamir
seal (see "Seal decision").

### 3. Verify the audit device

The file audit device is declared in the server configuration
(`audit "file" "file"` in `openbao.server.ha.raft.config`), because OpenBao 2.6
refuses audit devices created through the API. It is created on the active
node at start-up. From an operator environment able to reach the internal
service, set the CLI address and CA, then authenticate with the initial root
token using your local credential workflow. Create a short-lived operator token
and confirm the audit device and Raft peers:

```bash
export BAO_ADDR="https://$CUSTODY_NAME-active.$CUSTODY_NAMESPACE.svc.cluster.local:8200"
export BAO_CACERT=./ca.crt
# Authenticate the local CLI first; do not put the credential in pod configuration.
export BAO_TOKEN=$(bao token create -ttl=1h -policy=root -field=token)   # or a narrower admin policy
bao audit list
bao operator raft list-peers
```

The audit volume is retained like the data volume. Ship
`/openbao/audit/audit.log` to the customer's log pipeline; OpenBao refuses
requests when no enabled audit device can be written, so monitor the volume
(H6).

### 4. Configure the Auth mount, policy and role

Use the companion `scripts/openbao/configure-auth.sh` operator tooling from
[infrastructure PR #115](https://github.com/eqtylab/guardian-infrastructure/pull/115),
including `scripts/helpers/output.sh` and its policy file. That tooling is a
separate change, not bundled in this chart archive; use a checkout containing it.
The script is intended to be idempotent and leave existing keys untouched.
Using the authenticated operator CLI environment from step 3:

```bash
scripts/openbao/configure-auth.sh --service-account governance-auth-service \
  --namespace governance --audience openbao \
  --transit-mount guardian-did --auth-mount kubernetes --role guardian-auth
```

**In-cluster auth configuration:** the companion #115 script writes
`auth/kubernetes/config` itself, including on a fresh mount. With
`--kubernetes-host` omitted, it sets `https://kubernetes.default.svc:443`, enables
the server's local token and CA, and clears any previously configured external
reviewer token and CA. Verify with `bao read auth/kubernetes/config` before Auth
logs in (adapt the path for a custom auth mount).

For older tooling that only enables the mount and creates the role, the config
write remains a prerequisite. On a fresh mount, this manual alternative supplies
the missing configuration:

```bash
bao write auth/kubernetes/config \
  kubernetes_host=https://kubernetes.default.svc:443 \
  disable_local_ca_jwt=false
bao read auth/kubernetes/config
```

This example is for a fresh mount only: a reused mount with explicit reviewer
JWT/CA settings needs an operator review before changing configuration.
In-cluster OpenBao uses its own projected service-account token and local CA
(`authDelegator` is enabled); neither a reviewer JWT copied from a pod nor the
Auth login token belongs in this config. The script's external-Bao flags are
for a separate auth configuration and must not be used to disable local token
loading for this in-cluster path. See the upstream
[local reviewer-token configuration](https://openbao.org/docs/auth/kubernetes/#use-local-service-account-token-as-the-reviewer-jwt).
Then set
the Auth chart values (`config.keyManagement.openbao.address:
https://openbao-custody-active.custody.svc.cluster.local:8200`, the CA
ConfigMap/Secret, mount, role and audience) as described in
`charts/auth-service/README.md`.

### 5. Revoke the root token

Revoke the initial root token through your authenticated operator CLI, then
revoke the temporary operator token and clear it from the environment. Do not
store either token in a pod, chart value or Job.

Generate a new one only through `bao operator generate-root` with the
custodians present.

## Storage retention

`openbao.server.persistentVolumeClaimRetentionPolicy` is `Retain` for both delete and
scale-down, so `helm uninstall openbao-custody` leaves the `data-*` and
`audit-*` PersistentVolumeClaims in place, and a reinstall with the same
namespace and rendered StatefulSet name (including overrides) reattaches them;
the cluster only needs unsealing again. Delete
the PVCs only as a deliberate, recorded destruction step.
`scripts/openbao/kind-custody-smoke.sh` reproduces the check on a disposable
kind cluster: a Transit key created before `helm uninstall` is readable after
reinstall with the same public key, the declarative audit device is present,
the three Raft peers rejoin as voters and the upstream chart test passes.

## Upgrade

`openbao.server.updateStrategyType` is `OnDelete`. To upgrade OpenBao or the chart:

1. bump `openbao.server.image.tag` and/or the dependency version, run
   `helm dependency update charts/openbao-custody` to deliberately refresh the
   lock, review the lock diff, then `helm upgrade`; normal lint/package/install
   steps use `helm dependency build` instead;
2. delete the standby pods one at a time and unseal each replacement;
3. `bao operator step-down` on the active node, delete it, unseal the
   replacement;
4. check `bao operator raft list-peers` and `bao status` on every pod.

Take a Raft snapshot first (`bao operator raft snapshot save`). Do not
downgrade binaries against a newer Raft data format; restore from a snapshot
taken with the older version instead. Automation of snapshots, restore and
seal-recovery rehearsal is H5.

## Seal decision

The default has no `seal` stanza: Shamir shares, cloud-independent, manual
unseal after every restart. Alternatives to record in the on-prem workbook
before the pilot: transit auto-unseal from a second, independently operated
OpenBao (avoid a circular dependency on the same sealed cluster), PKCS#11 with
a customer HSM, or a cloud KMS seal where a cloud dependency is acceptable.
Custody of shares or recovery keys is documented independently of the Raft
volume; the local development launcher's automated unseal is never used in
production.

## Troubleshooting

- **Missing dependency:** run `helm dependency build charts/openbao-custody`;
  do not refresh the lock merely to fix a clean checkout.
- **Unsupported Kubernetes version:** this upstream pin requires 1.30+.
  Use a compatible external OpenBao with the platform on 1.29.
- **Only pod 0 exists / pods are unready:** initialize once and unseal each pod
  in order. `OrderedReady` delays the next pod until the previous pod is ready.
- **TLS or Raft join failure after a rename:** compare rendered ConfigMap joins,
  StatefulSet/Service names and certificate SANs; inspect NetworkPolicy peer
  labels and ports before changing the server configuration.
- **Kubernetes login fails:** check `auth/<mount>/config`, the API host, server
  TokenReview RBAC, and the role's service account, namespace and audience.
  A mount and role without the config write are insufficient on a fresh server.
- **Audit writes fail:** check free space and permissions on the retained audit
  volume; a full audit device can stop requests.

Use `kubectl -n "$CUSTODY_NAMESPACE" logs "$CUSTODY_NAME-0"` and authenticated
`bao status` / `bao operator raft list-peers` from the operator environment.
Commands such as `bao audit list` and `raft list-peers` require an authenticated
CLI; `kubectl exec` does not forward your local `BAO_TOKEN`. Use a temporary
operator CLI session for authenticated commands, not a token in pod configuration.

## Health Endpoints

OpenBao exposes [`/v1/sys/health`](https://openbao.org/api-docs/system/health/)
on port 8200. By default it returns 200 for an
active unsealed node, 429 for a standby, 501 before initialization, and 503 when
sealed. The upstream readiness probe uses `bao status`; inspect the rendered
StatefulSet when customizing probes. Do not treat sealed/uninitialized responses
as healthy to make rollout checks pass. The active Service routes to the elected
active node; the headless internal Service is for peer discovery.

## Support

- **Email**: support@eqtylab.io
- **Documentation**: https://docs.eqtylab.io
- **GitHub Issues**: https://github.com/eqtylab/guardian-infrastructure/issues
- **Local checks**: `just test-openbao-custody` (Helm, Python 3 and PyYAML);
  validates templates, NOTES, name overrides and package contents without a cluster.
