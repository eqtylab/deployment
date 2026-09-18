#!/usr/bin/env bash
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do SOURCE="$(readlink "$SOURCE")"; done
ROOTDIR="$(cd -P "$(dirname "$SOURCE")/../.." && pwd)"

# shellcheck source=../helpers/output.sh
source "$ROOTDIR/scripts/helpers/output.sh"

POLICY_TEMPLATE="$ROOTDIR/scripts/openbao/policies/guardian-auth.hcl"

TRANSIT_MOUNT="guardian-did"
AUTH_MOUNT="kubernetes"
ROLE="guardian-auth"
POLICY_NAME="guardian-auth"
AUDIENCE="openbao"
SERVICE_ACCOUNT=""
NAMESPACE=""
KUBERNETES_HOST=""
KUBERNETES_CA_FILE=""
KUBERNETES_SYSTEM_CA=false
REVIEWER_JWT_FILE=""
TOKEN_TTL="1h"
TOKEN_MAX_TTL="4h"
DRY_RUN=false

usage() {
  echo -e "\
Configure an OpenBao server for Guardian Auth: a dedicated Transit mount, the
scoped runtime policy, the Kubernetes auth method and one role bound to Auth's
ServiceAccount, namespace and audience. Idempotent: rerunning updates the
policy and role in place and leaves existing keys untouched.

Run with operator credentials (BAO_ADDR, BAO_TOKEN or a logged-in bao CLI).
Auth itself never needs these privileges.

Usage: $0 -s <service-account> -n <namespace> [options]
  -s, --service-account <name>   Auth ServiceAccount name (required), e.g. <release>-auth-service
  -n, --namespace <namespace>    Kubernetes namespace of the Auth pods (required)
  -a, --audience <audience>      Projected token audience (default: $AUDIENCE)
  -m, --transit-mount <path>     Transit mount dedicated to Auth (default: $TRANSIT_MOUNT)
  -k, --auth-mount <path>        Kubernetes auth mount (default: $AUTH_MOUNT)
  -r, --role <name>              Role name (default: $ROLE)
  -p, --policy <name>            Policy name (default: $POLICY_NAME)
      --kubernetes-host <url>    API server URL for auth/<mount>/config (external OpenBao)
      --kubernetes-ca-file <f>   Readable, nonempty API server CA PEM (external OpenBao)
      --kubernetes-system-ca     Use OpenBao server system trust for the external API server
      --reviewer-jwt-file <f>    TokenReview reviewer JWT for auth/<mount>/config (external OpenBao)
      --token-ttl <dur>          Role token TTL (default: $TOKEN_TTL)
      --token-max-ttl <dur>      Role token max TTL (default: $TOKEN_MAX_TTL)
      --dry-run                  Print the bao commands without running them
  -h, --help                     Show this help message

Without --kubernetes-host, config is written for https://kubernetes.default.svc:443
using OpenBao's local projected service-account token and CA. The OpenBao server
must run in the target cluster with those files mounted and its own ServiceAccount
bound to system:auth-delegator. Auth's ServiceAccount must not have that role.
External mode requires --reviewer-jwt-file and exactly one CA trust choice.

Chart values that must match: config.keyManagement.openbao.transitMount,
auth.mount, auth.role and auth.audience in charts/auth-service.

Examples:
  $0 -s governance-auth-service -n governance
  $0 -s governance-auth-service -n governance --kubernetes-host https://10.0.0.1:6443 \\
     --kubernetes-ca-file ./ca.crt --reviewer-jwt-file ./reviewer.jwt
"
}

while [[ $# -gt 0 ]]; do
  # Validate every value-taking option before dereferencing $2 (set -u).
  case "$1" in
    -s|--service-account|-n|--namespace|-a|--audience|-m|--transit-mount|-k|--auth-mount|-r|--role|-p|--policy|--kubernetes-host|--kubernetes-ca-file|--reviewer-jwt-file|--token-ttl|--token-max-ttl)
      if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
        print_error "Option $1 requires a nonempty value"
        exit 1
      fi ;;
  esac
  case "$1" in
    -s|--service-account) SERVICE_ACCOUNT="$2"; shift 2 ;;
    -n|--namespace) NAMESPACE="$2"; shift 2 ;;
    -a|--audience) AUDIENCE="$2"; shift 2 ;;
    -m|--transit-mount) TRANSIT_MOUNT="$2"; shift 2 ;;
    -k|--auth-mount) AUTH_MOUNT="$2"; shift 2 ;;
    -r|--role) ROLE="$2"; shift 2 ;;
    -p|--policy) POLICY_NAME="$2"; shift 2 ;;
    --kubernetes-host) KUBERNETES_HOST="$2"; shift 2 ;;
    --kubernetes-system-ca) KUBERNETES_SYSTEM_CA=true; shift ;;
    --kubernetes-ca-file) KUBERNETES_CA_FILE="$2"; shift 2 ;;
    --reviewer-jwt-file) REVIEWER_JWT_FILE="$2"; shift 2 ;;
    --token-ttl) TOKEN_TTL="$2"; shift 2 ;;
    --token-max-ttl) TOKEN_MAX_TTL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) print_error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$SERVICE_ACCOUNT" || -z "$NAMESPACE" ]]; then
  print_error "--service-account and --namespace are required"
  usage
  exit 1
fi
component='^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$'
for value in "$TRANSIT_MOUNT" "$AUTH_MOUNT" "$ROLE" "$POLICY_NAME"; do
  if ! [[ "$value" =~ $component ]]; then
    print_error "Mount, policy and role names must be single path components (max 64 chars): $value"
    exit 1
  fi
done
# Validate all external-mode inputs before the first bao call, including dry runs.
# Explicit trust selection prevents accidental reliance on the operator machine's
# CA store: system trust here always means the OpenBao SERVER's trust store.
if [[ -n "$KUBERNETES_HOST" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    print_error "python3 is required to validate --kubernetes-host before any writes"
    exit 1
  fi
  if ! python3 - "$KUBERNETES_HOST" <<'PYTHON'
import ipaddress
import re
import sys
from urllib.parse import urlsplit

try:
    raw = sys.argv[1]
    url = urlsplit(raw)
    if (not raw.startswith("https://") or re.search(r"[\s\\]", raw)
            or "?" in raw or "#" in raw or url.username is not None
            or url.password is not None or not url.hostname
            or url.path not in ("", "/") or url.port == 0):
        raise ValueError("invalid origin")
    host = url.hostname
    if ":" in host or re.fullmatch(r"[0-9.]+", host):
        ipaddress.ip_address(host)
    else:
        labels = host.rstrip(".").split(".")
        if len(host) > 253 or any(not re.fullmatch(
                r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?", label)
                for label in labels):
            raise ValueError("invalid hostname")
    if url.netloc.endswith(":"):
        raise ValueError("empty port")
except ValueError:
    sys.exit(1)
PYTHON
  then
    print_error "--kubernetes-host must be an HTTPS origin with a valid host/port and no credentials, path, query or fragment"
    exit 1
  fi
  if [[ -z "$REVIEWER_JWT_FILE" ]]; then
    print_error "External OpenBao requires --reviewer-jwt-file; Auth has no TokenReview permissions"
    exit 1
  fi
  if [[ -z "$KUBERNETES_CA_FILE" && "$KUBERNETES_SYSTEM_CA" != true ]] ||
     [[ -n "$KUBERNETES_CA_FILE" && "$KUBERNETES_SYSTEM_CA" == true ]]; then
    print_error "External OpenBao requires exactly one of --kubernetes-ca-file or --kubernetes-system-ca"
    exit 1
  fi
elif [[ -n "$KUBERNETES_CA_FILE" || -n "$REVIEWER_JWT_FILE" || "$KUBERNETES_SYSTEM_CA" == true ]]; then
  print_error "--kubernetes-ca-file, --kubernetes-system-ca and --reviewer-jwt-file require --kubernetes-host"
  exit 1
fi
for file in "$KUBERNETES_CA_FILE" "$REVIEWER_JWT_FILE"; do
  if [[ -n "$file" ]] && { [[ ! -f "$file" || ! -r "$file" || ! -s "$file" ]] || ! grep -q '[^[:space:]]' "$file"; }; then
    print_error "CA/reviewer input must be a readable, nonempty regular file: $file"
    exit 1
  fi
done

if ! command -v bao >/dev/null 2>&1 && [[ "$DRY_RUN" != true ]]; then
  print_error "bao CLI not found on PATH"
  exit 1
fi

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '+ %q' "$1"; shift; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

# 1. Dedicated Transit mount (never shared with other applications).
if [[ "$DRY_RUN" == true ]] || ! bao secrets list -format=json | grep -q "\"$TRANSIT_MOUNT/\""; then
  print_info "Enabling Transit mount $TRANSIT_MOUNT/"
  run bao secrets enable -path="$TRANSIT_MOUNT" transit
else
  print_info "Transit mount $TRANSIT_MOUNT/ already enabled"
fi

# 2. Scoped runtime policy: create/read/update P-256 keys and prehashed JWS
#    signing under this mount, renew-self, nothing else.
policy_file="$(mktemp)"
trap 'rm -f "$policy_file"' EXIT
sed "s#@TRANSIT_MOUNT@#$TRANSIT_MOUNT#g" "$POLICY_TEMPLATE" > "$policy_file"
print_info "Writing policy $POLICY_NAME"
run bao policy write "$POLICY_NAME" "$policy_file"

# 3. Kubernetes auth method.
if [[ "$DRY_RUN" == true ]] || ! bao auth list -format=json | grep -q "\"$AUTH_MOUNT/\""; then
  print_info "Enabling Kubernetes auth at auth/$AUTH_MOUNT/"
  run bao auth enable -path="$AUTH_MOUNT" kubernetes
else
  print_info "Kubernetes auth mount auth/$AUTH_MOUNT/ already enabled"
fi
if [[ -n "$KUBERNETES_HOST" ]]; then
  # Empty CA explicitly clears any old custom CA when switching to system trust.
  config_args=("kubernetes_host=$KUBERNETES_HOST" "disable_local_ca_jwt=true"
    "kubernetes_ca_cert=" "token_reviewer_jwt=@$REVIEWER_JWT_FILE")
  if [[ -n "$KUBERNETES_CA_FILE" ]]; then
    config_args[2]="kubernetes_ca_cert=@$KUBERNETES_CA_FILE"
  fi
  print_info "Configuring auth/$AUTH_MOUNT/config for an external OpenBao"
else
  # This config is required even on a fresh in-cluster auth mount. Explicitly
  # clear externally configured credentials so OpenBao rereads its local files.
  config_args=("kubernetes_host=https://kubernetes.default.svc:443"
    "disable_local_ca_jwt=false" "token_reviewer_jwt=" "kubernetes_ca_cert=")
  print_info "Configuring auth/$AUTH_MOUNT/config with OpenBao's local reviewer token and CA"
fi
run bao write "auth/$AUTH_MOUNT/config" "${config_args[@]}"

# 4. One role bound to exactly one ServiceAccount, namespace and audience.
print_info "Writing role auth/$AUTH_MOUNT/role/$ROLE for $NAMESPACE/$SERVICE_ACCOUNT (audience $AUDIENCE)"
run bao write "auth/$AUTH_MOUNT/role/$ROLE" \
  "bound_service_account_names=$SERVICE_ACCOUNT" \
  "bound_service_account_namespaces=$NAMESPACE" \
  "audience=$AUDIENCE" \
  "token_policies=$POLICY_NAME" \
  "token_no_default_policy=true" \
  "token_ttl=$TOKEN_TTL" \
  "token_max_ttl=$TOKEN_MAX_TTL"

print_info "Done. Chart values: transitMount=$TRANSIT_MOUNT auth.mount=$AUTH_MOUNT auth.role=$ROLE auth.audience=$AUDIENCE"
