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
Bootstrap Auth0 tenant (applications, API, scopes, users, actions) for the Governance Platform

Usage: $0 -f <values-file> -n <namespace> [options]
  -c, --chart-dir <dir>           Chart directory (default: $CHART_DIR)
  -f, --values <file>             Helm values file for auth0-bootstrap chart (required)
  -h, --help                      Show this help message
  -n, --namespace <namespace>     Kubernetes namespace (required)
  -r, --release <name>            Helm release name (default: $BOOTSTRAP_RELEASE)
      --actions-dir <dir>         Path to Auth0 action JS sources
                                  (default: $ACTIONS_DIR)
      --actions-configmap <name>  ConfigMap name for action JS sources
                                  (default: $ACTIONS_CONFIGMAP)
      --skip-actions              Skip Action ConfigMap creation and
                                  auth0-actions secret prerequisite check

Examples:
  $0 -f $CHART_DIR/examples/values.yaml -n governance
  $0 -f my-values.yaml --namespace governance-stag --skip-actions
"
}

# Verify required secrets exist in the namespace
check_prerequisites() {
  print_warn "Checking prerequisites..."

  # The bootstrap job mounts auth0-management (Management API M2M creds, and
  # the shared auth-service bearer token when actions are enabled).
  # platform-admin is also required when users.admin.enabled is true (default).
  local missing_secrets=()
  for secret in auth0-management platform-admin; do
    if ! kubectl get secret "$secret" -n "$NAMESPACE" &>/dev/null; then
      missing_secrets+=("$secret")
    fi
  done

  if [ ${#missing_secrets[@]} -gt 0 ]; then
    print_error "Missing required secrets:"
    printf '%s\n' "${missing_secrets[@]}"
    echo ""
    echo "Create the Management API M2M secret with credentials from the Auth0 Dashboard."
    echo "Add auth-service-api-secret too when actions.postLogin.enabled is true (default):"
    echo "  kubectl create secret generic auth0-management \\"
    echo "    --from-literal=client-id=<mgmt-m2m-client-id> \\"
    echo "    --from-literal=client-secret=<mgmt-m2m-client-secret> \\"
    echo "    --from-literal=auth-service-api-secret=\"\$(openssl rand -base64 32)\" \\"
    echo "    -n $NAMESPACE"
    echo ""
    echo "Create the platform admin password secret:"
    echo "  kubectl create secret generic platform-admin \\"
    echo "    --from-literal=password=\"\$(openssl rand -base64 16)\" \\"
    echo "    -n $NAMESPACE"
    echo ""
    echo "The Management API M2M application must be authorized for these scopes:"
    echo "  - read:clients, create:clients, update:clients"
    echo "  - read:resource_servers, create:resource_servers, update:resource_servers"
    echo "  - read:client_grants, create:client_grants, update:client_grants"
    echo "  - read:users, create:users, update:users"
    echo "  - read:actions, create:actions, update:actions, delete:actions (Actions)"
    exit 1
  fi
  print_info "All required secrets exist"

  # auth-service-api-secret is optional in the chart, so warn instead of failing
  if [ "$SKIP_ACTIONS" != "true" ]; then
    if ! kubectl get secret auth0-management -n "$NAMESPACE" -o jsonpath='{.data.auth-service-api-secret}' 2>/dev/null | grep -q .; then
      print_warn "Key 'auth-service-api-secret' not found in the auth0-management secret."
      echo "  The post-login action will deploy without AUTH_SERVICE_API_SECRET,"
      echo "  which will cause claims-enrichment calls to fail with HTTP 401."
      echo "  Patch the secret with:"
      echo "    kubectl patch secret auth0-management -n $NAMESPACE \\"
      echo "      -p '{\"stringData\":{\"auth-service-api-secret\":\"<shared-bearer-token>\"}}'"
    fi
  fi
}

# Create or replace the ConfigMap holding the Auth0 action JS sources
create_actions_source_configmap() {
  if [ "$SKIP_ACTIONS" = "true" ]; then
    print_warn "Skipping Auth0 actions source ConfigMap (--skip-actions)"
    return 0
  fi

  if [ ! -d "$ACTIONS_DIR" ]; then
    print_error "Auth0 actions directory not found: $ACTIONS_DIR"
    exit 1
  fi

  local js_count
  js_count=$(find "$ACTIONS_DIR" -maxdepth 1 -name '*.js' -type f | wc -l | tr -d ' ')
  if [ "$js_count" = "0" ]; then
    print_error "No .js action sources found in $ACTIONS_DIR"
    exit 1
  fi

  print_warn "Loading Auth0 action sources from $ACTIONS_DIR into ConfigMap '$ACTIONS_CONFIGMAP'..."

  # Replace any pre-existing ConfigMap so edits propagate
  kubectl create configmap "$ACTIONS_CONFIGMAP" \
    --from-file="$ACTIONS_DIR" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml \
    | kubectl apply -n "$NAMESPACE" -f -

  print_info "Loaded $js_count action source file(s)"
}

# Deploy the auth0-bootstrap Helm chart and monitor the job to completion
run_bootstrap() {
  # Clean up any existing bootstrap jobs
  print_warn "Cleaning up any existing bootstrap jobs..."
  kubectl delete job -l app.kubernetes.io/instance="$BOOTSTRAP_RELEASE" -n "$NAMESPACE" --ignore-not-found

  # Run the bootstrap
  print_warn "Running Auth0 bootstrap..."

  local helm_extra_args=()
  if [ "$SKIP_ACTIONS" = "true" ]; then
    helm_extra_args+=(--set "actions.enabled=false")
  fi

  helm upgrade --install "$BOOTSTRAP_RELEASE" "$CHART_DIR" \
    -n "$NAMESPACE" \
    -f "$VALUES_FILE" \
    "${helm_extra_args[@]}" \
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

  # Show logs (client secrets are printed once here — preserve full output)
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
  print_info "Auth0 Bootstrap Complete!"
  echo ""
  echo "The bootstrap job created the following Auth0 resources:"
  echo ""
  echo "Applications:"
  echo "- Frontend: Governance Platform Frontend (SPA / public client)"
  echo "- Backend:  Governance Platform Backend (M2M / non_interactive)"
  echo "- Worker:   Governance Worker (M2M / non_interactive)"
  echo ""
  echo "Resource Server:"
  echo "- Governance Platform API (with custom scopes + client grants)"
  echo ""
  if [ "$SKIP_ACTIONS" != "true" ]; then
    echo "Actions:"
    echo "- Post-Login enrichment action (bound to post-login trigger)"
    echo "- Client-Credentials-Exchange enrichment action (bound to credentials-exchange trigger)"
    echo ""
  fi
  echo "Next Steps:"
  echo "  1. Capture the backend and worker client IDs and secrets from the logs above"
  echo "     (Auth0 only prints client secrets once — store them now)"
  echo "  2. Create the platform-auth0 secret with backend + management credentials:"
  echo "     kubectl create secret generic platform-auth0 \\"
  echo "       --from-literal=client-id=<backend-client-id> \\"
  echo "       --from-literal=client-secret=<backend-client-secret> \\"
  echo "       --from-literal=mgmt-client-id=<backend-client-id> \\"
  echo "       --from-literal=mgmt-client-secret=<backend-client-secret> \\"
  echo "       -n $NAMESPACE"
  echo ""
  echo "  3. Create the governance-worker secret:"
  echo "     kubectl create secret generic platform-governance-worker \\"
  echo "       --from-literal=client-id=<worker-client-id> \\"
  echo "       --from-literal=client-secret=<worker-client-secret> \\"
  echo "       -n $NAMESPACE"
  echo ""
  echo "  4. Update governance-studio Helm values with the frontend SPA client ID and tenant domain"
  echo "  5. Deploy the governance platform with Auth0 values"
  echo "  6. Run the post-install setup script to create the organization and admin user"

  echo ""
  print_info "Bootstrap process completed!"
}

# Configurable parameters
NAMESPACE=""
VALUES_FILE=""
CHART_DIR="$ROOTDIR/charts/auth0-bootstrap"
BOOTSTRAP_RELEASE="auth0-bootstrap"
ACTIONS_DIR="$ROOTDIR/scripts/auth0/actions"
ACTIONS_CONFIGMAP="auth0-actions-source"
SKIP_ACTIONS="false"

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
  --actions-dir)
    ACTIONS_DIR="$2"
    shift 2
    ;;
  --actions-configmap)
    ACTIONS_CONFIGMAP="$2"
    shift 2
    ;;
  --skip-actions)
    SKIP_ACTIONS="true"
    shift
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

This will create the following Auth0 resources:
- Frontend application (SPA / public client)
- Backend application (M2M / non_interactive)
- Worker application (M2M / non_interactive)
- Governance Platform API (resource server) with custom scopes
- Client grants for backend and worker on the platform API
- Client grant for backend on the Auth0 Management API (user management)
- Platform admin user (if users.admin.enabled is true)
- Auth0 Actions (post-login + client-credentials-exchange) bound to triggers
  (skipped when --skip-actions is set)
"

# Verify secrets
check_prerequisites
# Load Auth0 action sources into a ConfigMap mounted by the bootstrap job
create_actions_source_configmap
# Deploy the auth0-bootstrap chart
run_bootstrap
# Display outputs
show_summary
