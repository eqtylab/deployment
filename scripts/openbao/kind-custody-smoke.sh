#!/usr/bin/env bash
# Disposable kind smoke for charts/openbao-custody: installs the chart with TLS
# and three Raft replicas, initializes with a single share (smoke only),
# creates a Transit key, uninstalls, verifies the PersistentVolumeClaims
# survive, reinstalls, unseals and reads the same key back, then runs the
# upstream chart test and deletes the cluster. Requires kind, kubectl, helm,
# openssl and Docker. Never point it at a real cluster: it creates its own.
# This fixture deliberately uses the default release/resource names; override
# and alternate release-name coverage lives in test-custody-chart.py.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do SOURCE="$(readlink "$SOURCE")"; done
ROOTDIR="$(cd -P "$(dirname "$SOURCE")/../.." && pwd)"

KIND="${KIND:-kind}"
CLUSTER="openbao-custody-smoke-$(date +%Y%m%d%H%M%S)"
WORK="$(mktemp -d)"
export KUBECONFIG="$WORK/kubeconfig"
CHART="$ROOTDIR/charts/openbao-custody"
NS=custody
cleanup() { echo "== cleanup"; $KIND delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

helm repo add openbao https://openbao.github.io/openbao-helm

echo "== create kind cluster $CLUSTER"
$KIND create cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" --wait 90s
kubectl create namespace $NS

echo "== TLS material (self-signed CA + server cert with the documented SANs)"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$WORK/ca.key" -out "$WORK/ca.crt" -days 2 -subj "/CN=guardian-h1-smoke-ca" >/dev/null 2>&1
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$WORK/tls.key" -out "$WORK/tls.csr" -subj "/CN=openbao-custody" >/dev/null 2>&1
cat > "$WORK/san.cnf" <<SAN
subjectAltName=DNS:openbao-custody,DNS:openbao-custody.$NS.svc,DNS:openbao-custody.$NS.svc.cluster.local,DNS:openbao-custody-active,DNS:openbao-custody-active.$NS.svc,DNS:openbao-custody-active.$NS.svc.cluster.local,DNS:*.openbao-custody-internal,DNS:*.openbao-custody-internal.$NS.svc,DNS:*.openbao-custody-internal.$NS.svc.cluster.local,IP:127.0.0.1
SAN
openssl x509 -req -in "$WORK/tls.csr" -CA "$WORK/ca.crt" -CAkey "$WORK/ca.key" -CAcreateserial -out "$WORK/tls.crt" -days 2 -extfile "$WORK/san.cnf" >/dev/null 2>&1
kubectl -n $NS create secret generic openbao-custody-tls --from-file=tls.crt="$WORK/tls.crt" --from-file=tls.key="$WORK/tls.key" --from-file=ca.crt="$WORK/ca.crt"

install() {
  helm dependency build "$CHART" >/dev/null
  helm upgrade --install openbao-custody "$CHART" -n $NS \
    --set 'openbao.server.affinity=' \
    --set openbao.server.resources.requests.cpu=50m \
    --set openbao.server.resources.requests.memory=128Mi \
    --set openbao.server.dataStorage.size=1Gi \
    --set openbao.server.auditStorage.size=1Gi >/dev/null
}
wait_pod() { kubectl -n $NS wait --for=jsonpath='{.status.phase}'=Running "pod/$1" --timeout=180s >/dev/null; }
bao() { kubectl -n $NS exec "$1" -- bao "${@:2}"; }
unseal() { bao "$1" operator unseal "$UNSEAL" >/dev/null; }

echo "== install (HA, TLS)"
install
wait_pod openbao-custody-0
sleep 5
echo "== init with one share (smoke only) and unseal pod 0"
INIT=$(bao openbao-custody-0 operator init -key-shares=1 -key-threshold=1 -format=json)
UNSEAL=$(echo "$INIT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["unseal_keys_b64"][0])')
ROOT=$(echo "$INIT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["root_token"])')
unseal openbao-custody-0
kubectl -n $NS wait --for=condition=Ready pod/openbao-custody-0 --timeout=120s >/dev/null
for i in 1 2; do wait_pod openbao-custody-$i; sleep 8; unseal openbao-custody-$i; kubectl -n $NS wait --for=condition=Ready pod/openbao-custody-$i --timeout=120s >/dev/null; done
echo "== raft peers"
kubectl -n $NS exec openbao-custody-0 -- env BAO_TOKEN="$ROOT" bao operator raft list-peers
echo "== TLS check from inside the pod against the active service via the CA"
kubectl -n $NS exec openbao-custody-0 -- env BAO_ADDR=https://openbao-custody-active.$NS.svc.cluster.local:8200 bao status | grep -E 'Sealed|HA Mode|Raft'
echo "== declarative audit device present, enable transit and create a P-256 key"
kubectl -n $NS exec openbao-custody-0 -- env BAO_TOKEN="$ROOT" bao audit list | grep -E 'file'
kubectl -n $NS exec openbao-custody-0 -- env BAO_TOKEN="$ROOT" bao secrets enable -path=guardian-did transit >/dev/null
kubectl -n $NS exec openbao-custody-0 -- env BAO_TOKEN="$ROOT" bao write -f guardian-did/keys/smoke type=ecdsa-p256 exportable=false allow_plaintext_backup=false >/dev/null
PUB1=$(kubectl -n $NS exec openbao-custody-0 -- env BAO_TOKEN="$ROOT" bao read -field=keys guardian-did/keys/smoke)
echo "public key before uninstall: $(printf %s "$PUB1" | shasum -a 256 | cut -c1-16)"
echo "== helm uninstall"
helm uninstall openbao-custody -n $NS >/dev/null
kubectl -n $NS wait --for=delete pod -l app.kubernetes.io/instance=openbao-custody --timeout=180s >/dev/null 2>&1 || true
until [ "$(kubectl -n $NS get pod -l app.kubernetes.io/instance=openbao-custody -o name | wc -l | tr -d ' ')" = "0" ]; do sleep 2; done
echo "PVCs after uninstall:"; kubectl -n $NS get pvc -o name
test "$(kubectl -n $NS get pvc -o name | wc -l | tr -d ' ')" = "6"
echo "== reinstall and unseal"
install
wait_pod openbao-custody-0
sleep 5
unseal openbao-custody-0
kubectl -n $NS wait --for=condition=Ready pod/openbao-custody-0 --timeout=120s >/dev/null
for i in 1 2; do wait_pod openbao-custody-$i; sleep 8; unseal openbao-custody-$i; kubectl -n $NS wait --for=condition=Ready pod/openbao-custody-$i --timeout=120s >/dev/null; done
PUB2=$(kubectl -n $NS exec openbao-custody-0 -- env BAO_TOKEN="$ROOT" bao read -field=keys guardian-did/keys/smoke)
echo "public key after reinstall: $(printf %s "$PUB2" | shasum -a 256 | cut -c1-16)"
test "$PUB1" = "$PUB2" && echo "RETENTION OK: same Transit key material after uninstall/reinstall"
kubectl -n $NS exec openbao-custody-0 -- env BAO_TOKEN="$ROOT" bao audit list | grep -q file && echo "AUDIT DEVICE PRESENT AFTER REINSTALL"
sleep 20; echo "== raft peers after reinstall"; kubectl -n $NS exec openbao-custody-0 -- env BAO_TOKEN="$ROOT" bao operator raft list-peers
echo "== chart tests"
helm test openbao-custody -n $NS 2>&1 | tail -3
echo "H1 SMOKE PASSED"
