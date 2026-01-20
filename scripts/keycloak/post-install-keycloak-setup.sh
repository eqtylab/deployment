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
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
NAMESPACE="governance"
REALM_NAME="governance"
ENVIRONMENT="dev"
OVERRIDE_KEYCLOAK_URL=""

# Function to print usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -n, --namespace <namespace>    Kubernetes namespace (default: $NAMESPACE)"
  echo "  -r, --realm <realm>            Keycloak realm name (default: $REALM_NAME)"
  echo "  -e, --env <environment>        Environment: dev|stag|prod (default: $ENVIRONMENT)"
  echo "  -k, --keycloak-url <url>       Keycloak URL"
  echo "  -h, --help                     Show this help message"
  echo ""
  echo "Example:"
  echo "  $0 --namespace governance-stag --realm governance --env stag"
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
  -e | --env)
    ENVIRONMENT="$2"
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

echo -e "${BLUE}Post-Install Keycloak Database Setup${NC}"
echo -e "${BLUE}===================================${NC}"
echo ""
echo "Namespace: $NAMESPACE"
echo "Environment: $ENVIRONMENT"
echo "Realm/Organization: $REALM_NAME"
echo ""

# Function to wait for governance platform
wait_for_platform() {
  echo -e "${YELLOW}Waiting for governance platform components...${NC}"

  # Check for governance service deployment
  echo "Checking for governance service deployment..."
  if ! kubectl get deployment -l app.kubernetes.io/name=governance-service -n "$NAMESPACE" &>/dev/null; then
    # Try alternative names
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

  # Check if database is accepting connections
  echo "Checking database connectivity..."
  local db_pod=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=postgresql" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [ -n "$db_pod" ]; then
    for i in {1..10}; do
      if kubectl exec -n "$NAMESPACE" "$db_pod" -- pg_isready -h localhost -U postgres &>/dev/null; then
        echo -e "${GREEN}✓ Database is accepting connections${NC}"
        return 0
      fi
      echo -n "."
      sleep 3
    done
  fi

  echo -e "${YELLOW}Platform components are starting up${NC}"
}

# Function to get PostgreSQL password
get_postgres_password() {
  # Try common secret names
  local password=""

  # Try platform-database first (current standard)
  password=$(kubectl get secret -n "$NAMESPACE" platform-database -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

  if [ -z "$password" ]; then
    # List available secrets for debugging
    echo -e "${RED}Error: Could not find PostgreSQL password${NC}"
    echo "Available secrets that might contain database credentials:"
    kubectl get secrets -n "$NAMESPACE" | grep -E "(postgres|database|platform)"
    return 1
  fi

  echo "$password"
}

# Function to verify database schema exists
verify_database_schema() {
  local db_pod=$1
  local pg_password=$2

  # Check for required tables
  local required_tables=("organization" "users" "user_organization_memberships")
  local all_exist=true

  for table in "${required_tables[@]}"; do
    # Use COUNT for more reliable results with password
    local count=$(kubectl exec -n "$NAMESPACE" "$db_pod" -- \
      env PGPASSWORD="$pg_password" psql -U postgres -d governance -tA -c \
      "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$table';" 2>/dev/null)

    # Check if count is 1 (table exists) or 0 (doesn't exist)
    if [ "$count" = "1" ]; then
      echo -e "${GREEN}  ✓ Table '$table' exists${NC}"
    else
      echo -e "${RED}  Table '$table' does not exist yet (count: ${count:-unknown})${NC}"
      all_exist=false
    fi
  done

  if [ "$all_exist" = true ]; then
    return 0
  else
    return 1
  fi
}

# Function to ensure database is ready (migrations run on app startup)
ensure_database_ready() {
  echo -e "${YELLOW}Ensuring database is ready...${NC}"

  # 1. Wait for governance service to be running
  echo "Waiting for governance service to be available..."
  kubectl wait --for=condition=available --timeout=300s \
    deployment/governance-platform-governance-service \
    -n "$NAMESPACE" 2>/dev/null || true

  # 2. Give the app time to run migrations on startup
  echo "Waiting for application to initialize and run migrations..."
  sleep 5

  # 3. Get database pod
  local db_pod=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=postgresql" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [ -z "$db_pod" ]; then
    echo -e "${RED}Error: Database pod not found${NC}"
    return 1
  fi

  # 4. Get PostgreSQL password
  echo "Getting database credentials..."
  local pg_password=$(get_postgres_password)
  if [ -z "$pg_password" ]; then
    echo -e "${RED}Error: Could not get PostgreSQL password${NC}"
    return 1
  fi

  # 5. Verify schema with retries
  echo "Verifying database schema..."
  local retries=5
  for i in $(seq 1 $retries); do
    if verify_database_schema "$db_pod" "$pg_password"; then
      echo -e "${GREEN}Database schema is ready${NC}"
      return 0
    fi

    if [ $i -lt $retries ]; then
      echo "Retry $i/$retries - waiting 30 seconds for migrations to complete..."
      sleep 30
    fi
  done

  # 6. Final check - if critical tables exist, proceed with warning
  local org_count=$(kubectl exec -n "$NAMESPACE" "$db_pod" -- \
    env PGPASSWORD="$pg_password" psql -U postgres -d governance -tA -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'organization';" 2>/dev/null)

  if [ "$org_count" = "1" ]; then
    echo -e "${YELLOW}Proceeding - organization table exists${NC}"
    return 0
  else
    echo -e "${RED}Warning: Database may not be fully initialized${NC}"
    return 1
  fi
}

# Function to create organization
create_organization() {
  echo -e "${YELLOW}Creating organization in database...${NC}"

  # Run the organization creation script
  "$SCRIPT_DIR/create-keycloak-organization.sh" \
    --namespace "$NAMESPACE" \
    --realm "$REALM_NAME" \
    --database "governance"
}

# Function to get platform-admin Keycloak ID
get_platform_admin_keycloak_id() {
  echo -e "${YELLOW}Getting platform-admin user ID from Keycloak...${NC}" >&2

  # Get external Keycloak URL
  local keycloak_url="$OVERRIDE_KEYCLOAK_URL"
  local ingress_host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null)

  if [ -z "$keycloak_url" ]; then
    if [ -n "$ingress_host" ]; then
      keycloak_url="https://$ingress_host/keycloak"
    else
      echo -e "${YELLOW}No ingress found, trying port-forward method${NC}" >&2
      # Start port-forward in background
      kubectl port-forward -n "$NAMESPACE" svc/keycloak 8080:80 &>/dev/null &
      local pf_pid=$!
      sleep 3
      keycloak_url="http://localhost:8080/keycloak"
    fi
  fi

  # Get admin password
  local admin_pass=$(kubectl get secret keycloak-admin -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)

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

# Function to verify integration
verify_integration() {
  echo -e "${YELLOW}Verifying Keycloak integration...${NC}"

  # Check Keycloak via external URL
  echo "Checking Keycloak realm..."

  # Get external Keycloak URL
  local keycloak_url=""
  local ingress_host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null)

  if [ -n "$ingress_host" ]; then
    keycloak_url="https://$ingress_host/keycloak"
  else
    echo -e "${YELLOW}No ingress found, trying port-forward method${NC}"
    # Start port-forward in background
    kubectl port-forward -n "$NAMESPACE" svc/keycloak 8080:80 &>/dev/null &
    local pf_pid=$!
    sleep 3
    keycloak_url="http://localhost:8080/keycloak"
  fi

  # Get admin password
  local admin_pass=$(kubectl get secret keycloak-admin -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)

  if [ -n "$admin_pass" ]; then
    # Get admin token
    local token_response=$(curl -sk -X POST "$keycloak_url/realms/master/protocol/openid-connect/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "username=admin" \
      -d "password=$admin_pass" \
      -d "grant_type=password" \
      -d "client_id=admin-cli" 2>/dev/null)

    local token=$(echo "$token_response" | jq -r '.access_token // empty')

    if [ -n "$token" ]; then
      # Check if realm exists
      local realm_check=$(curl -sk -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        "$keycloak_url/admin/realms/$REALM_NAME")

      if [ "$realm_check" = "200" ]; then
        echo -e "${GREEN}✓ Keycloak realm '$REALM_NAME' exists${NC}"

        # Check platform-admin user
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

  # Clean up port-forward if we started it
  [ -n "$pf_pid" ] && kill $pf_pid 2>/dev/null

  # Check organization in database
  echo "Checking organization in database..."
  local db_pod=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=postgresql" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [ -n "$db_pod" ]; then
    # Get PostgreSQL password
    local pg_password=$(get_postgres_password)

    if [ -n "$pg_password" ]; then
      local org_count=$(kubectl exec -n "$NAMESPACE" "$db_pod" -- \
        env PGPASSWORD="$pg_password" psql -U postgres -d governance -tA -c "SELECT COUNT(*) FROM organization WHERE name = '$REALM_NAME' AND idp_provider = 'keycloak';" 2>/dev/null)

      if [ "$org_count" = "1" ]; then
        echo -e "${GREEN}✓ Organization '$REALM_NAME' exists with idp_provider=keycloak${NC}"
      else
        echo -e "${RED}✗ Organization not found or incorrect idp_provider (count: ${org_count:-unknown})${NC}"
      fi

      # Check platform-admin user in auth service
      local user_count=$(kubectl exec -n "$NAMESPACE" "$db_pod" -- \
        env PGPASSWORD="$pg_password" psql -U postgres -d governance -tA -c "SELECT COUNT(*) FROM users WHERE email = 'admin@$REALM_NAME.local' AND idp_provider = 'keycloak';" 2>/dev/null)

      if [ "$user_count" = "1" ]; then
        echo -e "${GREEN}✓ Platform-admin user exists in auth service${NC}"

        # Check membership
        local membership_count=$(kubectl exec -n "$NAMESPACE" "$db_pod" -- \
          env PGPASSWORD="$pg_password" psql -U postgres -d governance -tA -c "SELECT COUNT(*) FROM user_organization_memberships uom JOIN users u ON uom.user_id = u.id WHERE u.email = 'admin@$REALM_NAME.local' AND 'organization_owner' = ANY(uom.roles);" 2>/dev/null)

        if [ "$membership_count" = "1" ]; then
          echo -e "${GREEN}✓ Platform-admin has organization_owner role${NC}"
        else
          echo -e "${RED}✗ Platform-admin missing organization_owner role (count: ${membership_count:-unknown})${NC}"
        fi
      else
        echo -e "${RED}✗ Platform-admin user not found in auth service (count: ${user_count:-unknown})${NC}"
      fi
    else
      echo -e "${YELLOW}Could not verify database - unable to get PostgreSQL password${NC}"
    fi
  else
    echo -e "${YELLOW}Could not find database pod${NC}"
  fi
}

# Function to show summary
show_summary() {
  echo ""
  echo -e "${BLUE}Setup Summary${NC}"
  echo -e "${BLUE}=============${NC}"
  echo ""

  echo "Database Setup Completed:"
  echo "  - Organization: $REALM_NAME (idp_provider=keycloak)"
  echo "  - Platform Admin: admin@$REALM_NAME.local"
  echo "  - Role: organization_owner"

  # Get Keycloak URL
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

  echo ""
  echo "To sync Keycloak user IDs (if needed):"
  echo "  $SCRIPT_DIR/sync-keycloak-user-ids.sh --namespace $NAMESPACE --realm $REALM_NAME"
}

# Main execution
main() {
  echo "This script sets up database entries after Keycloak bootstrap"
  echo ""
  echo -e "${YELLOW}Prerequisites:${NC}"
  echo "  - Keycloak must be deployed and running"
  echo "  - Keycloak bootstrap must be complete (realm, clients, users created)"
  echo "  - Governance platform must be deployed"
  echo ""

  # Step 1: Wait for platform
  wait_for_platform

  # Step 2: Ensure database is ready (migrations run on startup)
  ensure_database_ready

  # Step 3: Create organization
  echo ""
  read -p "Create organization in database? (y/n) [y]: " CREATE_ORG
  CREATE_ORG=${CREATE_ORG:-y}

  if [[ "$CREATE_ORG" =~ ^[Yy]$ ]]; then
    create_organization
  fi

  # Step 4: Create platform-admin user in database
  echo ""
  read -p "Create platform-admin user in auth service? (y/n) [y]: " CREATE_ADMIN
  CREATE_ADMIN=${CREATE_ADMIN:-y}

  if [[ "$CREATE_ADMIN" =~ ^[Yy]$ ]]; then
    # Get Keycloak user ID from existing platform-admin in Keycloak

    local user_id=$(get_platform_admin_keycloak_id)
    echo "USER ID LINE 521 -- $user_id"
    export KEYCLOAK_USER_ID=$user_id

    # Run the organization script with user creation
    "$SCRIPT_DIR/create-keycloak-organization.sh" \
      --namespace "$NAMESPACE" \
      --realm "$REALM_NAME" \
      --database "governance" <<<"n
y" # Answer n to create org (already done), y to create user
  fi

  # Step 5: Verify integration
  echo ""
  verify_integration

  # Step 6: Show summary
  show_summary

  echo ""
  echo -e "${GREEN}Post-install setup complete!${NC}"
}

# Run main function
main
