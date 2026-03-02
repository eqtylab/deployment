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
Bootstrap Microsoft Entra ID app registrations for the Governance Platform

Usage: $0 -f <values-file> [options]
  -c, --chart-dir <dir>           Chart directory (default: $CHART_DIR)
  -f, --values <file>             Helm values file for entra-bootstrap chart (required)
  -h, --help                      Show this help message
  -n, --namespace <namespace>     Kubernetes namespace (required)
  -r, --release <name>            Helm release name (default: $BOOTSTRAP_RELEASE)

Examples:
  $0 -f $CHART_DIR/examples/values.yaml -n governance
  $0 -f my-values.yaml --namespace governance-stag
"
}

# Verify required secrets exist in the namespace
check_prerequisites() {
  print_warn "Checking prerequisites..."

  # Check required secrets
  # The bootstrap job needs the service principal secret for Graph API access
  local missing_secrets=()
  for secret in entra-bootstrap-sp; do
    if ! kubectl get secret "$secret" -n "$NAMESPACE" &>/dev/null; then
      missing_secrets+=("$secret")
    fi
  done

  if [ ${#missing_secrets[@]} -gt 0 ]; then
    print_error "Missing required secrets:"
    printf '%s\n' "${missing_secrets[@]}"
    echo ""
    echo "Create the bootstrap service principal secret with:"
    echo "  kubectl create secret generic entra-bootstrap-sp \\"
    echo "    --from-literal=client-id=<sp-client-id> \\"
    echo "    --from-literal=client-secret=<sp-client-secret> \\"
    echo "    -n $NAMESPACE"
    echo ""
    echo "The service principal must have the following Microsoft Graph API permissions:"
    echo "  - Application.ReadWrite.All (Application)"
    echo "  - DelegatedPermissionGrant.ReadWrite.All (Application)"
    exit 1
  fi
  print_info "All required secrets exist"
}

# Deploy the entra-bootstrap Helm chart and monitor the job to completion
run_bootstrap() {
  # Clean up any existing bootstrap jobs
  print_warn "Cleaning up any existing bootstrap jobs..."
  kubectl delete job -l app.kubernetes.io/instance="$BOOTSTRAP_RELEASE" -n "$NAMESPACE" --ignore-not-found

  # Run the bootstrap
  print_warn "Running Entra ID bootstrap..."

  helm upgrade --install "$BOOTSTRAP_RELEASE" "$CHART_DIR" \
    -n "$NAMESPACE" \
    -f "$VALUES_FILE" \
    --wait \
    --timeout 10m

  # Get the job name
  local job_name
  job_name=$(kubectl get job -l app.kubernetes.io/instance="$BOOTSTRAP_RELEASE" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [ -z "$job_name" ]; then
    print_error "Bootstrap job not found"
    exit 1
  fi

  echo "Bootstrap job: $job_name"

  # Monitor job completion
  print_warn "Monitoring bootstrap job..."

  local timeout=600
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    local job_status
    local job_failed
    job_status=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
    job_failed=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)

    if [ "$job_status" = "True" ]; then
      print_info "Bootstrap completed successfully"
      break
    elif [ "$job_failed" = "True" ]; then
      print_error "Bootstrap job failed"
      echo "Job logs:"
      kubectl logs job/"$job_name" -n "$NAMESPACE" --tail=50
      exit 1
    fi

    echo -n "."
    sleep 5
    elapsed=$((elapsed + 5))
  done

  if [ $elapsed -ge $timeout ]; then
    print_error "Bootstrap job timed out"
    kubectl logs job/"$job_name" -n "$NAMESPACE" --tail=50
    exit 1
  fi

  # Show logs
  echo ""
  print_warn "Bootstrap logs:"
  kubectl logs job/"$job_name" -n "$NAMESPACE"

  # Cleanup completed job
  echo ""
  print_warn "Cleaning up completed job..."
  kubectl delete job "$job_name" -n "$NAMESPACE" --ignore-not-found
}

# Display summary with next steps
show_summary() {
  echo ""
  print_info "Entra ID Bootstrap Complete!"
  echo ""
  echo "The bootstrap job created the following app registrations:"
  echo ""
  echo "App Registrations:"
  echo "- Frontend: Governance Platform Frontend (SPA / public client)"
  echo "- Backend:  Governance Platform Backend (confidential with service account)"
  echo "- Worker:   Governance Worker (confidential, service account only)"
  echo ""
  echo "Next Steps:"
  echo "  1. Check the bootstrap job logs above for app IDs and client secrets"
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
  echo "  4. Update governance-studio Helm values with frontend app ID and tenant ID"
  echo "  5. Deploy the governance platform with Entra values"
  echo "  6. Run the post-install setup script to create the organization and admin user"

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

# Validate required arguments
assert_not_empty "namespace" "$NAMESPACE" "Use -n or --namespace to provide a namespace."
assert_not_empty "values-file" "$VALUES_FILE" "Use -f or --values to provide a Helm values file."

# Validate path to file exists
assert_path_exists "chart-dir" "$CHART_DIR"

if [ ! -f "$VALUES_FILE" ]; then
  print_error "Values file not found: $VALUES_FILE"
  exit 1
fi

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
