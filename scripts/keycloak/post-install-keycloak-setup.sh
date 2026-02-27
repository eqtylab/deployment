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
Post-install database setup for Keycloak integration

Usage: $0 -k <keycloak-url> [options]
  -e, --admin-email <email>       Platform admin email (default: $ADMIN_EMAIL)
  -h, --help                      Show this help message
  -k, --keycloak-url <url>        Keycloak URL (required, e.g. https://keycloak.example.com)
  -n, --namespace <namespace>     Kubernetes namespace (required)
  -r, --realm <realm>             Keycloak realm name (default: $REALM_NAME)

Examples:
  $0 -k https://governance.example.com/keycloak -n governance
  $0 -k https://governance.example.com/keycloak -n governance --admin-email admin@your-domain.com
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
      local exists=$(run_psql_scalar "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = '$table');")
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
  print_warn "Creating organization '$REALM_NAME'..."

  # Check if organization already exists
  local exists=$(run_psql_scalar "SELECT COUNT(*) FROM organization WHERE name = '$REALM_NAME';")

  if [ "$exists" = "1" ]; then
    print_info "Organization '$REALM_NAME' already exists"
    # Update to ensure idp_provider is set correctly
    run_psql -c "UPDATE organization SET idp_provider = 'keycloak', updated_at = NOW() WHERE name = '$REALM_NAME';"
    echo "Updated organization to use Keycloak IDP"
  else
    # Create new organization
    run_psql -c "INSERT INTO organization (name, description, display_name, idp_provider, settings, created_at, updated_at) \
          VALUES ('$REALM_NAME', '$REALM_NAME', '$DISPLAY_NAME', 'keycloak', '{}', NOW(), NOW());"
    print_info "Created organization '$REALM_NAME'"
  fi

  # Show the organization
  run_psql -c "SELECT id, name, display_name, idp_provider FROM organization WHERE name = '$REALM_NAME';"
}

# Create or update the platform-admin user and organization membership
create_platform_admin_user() {
  local keycloak_user_id=$1

  print_warn "Creating platform-admin user..."

  # Generate UUID using PostgreSQL (matching chart approach)
  local user_id=$(run_psql_scalar "SELECT gen_random_uuid();")

  # Check if user exists (by email or by IDP composite key)
  local user_exists=$(run_psql_scalar "SELECT COUNT(*) FROM users WHERE email = '$ADMIN_EMAIL' OR (idp_provider = 'keycloak' AND idp_user_id = '$keycloak_user_id');")

  if [ "$user_exists" != "0" ]; then
    print_warn "Platform admin user already exists"
    user_id=$(run_psql_scalar "SELECT id FROM users WHERE email = '$ADMIN_EMAIL' OR (idp_provider = 'keycloak' AND idp_user_id = '$keycloak_user_id') LIMIT 1;")
  else
    # Create user
    run_psql -c "INSERT INTO users (id, idp_provider, idp_user_id, email, email_verified, username, display_name, given_name, family_name, active, app_metadata, created_at, updated_at, is_service_account, service_config) \
          VALUES ('$user_id', 'keycloak', '$keycloak_user_id', '$ADMIN_EMAIL', true, 'platform-admin', 'Platform Admin', 'Platform', 'Admin', true, '{}', NOW(), NOW(), false, '{}');"
    print_info "Created platform admin user"
  fi

  # Get organization ID
  local org_id=$(run_psql_scalar "SELECT id FROM organization WHERE name = '$REALM_NAME';")

  if [ -z "$org_id" ]; then
    print_error "Organization not found"
    return 1
  fi

  # Check if membership exists
  local membership_exists=$(run_psql_scalar "SELECT COUNT(*) FROM user_organization_memberships WHERE user_id = '$user_id' AND organization_id = '$org_id';")

  if [ "$membership_exists" = "1" ]; then
    print_warn "Membership already exists, updating to ensure owner role"
    run_psql -c "UPDATE user_organization_memberships SET roles = '{organization_owner}', status = 'active' WHERE user_id = '$user_id' AND organization_id = '$org_id';"
  else
    # Create membership
    local membership_id=$(run_psql_scalar "SELECT gen_random_uuid();")
    run_psql -c "INSERT INTO user_organization_memberships (id, user_id, organization_id, roles, invited_at, joined_at, status) \
          VALUES ('$membership_id', '$user_id', '$org_id', '{organization_owner}', NOW(), NOW(), 'active');"
    print_info "Created organization membership"
  fi

  # Show created user
  echo ""
  echo "Platform admin user:"
  run_psql -c "SELECT id, email, display_name, idp_provider FROM users WHERE email = '$ADMIN_EMAIL';"
}

# Look up the platform-admin user ID from Keycloak Admin API
get_platform_admin_keycloak_id() {
  print_warn "Getting platform-admin user ID from Keycloak..." >&2

  # Get admin password
  local admin_pass=$(kubectl get secret keycloak-admin -n "$NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

  if [ -z "$admin_pass" ]; then
    print_warn "Could not get admin password, using placeholder ID" >&2
    echo "00000000-0000-0000-0000-000000000000"
    return
  fi

  # Get admin token from master realm
  echo "Getting admin token..." >&2
  local token_response=$(curl -sk -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" \
    --data-urlencode "password=$admin_pass" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" 2>/dev/null)

  local token=$(echo "$token_response" | jq -r '.access_token // empty')

  if [ -z "$token" ]; then
    print_warn "Could not get Keycloak token, using placeholder ID" >&2
    echo "00000000-0000-0000-0000-000000000000"
    return
  fi

  # Get platform-admin user from realm
  echo "Looking up platform-admin user in $REALM_NAME realm..." >&2
  local user_data=$(curl -sk -H "Authorization: Bearer $token" \
    "$KEYCLOAK_URL/admin/realms/$REALM_NAME/users?username=platform-admin&exact=true" 2>/dev/null)

  local user_id=$(echo "$user_data" | jq -r '.[0].id // empty')

  if [ -n "$user_id" ]; then
    print_info "Found platform-admin user ID: $user_id" >&2
    echo "$user_id"
  else
    print_warn "Platform-admin user not found in Keycloak, using placeholder" >&2
    echo "00000000-0000-0000-0000-000000000000"
  fi
}

# Verify Keycloak realm, database records, and organization membership
verify_integration() {
  print_warn "Verifying Keycloak integration..."

  # --- Verify Keycloak realm and user ---
  echo "Checking Keycloak realm..."

  local admin_pass=$(kubectl get secret keycloak-admin -n "$NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

  if [ -n "$admin_pass" ]; then
    local token_response=$(curl -sk -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "username=admin" \
      --data-urlencode "password=$admin_pass" \
      -d "grant_type=password" \
      -d "client_id=admin-cli" 2>/dev/null)

    local token=$(echo "$token_response" | jq -r '.access_token // empty')

    if [ -n "$token" ]; then
      local realm_check=$(curl -sk -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        "$KEYCLOAK_URL/admin/realms/$REALM_NAME")

      if [ "$realm_check" = "200" ]; then
        print_info "Keycloak realm '$REALM_NAME' exists"

        local user_data=$(curl -sk -H "Authorization: Bearer $token" \
          "$KEYCLOAK_URL/admin/realms/$REALM_NAME/users?username=platform-admin&exact=true" 2>/dev/null)
        local user_count=$(echo "$user_data" | jq '. | length // 0')

        if [ "$user_count" -gt 0 ]; then
          print_info "Platform-admin user exists in Keycloak"
        else
          print_error "Platform-admin user not found in Keycloak"
        fi
      else
        print_error "Keycloak realm '$REALM_NAME' not found"
      fi
    else
      print_warn "Could not verify Keycloak - unable to get token"
    fi
  else
    print_warn "Could not verify Keycloak - no admin password found"
  fi

  # --- Verify database records ---
  echo "Checking organization in database..."

  local org_count=$(run_psql_scalar "SELECT COUNT(*) FROM organization WHERE name = '$REALM_NAME' AND idp_provider = 'keycloak';")
  if [ "$org_count" = "1" ]; then
    print_info "Organization '$REALM_NAME' exists with idp_provider=keycloak"
  else
    print_error "Organization not found or incorrect idp_provider (count: ${org_count:-unknown})"
  fi

  local user_count=$(run_psql_scalar "SELECT COUNT(*) FROM users WHERE email = '$ADMIN_EMAIL' AND idp_provider = 'keycloak';")
  if [ "$user_count" = "1" ]; then
    print_info "Platform-admin user exists in auth service"

    local membership_count=$(run_psql_scalar "SELECT COUNT(*) FROM user_organization_memberships uom JOIN users u ON uom.user_id = u.id WHERE u.email = '$ADMIN_EMAIL' AND 'organization_owner' = ANY(uom.roles);")
    if [ "$membership_count" = "1" ]; then
      print_info "Platform-admin has organization_owner role"
    else
      print_error "Platform-admin missing organization_owner role (count: ${membership_count:-unknown})"
    fi
  else
    print_error "Platform-admin user not found in auth service (count: ${user_count:-unknown})"
  fi
}

# Display setup summary with URLs and next steps
show_summary() {
  echo ""
  print_info "Setup Summary"
  echo ""

  echo "Database Setup Completed:"
  echo "  - Organization: $REALM_NAME (idp_provider=keycloak)"
  echo "  - Display Name: $DISPLAY_NAME"
  echo "  - Platform Admin: $ADMIN_EMAIL"
  echo "  - Role: organization_owner"

  echo ""
  echo "Keycloak Information:"
  echo "  - Admin Console: $KEYCLOAK_URL/admin"
  echo "  - Realm: $KEYCLOAK_URL/admin/$REALM_NAME/console"

  echo ""
  echo "Next Steps:"
  echo "  1. Test login with platform-admin user"
  echo "  2. Verify token exchange with auth service"
  echo "  3. Check that users can access the governance platform"
}

# Orchestrate the full post-install setup workflow
main() {
  echo "This script sets up database entries after Keycloak bootstrap"
  echo ""
  print_warn "Prerequisites:"
  echo "  - Keycloak must be deployed and running"
  echo "  - Keycloak bootstrap must be complete (realm, clients, users created)"
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
  local keycloak_user_id=$(get_platform_admin_keycloak_id)
  create_platform_admin_user "$keycloak_user_id"

  # Step 4: Verify integration
  echo ""
  verify_integration

  # Step 5: Show summary
  show_summary

  echo ""
  print_info "Post-install setup complete!"
}

# Constants
REALM_NAME="governance"
DISPLAY_NAME="Governance Studio"
DB_NAME="governance"

# Configurable parameters
NAMESPACE=""
KEYCLOAK_URL=""
ADMIN_EMAIL="admin@governance.local"

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
  -k | --keycloak-url)
    KEYCLOAK_URL="$2"
    shift 2
    ;;
  -n | --namespace)
    NAMESPACE="$2"
    shift 2
    ;;
  -r | --realm)
    REALM_NAME="$2"
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
assert_not_empty "keycloak-url" "$KEYCLOAK_URL" "Use -k or --keycloak-url to provide the Keycloak URL."

# Run post-install setup
main
