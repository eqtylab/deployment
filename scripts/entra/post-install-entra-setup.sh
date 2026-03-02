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
Post-install database setup for Entra ID integration

Usage: $0 -n <namespace> [options]
  -e, --admin-email <email>       Platform admin email in Entra tenant (required)
  -h, --help                      Show this help message
  -n, --namespace <namespace>     Kubernetes namespace (required)
  -o, --org-name <name>           Organization name (default: $ORG_NAME)

Examples:
  $0 -n governance -e admin@contoso.com
  $0 -n governance-stag --admin-email admin@contoso.com --org-name my-org
"
}

# Execute psql via kubectl exec on the discovered database pod
run_psql() {
  kubectl exec -n "$NAMESPACE" "$DB_POD" -- \
    env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" "$@"
}

# Execute psql and return a trimmed scalar result
run_psql_scalar() {
  run_psql -tA -c "$1" 2>/dev/null | tr -d ' '
}

# Wait for governance-service deployment and database pod to be ready
wait_for_platform() {
  print_warn "Waiting for governance platform components..."

  # Check for governance service deployment
  echo "Checking for governance service deployment..."
  if ! kubectl get deployment -l app.kubernetes.io/name=governance-service -n "$NAMESPACE" &>/dev/null; then
    if ! kubectl get deployment governance-platform-governance-service -n "$NAMESPACE" &>/dev/null; then
      print_error "Governance service deployment not found"
      echo "Available deployments:"
      kubectl get deployments -n "$NAMESPACE"
      return 1
    fi
  fi

  # Wait for database to be running
  echo "Checking database pod..."
  local db_ready=false
  for i in {1..30}; do
    if kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=postgresql" -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
      db_ready=true
      break
    fi
    echo -n "."
    sleep 5
  done

  if [ "$db_ready" = true ]; then
    print_info "Database pod is running"
  else
    print_error "Database pod not ready after 150 seconds"
    return 1
  fi

  # Discover and store DB pod name for reuse
  DB_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=postgresql" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [ -z "$DB_POD" ]; then
    print_error "Could not find PostgreSQL pod"
    return 1
  fi

  # Check if database is accepting connections
  echo "Checking database connectivity..."
  for i in {1..10}; do
    if kubectl exec -n "$NAMESPACE" "$DB_POD" -- pg_isready -h localhost -U postgres &>/dev/null; then
      print_info "Database is accepting connections"
      return 0
    fi
    echo -n "."
    sleep 3
  done

  print_warn "Platform components are starting up"
}

# Wait for migrations and verify required database tables exist
ensure_database_ready() {
  print_warn "Ensuring database is ready..."

  # Wait for governance service to be running (migrations run on startup)
  echo "Waiting for governance service to be available..."
  kubectl wait --for=condition=available --timeout=300s \
    deployment/governance-platform-governance-service \
    -n "$NAMESPACE" 2>/dev/null || true

  echo "Waiting for application to initialize and run migrations..."
  sleep 5

  # Get PostgreSQL password
  echo "Getting database credentials..."
  PG_PASSWORD=$(kubectl get secret -n "$NAMESPACE" platform-database -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

  if [ -z "$PG_PASSWORD" ]; then
    print_error "Could not find PostgreSQL password"
    echo "Available secrets that might contain database credentials:"
    kubectl get secrets -n "$NAMESPACE" | grep -E "(postgres|database|platform)"
    return 1
  fi

  # Verify schema with retries (matching chart's init container: 30 attempts, 10s sleep)
  echo "Verifying database schema..."
  local required_tables=("organization" "users" "user_organization_memberships")
  local retries=30

  for attempt in $(seq 1 $retries); do
    local all_exist=true
    for table in "${required_tables[@]}"; do
      local exists
      exists=$(run_psql_scalar "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = '$table');")
      if [ "$exists" != "t" ]; then
        all_exist=false
        break
      fi
    done

    if [ "$all_exist" = true ]; then
      for table in "${required_tables[@]}"; do
        print_info "  Table '$table' exists"
      done
      print_info "Database schema is ready"
      return 0
    fi

    if [ $attempt -lt $retries ]; then
      echo "Attempt $attempt/$retries - Waiting 10 seconds for migrations..."
      sleep 10
    fi
  done

  print_error "Database may not be fully initialized after $retries attempts"
  return 1
}

# Create or update the organization record in the governance database
create_organization() {
  print_warn "Creating organization '$ORG_NAME'..."

  # Check if organization already exists
  local exists
  exists=$(run_psql_scalar "SELECT COUNT(*) FROM organization WHERE name = '$ORG_NAME';")

  if [ "$exists" = "1" ]; then
    print_info "Organization '$ORG_NAME' already exists"
    # Update to ensure idp_provider is set correctly
    run_psql -c "UPDATE organization SET idp_provider = 'entra', display_name = '$DISPLAY_NAME', updated_at = NOW() WHERE name = '$ORG_NAME';"
    echo "Updated organization to use Entra IDP"
  else
    # Create new organization
    run_psql -c "INSERT INTO organization (name, description, display_name, idp_provider, settings, created_at, updated_at) \
          VALUES ('$ORG_NAME', '$ORG_NAME', '$DISPLAY_NAME', 'entra', '{}', NOW(), NOW());"
    print_info "Created organization '$ORG_NAME'"
  fi

  # Show the organization
  run_psql -c "SELECT id, name, display_name, idp_provider FROM organization WHERE name = '$ORG_NAME';"
}

# Look up the platform admin user ID from Entra via Microsoft Graph API
get_platform_admin_entra_id() {
  print_warn "Getting platform admin user ID from Entra..." >&2

  # Get Graph API credentials from platform-entra secret
  local client_id
  local client_secret
  local tenant_id
  client_id=$(kubectl get secret platform-entra -n "$NAMESPACE" -o jsonpath='{.data.graph-client-id}' 2>/dev/null | base64 -d)
  client_secret=$(kubectl get secret platform-entra -n "$NAMESPACE" -o jsonpath='{.data.graph-client-secret}' 2>/dev/null | base64 -d)
  tenant_id=$(kubectl get secret platform-entra -n "$NAMESPACE" -o jsonpath='{.data.tenant-id}' 2>/dev/null | base64 -d)

  if [ -z "$client_id" ] || [ -z "$client_secret" ] || [ -z "$tenant_id" ]; then
    print_warn "Could not get Entra credentials from platform-entra secret, using placeholder ID" >&2
    echo "00000000-0000-0000-0000-000000000000"
    return
  fi

  # Get Graph API access token using client credentials flow
  echo "Getting Graph API access token..." >&2
  local token_response
  token_response=$(curl -s -X POST \
    "https://login.microsoftonline.com/${tenant_id}/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${client_id}" \
    -d "client_secret=${client_secret}" \
    -d "scope=https://graph.microsoft.com/.default" \
    -d "grant_type=client_credentials" 2>/dev/null) || true

  local token
  token=$(echo "$token_response" | jq -r '.access_token // empty')

  if [ -z "$token" ]; then
    print_warn "Could not get Graph API token, using placeholder ID" >&2
    echo "00000000-0000-0000-0000-000000000000"
    return
  fi

  # Look up user by email in Entra via Graph API
  echo "Looking up user '$ADMIN_EMAIL' in Entra..." >&2
  local user_data
  user_data=$(curl -s \
    -H "Authorization: Bearer $token" \
    "https://graph.microsoft.com/v1.0/users?\$filter=mail%20eq%20'${ADMIN_EMAIL}'%20or%20userPrincipalName%20eq%20'${ADMIN_EMAIL}'&\$select=id,mail,displayName,givenName,surname" 2>/dev/null) || true

  local user_id
  user_id=$(echo "$user_data" | jq -r '.value[0].id // empty')

  if [ -n "$user_id" ]; then
    # Store display name fields for user creation
    ENTRA_DISPLAY_NAME=$(echo "$user_data" | jq -r '.value[0].displayName // "Platform Admin"')
    ENTRA_GIVEN_NAME=$(echo "$user_data" | jq -r '.value[0].givenName // "Platform"')
    ENTRA_SURNAME=$(echo "$user_data" | jq -r '.value[0].surname // "Admin"')
    print_info "Found Entra user ID: $user_id" >&2
    echo "$user_id"
  else
    print_warn "User '$ADMIN_EMAIL' not found in Entra, using placeholder" >&2
    ENTRA_DISPLAY_NAME="Platform Admin"
    ENTRA_GIVEN_NAME="Platform"
    ENTRA_SURNAME="Admin"
    echo "00000000-0000-0000-0000-000000000000"
  fi
}

# Create or update the platform-admin user and organization membership
create_platform_admin_user() {
  local entra_user_id=$1

  print_warn "Creating platform-admin user..."

  # Generate UUID using PostgreSQL (matching chart approach)
  local user_id
  user_id=$(run_psql_scalar "SELECT gen_random_uuid();")

  # Check if user exists (by email or by IDP composite key)
  local user_exists
  user_exists=$(run_psql_scalar "SELECT COUNT(*) FROM users WHERE email = '$ADMIN_EMAIL' OR (idp_provider = 'entra' AND idp_user_id = '$entra_user_id');")

  if [ "$user_exists" != "0" ]; then
    print_warn "Platform admin user already exists"
    user_id=$(run_psql_scalar "SELECT id FROM users WHERE email = '$ADMIN_EMAIL' OR (idp_provider = 'entra' AND idp_user_id = '$entra_user_id') LIMIT 1;")
  else
    # Create user
    run_psql -c "INSERT INTO users (id, idp_provider, idp_user_id, email, email_verified, display_name, given_name, family_name, active, app_metadata, created_at, updated_at, is_service_account, service_config) \
          VALUES ('$user_id', 'entra', '$entra_user_id', '$ADMIN_EMAIL', true, '$ENTRA_DISPLAY_NAME', '$ENTRA_GIVEN_NAME', '$ENTRA_SURNAME', true, '{}', NOW(), NOW(), false, '{}');"
    print_info "Created platform admin user"
  fi

  # Get organization ID
  local org_id
  org_id=$(run_psql_scalar "SELECT id FROM organization WHERE name = '$ORG_NAME';")

  if [ -z "$org_id" ]; then
    print_error "Organization not found"
    return 1
  fi

  # Check if membership exists
  local membership_exists
  membership_exists=$(run_psql_scalar "SELECT COUNT(*) FROM user_organization_memberships WHERE user_id = '$user_id' AND organization_id = '$org_id';")

  if [ "$membership_exists" = "1" ]; then
    print_warn "Membership already exists, updating to ensure owner role"
    run_psql -c "UPDATE user_organization_memberships SET roles = '{organization_owner}', status = 'active' WHERE user_id = '$user_id' AND organization_id = '$org_id';"
  else
    # Create membership
    local membership_id
    membership_id=$(run_psql_scalar "SELECT gen_random_uuid();")
    run_psql -c "INSERT INTO user_organization_memberships (id, user_id, organization_id, roles, invited_at, joined_at, status) \
          VALUES ('$membership_id', '$user_id', '$org_id', '{organization_owner}', NOW(), NOW(), 'active');"
    print_info "Created organization membership"
  fi

  # Show created user
  echo ""
  echo "Platform admin user:"
  run_psql -c "SELECT id, email, display_name, idp_provider FROM users WHERE email = '$ADMIN_EMAIL';"
}

# Verify Entra integration: database records and organization membership
verify_integration() {
  print_warn "Verifying Entra integration..."

  # --- Verify Entra Graph API connectivity ---
  echo "Checking Entra Graph API connectivity..."

  local client_id
  local client_secret
  local tenant_id
  client_id=$(kubectl get secret platform-entra -n "$NAMESPACE" -o jsonpath='{.data.graph-client-id}' 2>/dev/null | base64 -d)
  client_secret=$(kubectl get secret platform-entra -n "$NAMESPACE" -o jsonpath='{.data.graph-client-secret}' 2>/dev/null | base64 -d)
  tenant_id=$(kubectl get secret platform-entra -n "$NAMESPACE" -o jsonpath='{.data.tenant-id}' 2>/dev/null | base64 -d)

  if [ -n "$client_id" ] && [ -n "$client_secret" ] && [ -n "$tenant_id" ]; then
    local token_response
    token_response=$(curl -s -X POST \
      "https://login.microsoftonline.com/${tenant_id}/oauth2/v2.0/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "client_id=${client_id}" \
      -d "client_secret=${client_secret}" \
      -d "scope=https://graph.microsoft.com/.default" \
      -d "grant_type=client_credentials" 2>/dev/null) || true

    local token
    token=$(echo "$token_response" | jq -r '.access_token // empty')

    if [ -n "$token" ]; then
      print_info "Graph API authentication successful"

      # Verify admin user exists in Entra
      local user_check
      user_check=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        "https://graph.microsoft.com/v1.0/users?\$filter=mail%20eq%20'${ADMIN_EMAIL}'%20or%20userPrincipalName%20eq%20'${ADMIN_EMAIL}'&\$select=id" 2>/dev/null) || true

      if [ "$user_check" = "200" ]; then
        print_info "Graph API user lookup successful"
      else
        print_warn "Graph API user lookup returned HTTP $user_check"
      fi
    else
      print_warn "Could not verify Entra - unable to get Graph API token"
    fi
  else
    print_warn "Could not verify Entra - platform-entra secret not found or incomplete"
  fi

  # --- Verify database records ---
  echo "Checking organization in database..."

  local org_count
  org_count=$(run_psql_scalar "SELECT COUNT(*) FROM organization WHERE name = '$ORG_NAME' AND idp_provider = 'entra';")
  if [ "$org_count" = "1" ]; then
    print_info "Organization '$ORG_NAME' exists with idp_provider=entra"
  else
    print_error "Organization not found or incorrect idp_provider (count: ${org_count:-unknown})"
  fi

  local user_count
  user_count=$(run_psql_scalar "SELECT COUNT(*) FROM users WHERE email = '$ADMIN_EMAIL' AND idp_provider = 'entra';")
  if [ "$user_count" = "1" ]; then
    print_info "Platform admin user exists in auth service"

    local membership_count
    membership_count=$(run_psql_scalar "SELECT COUNT(*) FROM user_organization_memberships uom JOIN users u ON uom.user_id = u.id WHERE u.email = '$ADMIN_EMAIL' AND 'organization_owner' = ANY(uom.roles);")
    if [ "$membership_count" = "1" ]; then
      print_info "Platform admin has organization_owner role"
    else
      print_error "Platform admin missing organization_owner role (count: ${membership_count:-unknown})"
    fi
  else
    print_error "Platform admin user not found in auth service (count: ${user_count:-unknown})"
  fi
}

# Display setup summary with next steps
show_summary() {
  echo ""
  print_info "Setup Summary"
  echo ""

  echo "Database Setup Completed:"
  echo "  - Organization: $ORG_NAME (idp_provider=entra)"
  echo "  - Display Name: $DISPLAY_NAME"
  echo "  - Platform Admin: $ADMIN_EMAIL"
  echo "  - Role: organization_owner"

  echo ""
  echo "Next Steps:"
  echo "  1. Test login with the platform admin user via Entra SSO"
  echo "  2. Verify token exchange with auth service"
  echo "  3. Check that users can access the governance platform"
}

# Orchestrate the full post-install setup workflow
main() {
  echo "This script sets up database entries after Entra ID bootstrap"
  echo ""
  print_warn "Prerequisites:"
  echo "  - Entra ID bootstrap must be complete (app registrations created)"
  echo "  - platform-entra secret must exist with Graph API credentials"
  echo "  - Governance platform must be deployed"
  echo ""

  # Step 1: Wait for platform and discover DB pod
  wait_for_platform

  # Step 2: Ensure database is ready (migrations run on startup)
  ensure_database_ready

  # Step 3: Create organization and platform-admin user
  echo ""
  create_organization

  echo ""
  local entra_user_id
  entra_user_id=$(get_platform_admin_entra_id)
  create_platform_admin_user "$entra_user_id"

  # Step 4: Verify integration
  echo ""
  verify_integration

  # Step 5: Show summary
  show_summary

  echo ""
  print_info "Post-install setup complete!"
}

# Constants
ORG_NAME="governance"
DISPLAY_NAME="Governance Studio"
DB_NAME="governance"

# Configurable parameters
NAMESPACE=""
ADMIN_EMAIL=""

# Entra user metadata (populated during Graph API lookup)
ENTRA_DISPLAY_NAME="Platform Admin"
ENTRA_GIVEN_NAME="Platform"
ENTRA_SURNAME="Admin"

# Runtime state (populated during setup)
DB_POD=""
PG_PASSWORD=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -e | --admin-email)
    ADMIN_EMAIL="$2"
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
  -o | --org-name)
    ORG_NAME="$2"
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
assert_is_installed "kubectl"
assert_is_installed "curl"
assert_is_installed "jq"

# Validate required arguments
assert_not_empty "namespace" "$NAMESPACE" "Use -n or --namespace to provide a namespace."
assert_not_empty "admin-email" "$ADMIN_EMAIL" "Use -e or --admin-email to provide the platform admin's Entra email."

# Run post-install setup
main
