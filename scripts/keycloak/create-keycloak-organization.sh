#!/bin/bash

# Script to create organization in governance service database for Keycloak realm
# This should be run AFTER the governance platform is deployed

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_NAMESPACE="governance"
DEFAULT_REALM="governance"
DEFAULT_DB_NAME="governance"

# Function to print usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -n, --namespace <namespace>    Kubernetes namespace (default: $DEFAULT_NAMESPACE)"
  echo "  -r, --realm <realm>           Keycloak realm name (default: $DEFAULT_REALM)"
  echo "  -d, --database <database>     Database name (default: $DEFAULT_DB_NAME)"
  echo "  -p, --pod <pod>              Specific pod name (optional, will auto-detect)"
  echo "  -h, --help                   Show this help message"
  echo ""
  echo "Example:"
  echo "  $0 --namespace governance-stag --realm governance"
}

# Parse arguments
NAMESPACE=$DEFAULT_NAMESPACE
REALM_NAME=$DEFAULT_REALM
DB_NAME=$DEFAULT_DB_NAME
POD_NAME=""

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
  -d | --database)
    DB_NAME="$2"
    shift 2
    ;;
  -p | --pod)
    POD_NAME="$2"
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

echo -e "${BLUE}Creating Keycloak Organization in Governance Database${NC}"
echo -e "${BLUE}==================================================${NC}"
echo ""
echo "Namespace: $NAMESPACE"
echo "Realm/Organization: $REALM_NAME"
echo "Database: $DB_NAME"
echo ""

# Function to get PostgreSQL password
get_postgres_password() {
  # Try common secret names
  local password=""

  # Try compliance-secrets first
  password=$(kubectl get secret -n "$NAMESPACE" compliance-secrets -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

  if [ -z "$password" ]; then
    # Try generic postgresql secret
    password=$(kubectl get secret -n "$NAMESPACE" postgresql -o jsonpath="{.data.postgres-password}" 2>/dev/null | base64 -d)
  fi

  if [ -z "$password" ]; then
    # Try with different keys
    password=$(kubectl get secret -n "$NAMESPACE" compliance-secrets -o jsonpath="{.data.postgres-password}" 2>/dev/null | base64 -d)
  fi

  if [ -z "$password" ]; then
    # List available secrets for debugging
    echo -e "${RED}Error: Could not find PostgreSQL password${NC}"
    echo "Available PostgreSQL secrets:"
    kubectl get secrets -n "$NAMESPACE" | grep -E "(postgres|sql)"
    return 1
  fi

  echo "$password"
}

# Function to find governance database pod
find_db_pod() {
  echo -e "${YELLOW}Finding governance database pod...${NC}"

  if [ -n "$POD_NAME" ]; then
    echo "Using specified pod: $POD_NAME"
    return
  fi

  # Try to find the governance PostgreSQL pod
  POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=postgresql,app.kubernetes.io/instance=governance-platform" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [ -z "$POD_NAME" ]; then
    # Try alternative label
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l "app=postgresql" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  fi

  if [ -z "$POD_NAME" ]; then
    echo -e "${RED}Error: Could not find PostgreSQL pod${NC}"
    echo "Please specify pod name with -p option"
    kubectl get pods -n "$NAMESPACE"
    exit 1
  fi

  echo "Found pod: $POD_NAME"
}

# Function to check if organization exists
check_org_exists() {
  echo -e "${YELLOW}Checking if organization already exists...${NC}"

  RESULT=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -tA -c "SELECT COUNT(*) FROM organization WHERE name = '$REALM_NAME';" 2>/dev/null)

  if [ "$RESULT" = "1" ]; then
    echo -e "${GREEN}Organization '$REALM_NAME' already exists${NC}"

    # Show existing organization
    echo ""
    echo "Existing organization details:"
    kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -c "SELECT id, name, display_name, idp_provider, created_at FROM organization WHERE name = '$REALM_NAME';"
    return 0
  else
    return 1
  fi
}

# Function to create organization
create_organization() {
  echo -e "${YELLOW}Creating organization '$REALM_NAME'...${NC}"

  # Prepare SQL statement
  SQL="INSERT INTO organization (name, description, display_name, idp_provider, settings, created_at, updated_at) VALUES ('$REALM_NAME', '$REALM_NAME', '${REALM_NAME^}', 'keycloak', '{}', NOW(), NOW()) RETURNING id, name, display_name, idp_provider;"

  # Execute SQL
  RESULT=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -c "$SQL" 2>&1)

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Organization created successfully!${NC}"
    echo ""
    echo "$RESULT"
  else
    echo -e "${RED}Failed to create organization${NC}"
    echo "$RESULT"
    exit 1
  fi
}

# Function to verify tables exist
verify_tables() {
  echo -e "${YELLOW}Verifying database tables exist...${NC}"

  # Check for all required tables
  local required_tables=("organization" "users" "user_organization_memberships")
  local all_exist=true
  local missing_tables=()

  for table in "${required_tables[@]}"; do
    local count=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
      env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -tA -c \
      "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$table';" 2>/dev/null)

    if [ "$count" != "1" ]; then
      all_exist=false
      missing_tables+=("$table")
    fi
  done

  if [ "$all_exist" = true ]; then
    echo -e "${GREEN}✓ All required tables exist${NC}"
    return 0
  else
    echo -e "${RED}Error: Required tables are missing:${NC}"
    printf '  - %s\n' "${missing_tables[@]}"
    echo ""
    echo "This usually means:"
    echo "1. The governance platform is not deployed yet, OR"
    echo "2. The application hasn't started and run migrations yet"
    echo ""
    echo "Please ensure:"
    echo "1. Governance platform is deployed"
    echo "2. Wait for the governance-service to be running"
    echo "3. Try again in a minute"

    # Show existing tables for debugging
    echo ""
    echo "Existing tables in database:"
    kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -c "\dt" 2>/dev/null || echo "Could not list tables"

    exit 1
  fi
}

# Main execution
main() {
  # Find database pod
  find_db_pod

  # Get PostgreSQL password
  echo -e "${YELLOW}Getting database credentials...${NC}"
  PG_PASSWORD=$(get_postgres_password)
  if [ -z "$PG_PASSWORD" ]; then
    exit 1
  fi
  export PG_PASSWORD # Make it available to all functions

  # Verify tables exist
  verify_tables

  # Check if organization exists
  if check_org_exists; then
    read -p "Organization already exists. Do you want to update it? (y/n) [n]: " UPDATE_ORG
    UPDATE_ORG=${UPDATE_ORG:-n}

    if [[ "$UPDATE_ORG" =~ ^[Yy]$ ]]; then
      echo -e "${YELLOW}Updating organization...${NC}"
      UPDATE_SQL="UPDATE organization SET idp_provider = 'keycloak', updated_at = NOW() WHERE name = '$REALM_NAME' RETURNING id, name, display_name, idp_provider;"
      kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -c "$UPDATE_SQL"
      echo -e "${GREEN}Organization updated${NC}"
    fi
  else
    # Create organization
    create_organization
  fi

  # Create platform-admin user if requested
  echo ""
  read -p "Create platform-admin user in auth service? (y/n) [y]: " CREATE_USER
  CREATE_USER=${CREATE_USER:-y}

  if [[ "$CREATE_USER" =~ ^[Yy]$ ]]; then
    create_platform_admin_user
  fi

  echo ""
  echo -e "${GREEN}Done!${NC}"
  echo ""
  echo "Next steps:"
  echo "1. Run Keycloak bootstrap to create the '$REALM_NAME' realm"
  echo "2. Users authenticated through Keycloak will be associated with this organization"
}

# Function to create platform-admin user
create_platform_admin_user() {
  echo -e "${YELLOW}Creating platform-admin user in auth service...${NC}"

  # Get Keycloak admin user ID from bootstrap (we'll use a placeholder for now)
  local KEYCLOAK_USER_ID="${KEYCLOAK_USER_ID:-$(uuidgen | tr '[:upper:]' '[:lower:]')}"
  local USER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

  # Check if user already exists
  local USER_EXISTS=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -tA -c "SELECT COUNT(*) FROM users WHERE email = 'admin@$REALM_NAME.local';" 2>/dev/null)

  if [ "$USER_EXISTS" = "1" ]; then
    echo -e "${YELLOW}Platform admin user already exists${NC}"
    # Get existing user ID
    USER_ID=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -tA -c "SELECT id FROM users WHERE email = 'admin@$REALM_NAME.local';" 2>/dev/null | tr -d ' ')
  else
    # Create user
    USER_SQL="INSERT INTO users (id, idp_provider, idp_user_id, email, email_verified, display_name, given_name, family_name, active, app_metadata, created_at, updated_at, is_service_account, service_config) VALUES ('$USER_ID', 'keycloak', '$KEYCLOAK_USER_ID', 'admin@$REALM_NAME.local', true, 'Platform Admin', 'Platform', 'Admin', true, '{}', NOW(), NOW(), false, '{}') RETURNING id;"

    RESULT=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -c "$USER_SQL" 2>&1)

    if [ $? -eq 0 ]; then
      echo -e "${GREEN}Platform admin user created successfully${NC}"
    else
      echo -e "${RED}Failed to create platform admin user${NC}"
      echo "$RESULT"
      return 1
    fi
  fi

  # Get organization ID
  local ORG_ID=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -tA -c "SELECT id FROM organization WHERE name = '$REALM_NAME';" 2>/dev/null | tr -d ' ')

  if [ -z "$ORG_ID" ]; then
    echo -e "${RED}Error: Organization not found${NC}"
    return 1
  fi

  # Check if membership already exists
  local MEMBERSHIP_EXISTS=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -tA -c "SELECT COUNT(*) FROM user_organization_memberships WHERE user_id = '$USER_ID' AND organization_id = $ORG_ID;" 2>/dev/null)

  if [ "$MEMBERSHIP_EXISTS" = "1" ]; then
    echo -e "${YELLOW}Organization membership already exists${NC}"
    # Update to ensure owner role
    UPDATE_SQL="UPDATE user_organization_memberships SET roles = '{organization_owner}', status = 'active' WHERE user_id = '$USER_ID' AND organization_id = $ORG_ID;"
    kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -c "$UPDATE_SQL"
  else
    # Create membership
    MEMBERSHIP_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    MEMBERSHIP_SQL="INSERT INTO user_organization_memberships (id, user_id, organization_id, roles, invited_at, joined_at, status) VALUES ('$MEMBERSHIP_ID', '$USER_ID', $ORG_ID, '{organization_owner}', NOW(), NOW(), 'active');"

    kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -c "$MEMBERSHIP_SQL"

    if [ $? -eq 0 ]; then
      echo -e "${GREEN}Organization membership created successfully${NC}"
    else
      echo -e "${RED}Failed to create organization membership${NC}"
      return 1
    fi
  fi

  # Show the created user and membership
  echo ""
  echo "Platform admin user:"
  kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -c "SELECT id, email, display_name, idp_provider FROM users WHERE email = 'admin@$REALM_NAME.local';"

  echo ""
  echo "Organization membership:"
  kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PG_PASSWORD" psql -U postgres -d "$DB_NAME" -c "SELECT m.*, o.name as org_name FROM user_organization_memberships m JOIN organization o ON m.organization_id = o.id WHERE m.user_id = '$USER_ID';"
}

# Run main function
main
