#!/usr/bin/env bash
# idp-setup.sh contains the database steps shared by scripts/{auth0,entra,keycloak}/post-install-*-setup.sh.
# The SQL mirrors charts/governance-platform/templates/hooks/_idp-setup.tpl.
#
# Callers set NAMESPACE, ORG_NAME, DISPLAY_NAME, IDP_PROVIDER and ADMIN_EMAIL before calling these functions.
# These environment variables override the defaults for non-standard installs:
#   PLATFORM_RELEASE  Helm release name of governance-platform (default: governance-platform)
#   DB_POD_SELECTOR   Label selector for the bundled PostgreSQL pod (default: app.kubernetes.io/name=postgresql)
#   DB_NAME           Database name (default: governance)
#   DB_USER           Database user (default: postgres)
#   DB_SECRET         Secret holding the database password (default: platform-database)
#   DB_SECRET_KEY     Key of the password in DB_SECRET (default: password)
#   CURL_INSECURE     Set to true to skip TLS verification on IdP API calls (default: false)

PLATFORM_RELEASE="${PLATFORM_RELEASE:-governance-platform}"
DB_POD_SELECTOR="${DB_POD_SELECTOR:-app.kubernetes.io/name=postgresql}"
DB_NAME="${DB_NAME:-governance}"
DB_USER="${DB_USER:-postgres}"
DB_SECRET="${DB_SECRET:-platform-database}"
DB_SECRET_KEY="${DB_SECRET_KEY:-password}"
CURL_INSECURE="${CURL_INSECURE:-false}"

DB_POD=""
PG_PASSWORD=""

# Print the environment overrides for a script's usage text
idp_setup_env_usage() {
  echo "\
Environment overrides (for non-default releases; the bundled PostgreSQL is required):
  PLATFORM_RELEASE  governance-platform release name (default: $PLATFORM_RELEASE)
  DB_POD_SELECTOR   PostgreSQL pod label selector (default: $DB_POD_SELECTOR)
  DB_NAME           Database name (default: $DB_NAME)
  DB_USER           Database user (default: $DB_USER)
  DB_SECRET         Database password secret (default: $DB_SECRET)
  DB_SECRET_KEY     Password key in DB_SECRET (default: $DB_SECRET_KEY)
  CURL_INSECURE     true to skip TLS verification on IdP API calls (default: $CURL_INSECURE)"
}

# Read and decode one key from a secret in NAMESPACE
secret_value() {
  local name=$1 key=$2
  kubectl get secret "$name" -n "$NAMESPACE" -o "go-template={{ index .data \"$key\" | base64decode }}" 2>/dev/null
}

# curl with errors shown, honouring CURL_INSECURE
idp_curl() {
  if [ "$CURL_INSECURE" = "true" ]; then
    curl -sS -k "$@"
  else
    curl -sS "$@"
  fi
}

# Execute psql via kubectl exec on the discovered database pod
run_psql() {
  kubectl exec -n "$NAMESPACE" "$DB_POD" -- \
    env PGPASSWORD="$PG_PASSWORD" psql -X -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" "$@"
}

# Execute a query and print its unaligned, header-free result
run_psql_scalar() {
  run_psql -q -tA -c "$1"
}

# Double single quotes (SQL and OData string escaping)
double_quotes() {
  local q="'"
  printf '%s' "${1//$q/$q$q}"
}

# Render a value as a SQL string literal
sql_lit() {
  printf "'%s'" "$(double_quotes "$1")"
}

# Wait for governance-service deployment and database pod to be ready
wait_for_platform() {
  print_warn "Waiting for Guardian Platform components..."

  echo "Checking for Governance Service deployment..."
  if ! kubectl get deployment "$PLATFORM_RELEASE-governance-service" -n "$NAMESPACE" &>/dev/null; then
    print_error "Deployment $PLATFORM_RELEASE-governance-service not found (set PLATFORM_RELEASE for a different release name)"
    echo "Available deployments:"
    kubectl get deployments -n "$NAMESPACE"
    return 1
  fi

  echo "Checking database pod..."
  local db_ready=false
  for _ in {1..30}; do
    if kubectl get pods -n "$NAMESPACE" -l "$DB_POD_SELECTOR" -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
      db_ready=true
      break
    fi
    echo -n "."
    sleep 5
  done

  if [ "$db_ready" = true ]; then
    print_info "Database pod is running"
  else
    print_error "No running pod matches $DB_POD_SELECTOR after 150 seconds (these scripts need the bundled PostgreSQL)"
    return 1
  fi

  DB_POD=$(kubectl get pods -n "$NAMESPACE" -l "$DB_POD_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$DB_POD" ]; then
    print_error "Could not find PostgreSQL pod"
    return 1
  fi

  echo "Checking database connectivity..."
  for _ in {1..10}; do
    if kubectl exec -n "$NAMESPACE" "$DB_POD" -- pg_isready -h localhost -U "$DB_USER" &>/dev/null; then
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

  echo "Waiting for Governance Service to be available..."
  kubectl wait --for=condition=available --timeout=300s \
    "deployment/$PLATFORM_RELEASE-governance-service" \
    -n "$NAMESPACE" 2>/dev/null || true

  echo "Getting database credentials..."
  PG_PASSWORD=$(secret_value "$DB_SECRET" "$DB_SECRET_KEY")
  if [ -z "$PG_PASSWORD" ]; then
    print_error "Could not read key '$DB_SECRET_KEY' from secret '$DB_SECRET'"
    echo "Available secrets that might contain database credentials:"
    kubectl get secrets -n "$NAMESPACE" | grep -E "(postgres|database|platform)"
    return 1
  fi

  # Matches the chart's init container: 30 attempts, 10s apart
  echo "Verifying database schema..."
  local required_tables=("organization" "users" "user_organization_memberships" "user_project_assignments")
  local retries=30

  for attempt in $(seq 1 $retries); do
    local all_exist=true
    for table in "${required_tables[@]}"; do
      local exists
      exists=$(run_psql_scalar "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = '$table');" 2>/dev/null || true)
      if [ "$exists" != "t" ]; then
        all_exist=false
        break
      fi
    done

    if [ "$all_exist" = true ]; then
      print_info "Database schema is ready"
      return 0
    fi

    if [ "$attempt" -lt $retries ]; then
      echo "Attempt $attempt/$retries - Waiting 10 seconds for migrations..."
      sleep 10
    fi
  done

  print_error "Database may not be fully initialized after $retries attempts"
  return 1
}

# Create the organization, or point an existing one at this IdP. display_name is only set on create.
# Sets ORG_ID.
upsert_org() {
  print_warn "Creating organization '$ORG_NAME'..."

  ORG_ID=$(run_psql_scalar "SELECT id FROM organization WHERE name = $(sql_lit "$ORG_NAME") ORDER BY id LIMIT 1;")
  if [ -n "$ORG_ID" ]; then
    run_psql -q -c "UPDATE organization SET idp_provider = $(sql_lit "$IDP_PROVIDER"), updated_at = NOW() WHERE id = $ORG_ID;"
    print_info "Organization '$ORG_NAME' already exists; set idp_provider to $IDP_PROVIDER"
  else
    ORG_ID=$(run_psql_scalar "INSERT INTO organization (name, description, display_name, idp_provider) \
      VALUES ($(sql_lit "$ORG_NAME"), $(sql_lit "$ORG_NAME"), $(sql_lit "$DISPLAY_NAME"), $(sql_lit "$IDP_PROVIDER")) RETURNING id;")
    print_info "Created organization '$ORG_NAME'"
  fi

  run_psql -c "SELECT id, name, display_name, idp_provider FROM organization WHERE id = $ORG_ID;"
}

# Create the platform admin user if missing, link it to the IdP account and make it an active
# organization owner. Existing organization roles are kept; project roles and project assignments in
# the organization are dropped because organization owners cannot hold them.
# Arguments: idp_user_id display_name given_name family_name
upsert_admin() {
  local idp_user_id=$1 display_name=$2 given_name=$3 family_name=$4
  local user_id match_idp linked

  print_warn "Creating platform admin user..."

  match_idp="(idp_provider = $(sql_lit "$IDP_PROVIDER") AND idp_user_id = $(sql_lit "$idp_user_id"))"
  user_id=$(run_psql_scalar "SELECT id FROM users WHERE email = $(sql_lit "$ADMIN_EMAIL") OR $match_idp \
    ORDER BY $match_idp DESC LIMIT 1;")

  if [ -n "$user_id" ]; then
    print_warn "Platform admin user already exists"
    # Point a row found by email at this IdP account (another IdP, a recreated IdP user, or the
    # placeholder IdP user ID written by older versions of these scripts)
    linked=$(run_psql_scalar "UPDATE users SET idp_provider = $(sql_lit "$IDP_PROVIDER"), \
        idp_user_id = $(sql_lit "$idp_user_id"), updated_at = NOW() \
      WHERE id = '$user_id' AND NOT $match_idp \
      RETURNING id;")
    if [ -n "$linked" ]; then
      print_info "Linked platform admin user to $IDP_PROVIDER user $idp_user_id"
    fi
  else
    user_id=$(run_psql_scalar "INSERT INTO users (idp_provider, idp_user_id, email, email_verified, display_name, given_name, family_name, active) \
      VALUES ($(sql_lit "$IDP_PROVIDER"), $(sql_lit "$idp_user_id"), $(sql_lit "$ADMIN_EMAIL"), true, \
              $(sql_lit "$display_name"), $(sql_lit "$given_name"), $(sql_lit "$family_name"), true) \
      RETURNING id;")
    print_info "Created platform admin user"
  fi

  run_psql -q -c "INSERT INTO user_organization_memberships (user_id, organization_id, roles, invited_at, joined_at, status) \
    VALUES ('$user_id', $ORG_ID, ARRAY['organization_owner'], NOW(), NOW(), 'active') \
    ON CONFLICT (user_id, organization_id) DO UPDATE SET \
      roles = ARRAY['organization_owner'] || ARRAY( \
        SELECT r FROM unnest(user_organization_memberships.roles) AS r \
        WHERE r <> ALL (ARRAY['organization_owner', 'project_owner', 'implementation_owner', \
          'implementation_contributor', 'audit_owner', 'audit_contributor', 'project_viewer'])), \
      status = 'active', \
      joined_at = COALESCE(user_organization_memberships.joined_at, NOW());"
  run_psql -q -c "DELETE FROM user_project_assignments WHERE user_id = '$user_id' AND organization_id = $ORG_ID;"
  print_info "Ensured organization_owner membership"

  echo ""
  echo "Platform admin user:"
  run_psql -c "SELECT id, email, display_name, idp_provider FROM users WHERE id = '$user_id';"
}

# Check the organization, admin user and owner membership the setup should have produced
verify_db_records() {
  print_warn "Verifying database records..."
  local failed=false

  local org_count
  org_count=$(run_psql_scalar "SELECT COUNT(*) FROM organization WHERE id = $ORG_ID AND idp_provider = $(sql_lit "$IDP_PROVIDER");")
  if [ "$org_count" = "1" ]; then
    print_info "Organization '$ORG_NAME' exists with idp_provider=$IDP_PROVIDER"
  else
    print_error "Organization not found or incorrect idp_provider (count: ${org_count:-unknown})"
    failed=true
  fi

  local owner_count
  owner_count=$(run_psql_scalar "SELECT COUNT(*) FROM user_organization_memberships uom \
    JOIN users u ON uom.user_id = u.id \
    WHERE u.email = $(sql_lit "$ADMIN_EMAIL") AND u.idp_provider = $(sql_lit "$IDP_PROVIDER") \
      AND u.idp_user_id <> '00000000-0000-0000-0000-000000000000' \
      AND uom.organization_id = $ORG_ID AND uom.status = 'active' AND 'organization_owner' = ANY(uom.roles);")
  if [ "$owner_count" = "1" ]; then
    print_info "Platform admin is an active organization_owner"
  else
    print_error "Platform admin is not an active organization_owner (count: ${owner_count:-unknown})"
    failed=true
  fi

  [ "$failed" = false ]
}

# Print the database part of the setup summary
show_db_summary() {
  echo "Database Setup Completed:"
  echo "  - Organization: $ORG_NAME (idp_provider=$IDP_PROVIDER)"
  echo "  - Platform Admin: $ADMIN_EMAIL"
  echo "  - Role: organization_owner"
}
