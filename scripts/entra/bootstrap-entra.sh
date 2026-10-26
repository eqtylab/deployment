#!/usr/bin/env bash
set -e

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do SOURCE="$(readlink "$SOURCE")"; done
ROOTDIR="$(cd -P "$(dirname "$SOURCE")/../.." && pwd)"

# shellcheck source=../helpers/output.sh
source "$ROOTDIR/scripts/helpers/output.sh"
# shellcheck source=../helpers/assert.sh
source "$ROOTDIR/scripts/helpers/assert.sh"

# Function to display usage
usage() {
  echo -e "\
Bootstrap Microsoft Entra ID app registrations for the Guardian Platform

Usage: $0 -f <values-file> [options]
  -c, --chart-dir <dir>           Chart directory (default: $CHART_DIR)
  -f, --values <file>             Helm values file for entra-bootstrap chart (required)
  -h, --help                      Show this help message
  -n, --namespace <namespace>     Kubernetes namespace (required)
  -r, --release <name>            Helm release name (default: $BOOTSTRAP_RELEASE)

Examples:
  $0 -f $CHART_DIR/examples/values.yaml -n guardian
  $0 -f my-values.yaml --namespace guardian-stag
"
}

# Verify required secrets exist in the namespace
check_prerequisites() {
  print_warn "Checking prerequisites..."

  # Check required secrets
  # The bootstrap job needs the service principal secret for Graph API access
  local missing_secrets=()
  for secret in "$SP_SECRET"; do
    if ! kubectl get secret "$secret" -n "$NAMESPACE" &>/dev/null; then
      missing_secrets+=("$secret")
    fi
  done

  if [ ${#missing_secrets[@]} -gt 0 ]; then
    print_error "Missing required secrets:"
    printf '%s\n' "${missing_secrets[@]}"
    echo ""
    echo "Create the bootstrap service principal secret with:"
    echo "  kubectl create secret generic $SP_SECRET \\"
    echo "    --from-literal=$(values_get '.entra.servicePrincipalSecret.clientIdKey' client-id)=<sp-client-id> \\"
    echo "    --from-literal=$(values_get '.entra.servicePrincipalSecret.clientSecretKey' client-secret)=<sp-client-secret> \\"
    echo "    -n $NAMESPACE"
    echo ""
    echo "The service principal must have the following Microsoft Graph API permissions:"
    echo "  - Application.ReadWrite.All (Application)"
    echo "  - DelegatedPermissionGrant.ReadWrite.All (Application)"
    exit 1
  fi
  print_info "All required secrets exist"
}

# Deploy the entra-bootstrap Helm chart, which waits for the bootstrap job
run_bootstrap() {
  # Clean up any existing bootstrap jobs
  print_warn "Cleaning up any existing bootstrap jobs..."
  kubectl delete job -l app.kubernetes.io/instance="$BOOTSTRAP_RELEASE" -n "$NAMESPACE" --ignore-not-found

  # Run the bootstrap
  print_warn "Running Entra ID bootstrap..."

  if ! helm upgrade --install "$BOOTSTRAP_RELEASE" "$CHART_DIR" \
    -n "$NAMESPACE" \
    -f "$VALUES_FILE" \
    --wait \
    --timeout 10m; then
    print_error "Bootstrap job failed or timed out"
    kubectl logs -l app.kubernetes.io/instance="$BOOTSTRAP_RELEASE" -n "$NAMESPACE" --tail=50 || true
    exit 1
  fi

  # Get the job name
  local job_name
  job_name=$(kubectl get job -l app.kubernetes.io/instance="$BOOTSTRAP_RELEASE" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [ -z "$job_name" ]; then
    print_error "Bootstrap job not found"
    exit 1
  fi

  print_info "Bootstrap job $job_name completed"

  # Secret the job saved client credentials to
  CREDENTIALS_SECRET=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="CREDENTIALS_SECRET")].value}')

  # Show logs
  echo ""
  print_warn "Bootstrap logs:"
  kubectl logs job/"$job_name" -n "$NAMESPACE"

  # Cleanup completed job
  echo ""
  print_warn "Cleaning up completed job..."
  kubectl delete job "$job_name" -n "$NAMESPACE" --ignore-not-found
}

# Read a key from the values file with yq, falling back to the chart default
values_get() {
  local value
  value=$(yq "$1 // \"\"" "$VALUES_FILE" 2>/dev/null)
  echo "${value:-$2}"
}

# Display summary with next steps
show_summary() {
  local frontend_app backend_app worker_app
  frontend_app=$(values_get '.apps.frontend.displayName' "Guardian Platform Frontend")
  backend_app=$(values_get '.apps.backend.displayName' "Guardian Platform Backend")
  worker_app=$(values_get '.apps.worker.displayName' "Governance Worker")

  echo ""
  print_info "Entra ID Bootstrap Complete!"
  echo ""
  echo "The bootstrap job created the following app registrations:"
  echo ""
  echo "App Registrations:"
  echo "- Frontend: ${frontend_app} (SPA / public client)"
  echo "- Backend:  ${backend_app} (confidential with service account)"
  echo "- Worker:   ${worker_app} (confidential, service account only)"
  echo ""
  echo "Next Steps:"
  echo "  1. Read the app IDs and client secrets from the ${CREDENTIALS_SECRET} Secret"
  echo "     (new client secrets are saved there, not to the logs):"
  echo "     kubectl get secret ${CREDENTIALS_SECRET} -n $NAMESPACE -o json | jq '.data | map_values(@base64d)'"
  echo "  2. Create the platform-entra secret with the backend app credentials:"
  echo "     kubectl create secret generic platform-entra \\"
  echo "       --from-literal=client-id=<backend-app-id> \\"
  echo "       --from-literal=client-secret=<backend-secret> \\"
  echo "       --from-literal=tenant-id=<tenant-id> \\"
  echo "       --from-literal=graph-client-id=<backend-app-id> \\"
  echo "       --from-literal=graph-client-secret=<backend-secret> \\"
  echo "       -n $NAMESPACE"
  echo ""
  echo "  3. Create the governance-worker secret:"
  echo "     kubectl create secret generic platform-governance-worker \\"
  echo "       --from-literal=client-id=<worker-app-id> \\"
  echo "       --from-literal=client-secret=<worker-secret> \\"
  echo "       -n $NAMESPACE"
  echo ""
  echo "  4. Update guardian Helm values with frontend app ID and tenant ID"
  echo "  5. Deploy the Guardian Platform with Entra values"
  echo "  6. Enable entra.createOrganization (and createPlatformAdmin) in the platform values so the Helm hook creates the organization and admin user, or run scripts/entra/post-install-entra-setup.sh after deploying"

  echo ""
  print_info "Bootstrap process completed!"
}

# Configurable parameters
NAMESPACE=""
VALUES_FILE=""
CHART_DIR="$ROOTDIR/charts/entra-bootstrap"
BOOTSTRAP_RELEASE="entra-bootstrap"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -c | --chart-dir)
    CHART_DIR="$2"
    shift 2
    ;;
  -f | --values)
    VALUES_FILE="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  -n | --namespace)
    NAMESPACE="$2"
    shift 2
    ;;
  -r | --release)
    BOOTSTRAP_RELEASE="$2"
    shift 2
    ;;
  *)
    print_error "Unknown option: $1"
    usage
    exit 1
    ;;
  esac
done

# Validate prerequisites
assert_is_installed "helm"
assert_is_installed "kubectl"
assert_is_installed "yq"
if ! yq --version 2>&1 | grep -q mikefarah; then
  print_error "yq must be mikefarah/yq v4 (https://github.com/mikefarah/yq)"
  exit 1
fi

# Validate required arguments
assert_not_empty "namespace" "$NAMESPACE" "Use -n or --namespace to provide a namespace."
assert_not_empty "values-file" "$VALUES_FILE" "Use -f or --values to provide a Helm values file."

# Validate path to file exists
assert_path_exists "chart-dir" "$CHART_DIR"

if [ ! -f "$VALUES_FILE" ]; then
  print_error "Values file not found: $VALUES_FILE"
  exit 1
fi

# Secret name the bootstrap job reads, from the values file
SP_SECRET=$(values_get '.entra.servicePrincipalSecret.name' entra-bootstrap-sp)

echo -e "\
Namespace:    $NAMESPACE
Release:      $BOOTSTRAP_RELEASE
Chart:        $CHART_DIR
Values:       $VALUES_FILE

This will create the following Entra ID app registrations:
- Frontend (SPA / public client)
- Backend (confidential with service account)
- Worker (confidential, service account only)

The backend app will be configured with:
- accessTokenAcceptedVersion: 2
- Application ID URI (api://<appId>)
- access_as_user OAuth2 scope
- Graph API permissions (User.Read, profile, openid, User.Read.All)
"

# Verify secrets
check_prerequisites
# Deploy the entra-bootstrap chart
run_bootstrap
# Display outputs
show_summary
