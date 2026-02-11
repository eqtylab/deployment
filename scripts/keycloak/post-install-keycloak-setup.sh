#!/bin/bash

# Post-install script for Keycloak database setup
# Run this AFTER:
# 1. Keycloak is deployed
# 2. Keycloak bootstrap is complete (realm, clients, users created)
# 3. Governance platform is deployed
#
# NOTE: Database migrations run automatically when the governance-service starts,
# so this script waits for the service to be running and verifies the schema exists.
#
# This script will:
# - Wait for database schema to be ready (migrations complete)
# - Create organization in governance database
# - Create platform-admin user in auth service tables
# - Set up organization membership with owner role
# - Verify the integration

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
NAMESPACE="governance"
REALM_NAME="governance"
DISPLAY_NAME=""
DB_NAME="governance"
OVERRIDE_KEYCLOAK_URL=""

# Shared state (populated during setup)
DB_POD=""
PG_PASSWORD=""

# Function to print usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -n, --namespace <namespace>       Kubernetes namespace (default: $NAMESPACE)"
  echo "  -r, --realm <realm>               Keycloak realm name (default: $REALM_NAME)"
  echo "  -D, --display-name <name>         Organization display name (default: realm name)"
  echo "  -d, --database <database>         Database name (default: $DB_NAME)"
  echo "  -k, --keycloak-url <url>          Keycloak URL (auto-detected from ingress if not set)"
  echo "  -h, --help                        Show this help message"
  echo ""
  echo "Example:"
  echo "  $0 --namespace governance --realm governance --display-name 'Governance Platform'"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -n | --namespace)
    NAMESPACE="$2"
    shift 2
    ;;
  -r | --realm)
    REALM_NAME="$2"
    shift 2
    ;;
  -D | --display-name)
    DISPLAY_NAME="$2"
    shift 2
    ;;
  -d | --database)
    DB_NAME="$2"
    shift 2
    ;;
  -k | --keycloak-url)
    OVERRIDE_KEYCLOAK_URL="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
  esac
done

# Default display name to realm name if not set
if [ -z "$DISPLAY_NAME" ]; then
  DISPLAY_NAME="$REALM_NAME"
fi

echo -e "${BLUE}Post-Install Keycloak Database Setup${NC}"
echo -e "${BLUE}===================================${NC}"
echo ""
echo "Namespace: $NAMESPACE"
echo "Realm/Organization: $REALM_NAME"
echo "Display Name: $DISPLAY_NAME"
echo "Database: $DB_NAME"
echo ""

# Helper to run psql via kubectl exec
run_psql() {
  kubectl exec -n "$NAMESPACE" "$DB_POD" -- \
    env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" "$@"
}

# Helper to run psql and return trimmed scalar result
run_psql_scalar() {
  run_psql -tA -c "$1" 2>/dev/null | tr -d ' '
}

# =============================================================================
# PLATFORM READINESS
# =============================================================================

wait_for_platform() {
  echo -e "${YELLOW}Waiting for governance platform components...${NC}"

  # Check for governance service deployment
  echo "Checking for governance service deployment..."
  if ! kubectl get deployment -l app.kubernetes.io/name=governance-service -n "$NAMESPACE" &>/dev/null; then
    if ! kubectl get deployment governance-platform-governance-service -n "$NAMESPACE" &>/dev/null; then
      echo -e "${RED}Error: Governance service deployment not found${NC}"
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
    echo -e "${GREEN}✓ Database pod is running${NC}"
  else
    echo -e "${RED}Database pod not ready after 150 seconds${NC}"
    return 1
  fi

  # Discover and store DB pod name for reuse
  DB_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=postgresql" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [ -z "$DB_POD" ]; then
    echo -e "${RED}Error: Could not find PostgreSQL pod${NC}"
    return 1
  fi

  # Check if database is accepting connections
  echo "Checking database connectivity..."
  for i in {1..10}; do
    if kubectl exec -n "$NAMESPACE" "$DB_POD" -- pg_isready -h localhost -U postgres &>/dev/null; then
      echo -e "${GREEN}✓ Database is accepting connections${NC}"
      return 0
    fi
    echo -n "."
    sleep 3
  done

  echo -e "${YELLOW}Platform components are starting up${NC}"
}

# =============================================================================
# DATABASE READINESS
# =============================================================================

ensure_database_ready() {
  echo -e "${YELLOW}Ensuring database is ready...${NC}"

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
    echo -e "${RED}Error: Could not find PostgreSQL password${NC}"
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
        echo -e "${GREEN}  ✓ Table '$table' exists${NC}"
      done
      echo -e "${GREEN}Database schema is ready${NC}"
      return 0
    fi

    if [ $attempt -lt $retries ]; then
      echo "Attempt $attempt/$retries - Waiting 10 seconds for migrations..."
      sleep 10
    fi
  done

  echo -e "${RED}Warning: Database may not be fully initialized after $retries attempts${NC}"
  return 1
}

# =============================================================================
# ORGANIZATION CREATION (matches chart's create-keycloak-org-job.yaml)
# =============================================================================

create_organization() {
  echo -e "${YELLOW}Creating organization '$REALM_NAME'...${NC}"

  # Check if organization already exists
  local exists=$(run_psql_scalar "SELECT COUNT(*) FROM organization WHERE name = '$REALM_NAME';")

  if [ "$exists" = "1" ]; then
    echo -e "${GREEN}Organization '$REALM_NAME' already exists${NC}"
    # Update to ensure idp_provider is set correctly
    run_psql -c "UPDATE organization SET idp_provider = 'keycloak', updated_at = NOW() WHERE name = '$REALM_NAME';"
    echo "Updated organization to use Keycloak IDP"
  else
    # Create new organization
    run_psql -c "INSERT INTO organization (name, description, display_name, idp_provider, settings, created_at, updated_at) \
          VALUES ('$REALM_NAME', '$REALM_NAME', '$DISPLAY_NAME', 'keycloak', '{}', NOW(), NOW());"
    echo -e "${GREEN}Created organization '$REALM_NAME'${NC}"
  fi

  # Show the organization
  run_psql -c "SELECT id, name, display_name, idp_provider FROM organization WHERE name = '$REALM_NAME';"
}

# =============================================================================
# PLATFORM ADMIN USER CREATION (matches chart's create-keycloak-org-job.yaml)
# =============================================================================

create_platform_admin_user() {
  local keycloak_user_id=$1

  echo -e "${YELLOW}Creating platform-admin user...${NC}"

  # Generate UUID using PostgreSQL (matching chart approach)
  local user_id=$(run_psql_scalar "SELECT gen_random_uuid();")

  # Check if user exists (by email or by IDP composite key)
  local user_exists=$(run_psql_scalar "SELECT COUNT(*) FROM users WHERE email = 'admin@$REALM_NAME.local' OR (idp_provider = 'keycloak' AND idp_user_id = '$keycloak_user_id');")

  if [ "$user_exists" != "0" ]; then
    echo -e "${YELLOW}Platform admin user already exists${NC}"
    user_id=$(run_psql_scalar "SELECT id FROM users WHERE email = 'admin@$REALM_NAME.local' OR (idp_provider = 'keycloak' AND idp_user_id = '$keycloak_user_id') LIMIT 1;")
  else
    # Create user
    run_psql -c "INSERT INTO users (id, idp_provider, idp_user_id, email, email_verified, display_name, given_name, family_name, active, app_metadata, created_at, updated_at, is_service_account, service_config) \
          VALUES ('$user_id', 'keycloak', '$keycloak_user_id', 'admin@$REALM_NAME.local', true, 'Platform Admin', 'Platform', 'Admin', true, '{}', NOW(), NOW(), false, '{}');"
    echo -e "${GREEN}Created platform admin user${NC}"
  fi

  # Get organization ID
  local org_id=$(run_psql_scalar "SELECT id FROM organization WHERE name = '$REALM_NAME';")

  if [ -z "$org_id" ]; then
    echo -e "${RED}Error: Organization not found${NC}"
    return 1
  fi

  # Check if membership exists
  local membership_exists=$(run_psql_scalar "SELECT COUNT(*) FROM user_organization_memberships WHERE user_id = '$user_id' AND organization_id = '$org_id';")

  if [ "$membership_exists" = "1" ]; then
    echo -e "${YELLOW}Membership already exists, updating to ensure owner role${NC}"
    run_psql -c "UPDATE user_organization_memberships SET roles = '{organization_owner}', status = 'active' WHERE user_id = '$user_id' AND organization_id = '$org_id';"
  else
    # Create membership
    local membership_id=$(run_psql_scalar "SELECT gen_random_uuid();")
    run_psql -c "INSERT INTO user_organization_memberships (id, user_id, organization_id, roles, invited_at, joined_at, status) \
          VALUES ('$membership_id', '$user_id', '$org_id', '{organization_owner}', NOW(), NOW(), 'active');"
    echo -e "${GREEN}Created organization membership${NC}"
  fi

  # Show created user
  echo ""
  echo "Platform admin user:"
  run_psql -c "SELECT id, email, display_name, idp_provider FROM users WHERE email = 'admin@$REALM_NAME.local';"
}

# =============================================================================
# KEYCLOAK USER ID LOOKUP
# =============================================================================

get_platform_admin_keycloak_id() {
  echo -e "${YELLOW}Getting platform-admin user ID from Keycloak...${NC}" >&2

  local keycloak_url="$OVERRIDE_KEYCLOAK_URL"
  local ingress_host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null)
  local pf_pid=""

  if [ -z "$keycloak_url" ]; then
    if [ -n "$ingress_host" ]; then
      keycloak_url="https://$ingress_host/keycloak"
    else
      echo -e "${YELLOW}No ingress found, trying port-forward method${NC}" >&2
      kubectl port-forward -n "$NAMESPACE" svc/keycloak 8080:80 &>/dev/null &
      pf_pid=$!
      sleep 3
      keycloak_url="http://localhost:8080/keycloak"
    fi
  fi

  # Get admin password
  local admin_pass=$(kubectl get secret keycloak-admin -n "$NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

  if [ -z "$admin_pass" ]; then
    echo -e "${YELLOW}Could not get admin password, using placeholder ID${NC}" >&2
    [ -n "$pf_pid" ] && kill $pf_pid 2>/dev/null
    echo "00000000-0000-0000-0000-000000000000"
    return
  fi

  # Get admin token from master realm
  echo "Getting admin token..." >&2
  local token_response=$(curl -sk -X POST "$keycloak_url/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" \
    -d "password=$admin_pass" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" 2>/dev/null)

  local token=$(echo "$token_response" | jq -r '.access_token // empty')

  if [ -z "$token" ]; then
    echo -e "${YELLOW}Could not get Keycloak token, using placeholder ID${NC}" >&2
    [ -n "$pf_pid" ] && kill $pf_pid 2>/dev/null
    echo "00000000-0000-0000-0000-000000000000"
    return
  fi

  # Get platform-admin user from realm
  echo "Looking up platform-admin user in $REALM_NAME realm..." >&2
  local user_data=$(curl -sk -H "Authorization: Bearer $token" \
    "$keycloak_url/admin/realms/$REALM_NAME/users?username=platform-admin&exact=true" 2>/dev/null)

  local user_id=$(echo "$user_data" | jq -r '.[0].id // empty')

  # Clean up port-forward if we started it
  [ -n "$pf_pid" ] && kill $pf_pid 2>/dev/null

  if [ -n "$user_id" ]; then
    echo -e "${GREEN}Found platform-admin user ID: $user_id${NC}" >&2
    echo "$user_id"
  else
    echo -e "${YELLOW}Platform-admin user not found in Keycloak, using placeholder${NC}" >&2
    echo "00000000-0000-0000-0000-000000000000"
  fi
}

# =============================================================================
# INTEGRATION VERIFICATION
# =============================================================================

verify_integration() {
  echo -e "${YELLOW}Verifying Keycloak integration...${NC}"

  # --- Verify Keycloak realm and user ---
  echo "Checking Keycloak realm..."

  local keycloak_url="$OVERRIDE_KEYCLOAK_URL"
  local ingress_host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null)
  local pf_pid=""

  if [ -n "$keycloak_url" ]; then
    : # Already set via --keycloak-url flag
  elif [ -n "$ingress_host" ]; then
    keycloak_url="https://$ingress_host/keycloak"
  else
    echo -e "${YELLOW}No ingress found, trying port-forward method${NC}"
    kubectl port-forward -n "$NAMESPACE" svc/keycloak 8080:80 &>/dev/null &
    pf_pid=$!
    sleep 3
    keycloak_url="http://localhost:8080/keycloak"
  fi

  local admin_pass=$(kubectl get secret keycloak-admin -n "$NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

  if [ -n "$admin_pass" ]; then
    local token_response=$(curl -sk -X POST "$keycloak_url/realms/master/protocol/openid-connect/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "username=admin" \
      -d "password=$admin_pass" \
      -d "grant_type=password" \
      -d "client_id=admin-cli" 2>/dev/null)

    local token=$(echo "$token_response" | jq -r '.access_token // empty')

    if [ -n "$token" ]; then
      local realm_check=$(curl -sk -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        "$keycloak_url/admin/realms/$REALM_NAME")

      if [ "$realm_check" = "200" ]; then
        echo -e "${GREEN}✓ Keycloak realm '$REALM_NAME' exists${NC}"

        local user_data=$(curl -sk -H "Authorization: Bearer $token" \
          "$keycloak_url/admin/realms/$REALM_NAME/users?username=platform-admin&exact=true" 2>/dev/null)
        local user_count=$(echo "$user_data" | jq '. | length // 0')

        if [ "$user_count" -gt 0 ]; then
          echo -e "${GREEN}✓ Platform-admin user exists in Keycloak${NC}"
        else
          echo -e "${RED}✗ Platform-admin user not found in Keycloak${NC}"
        fi
      else
        echo -e "${RED}✗ Keycloak realm '$REALM_NAME' not found${NC}"
      fi
    else
      echo -e "${YELLOW}Could not verify Keycloak - unable to get token${NC}"
    fi
  else
    echo -e "${YELLOW}Could not verify Keycloak - no admin password found${NC}"
  fi

  [ -n "$pf_pid" ] && kill $pf_pid 2>/dev/null

  # --- Verify database records ---
  echo "Checking organization in database..."

  local org_count=$(run_psql_scalar "SELECT COUNT(*) FROM organization WHERE name = '$REALM_NAME' AND idp_provider = 'keycloak';")
  if [ "$org_count" = "1" ]; then
    echo -e "${GREEN}✓ Organization '$REALM_NAME' exists with idp_provider=keycloak${NC}"
  else
    echo -e "${RED}✗ Organization not found or incorrect idp_provider (count: ${org_count:-unknown})${NC}"
  fi

  local user_count=$(run_psql_scalar "SELECT COUNT(*) FROM users WHERE email = 'admin@$REALM_NAME.local' AND idp_provider = 'keycloak';")
  if [ "$user_count" = "1" ]; then
    echo -e "${GREEN}✓ Platform-admin user exists in auth service${NC}"

    local membership_count=$(run_psql_scalar "SELECT COUNT(*) FROM user_organization_memberships uom JOIN users u ON uom.user_id = u.id WHERE u.email = 'admin@$REALM_NAME.local' AND 'organization_owner' = ANY(uom.roles);")
    if [ "$membership_count" = "1" ]; then
      echo -e "${GREEN}✓ Platform-admin has organization_owner role${NC}"
    else
      echo -e "${RED}✗ Platform-admin missing organization_owner role (count: ${membership_count:-unknown})${NC}"
    fi
  else
    echo -e "${RED}✗ Platform-admin user not found in auth service (count: ${user_count:-unknown})${NC}"
  fi
}

# =============================================================================
# SUMMARY
# =============================================================================

show_summary() {
  echo ""
  echo -e "${BLUE}Setup Summary${NC}"
  echo -e "${BLUE}=============${NC}"
  echo ""

  echo "Database Setup Completed:"
  echo "  - Organization: $REALM_NAME (idp_provider=keycloak)"
  echo "  - Display Name: $DISPLAY_NAME"
  echo "  - Platform Admin: admin@$REALM_NAME.local"
  echo "  - Role: organization_owner"

  local ingress_host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null)

  echo ""
  echo "Keycloak Information:"
  if [ -n "$ingress_host" ]; then
    echo "  - Admin Console: https://$ingress_host/keycloak/admin"
    echo "  - Realm: https://$ingress_host/keycloak/admin/$REALM_NAME/console"
  else
    echo "  - Use port-forward: kubectl port-forward -n $NAMESPACE svc/keycloak 8080:80"
    echo "  - Then access: http://localhost:8080/keycloak/admin"
  fi

  echo ""
  echo "Next Steps:"
  echo "  1. Test login with platform-admin user"
  echo "  2. Verify token exchange with auth service"
  echo "  3. Check that users can access the governance platform"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  echo "This script sets up database entries after Keycloak bootstrap"
  echo ""
  echo -e "${YELLOW}Prerequisites:${NC}"
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
  echo -e "${GREEN}Post-install setup complete!${NC}"
}

# Run main function
main
