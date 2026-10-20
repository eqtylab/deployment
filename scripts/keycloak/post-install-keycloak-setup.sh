#!/usr/bin/env bash
set -e

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do SOURCE="$(readlink "$SOURCE")"; done
ROOTDIR="$(cd -P "$(dirname "$SOURCE")/../.." && pwd)"

# shellcheck source=../helpers/output.sh
source "$ROOTDIR/scripts/helpers/output.sh"
# shellcheck source=../helpers/assert.sh
source "$ROOTDIR/scripts/helpers/assert.sh"
# shellcheck source=../helpers/idp-setup.sh
source "$ROOTDIR/scripts/helpers/idp-setup.sh"

# Function to display usage
usage() {
  echo -e "\
Post-install database setup for Keycloak integration
Performs the same steps as the governance-platform keycloak.createOrganization Helm hook.

Usage: $0 -n <namespace> -k <keycloak-url> -e <admin-email> [options]
  -D, --display-name <name>       Organization display name, used when creating it (default: $DISPLAY_NAME)
  -e, --admin-email <email>       Platform admin email; must match keycloak-bootstrap users.admin.email (required)
  -h, --help                      Show this help message
  -k, --keycloak-url <url>        Keycloak URL (required, e.g. https://keycloak.example.com)
  -n, --namespace <namespace>     Kubernetes namespace (required)
  -r, --realm <realm>             Keycloak realm name, also used as the organization name (default: $ORG_NAME)

Keycloak admin credentials (must match keycloak-bootstrap keycloak.adminUsername / adminPasswordSecret):
  KEYCLOAK_ADMIN_USERNAME    Master realm admin user (default: $KEYCLOAK_ADMIN_USERNAME)
  KEYCLOAK_ADMIN_SECRET      Secret holding the admin password (default: $KEYCLOAK_ADMIN_SECRET)
  KEYCLOAK_ADMIN_SECRET_KEY  Password key in that secret (default: $KEYCLOAK_ADMIN_SECRET_KEY)

$(idp_setup_env_usage)

Examples:
  $0 -k https://governance.example.com/keycloak -n governance -e admin@example.com
  $0 -k https://governance.example.com/keycloak -n governance-stag --admin-email admin@example.com --realm my-realm
"
}

# Get a master realm admin token; prints nothing on failure
get_admin_token() {
  local admin_pass
  admin_pass=$(secret_value "$KEYCLOAK_ADMIN_SECRET" "$KEYCLOAK_ADMIN_SECRET_KEY")
  if [ -z "$admin_pass" ]; then
    print_error "Could not read key '$KEYCLOAK_ADMIN_SECRET_KEY' from secret '$KEYCLOAK_ADMIN_SECRET'" >&2
    return 1
  fi

  idp_curl -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    --data-urlencode "username=$KEYCLOAK_ADMIN_USERNAME" \
    --data-urlencode "password=$admin_pass" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "client_id=admin-cli" | jq -r '.access_token // empty'
}

# Look up the platform admin in the realm by email and create the database records
setup_platform_admin() {
  print_warn "Looking up '$ADMIN_EMAIL' in Keycloak realm '$ORG_NAME'..."

  local token
  token=$(get_admin_token) || true
  if [ -z "$token" ]; then
    print_error "Could not get a Keycloak admin token from $KEYCLOAK_URL"
    return 1
  fi

  local realm_path user_data user_id
  realm_path=$(jq -rn --arg realm "$ORG_NAME" '$realm | @uri')
  user_data=$(idp_curl -G -H "Authorization: Bearer $token" \
    --data-urlencode "email=$ADMIN_EMAIL" \
    --data-urlencode "exact=true" \
    "$KEYCLOAK_URL/admin/realms/$realm_path/users") || true
  user_id=$(jq -r '.[0].id // empty' <<<"$user_data" 2>/dev/null || true)

  if [ -z "$user_id" ]; then
    print_error "User '$ADMIN_EMAIL' not found in Keycloak realm '$ORG_NAME'"
    echo "The admin email must match keycloak-bootstrap users.admin.email (pass it with -e)."
    return 1
  fi
  print_info "Found Keycloak user ID: $user_id"

  # Empty Keycloak profile fields count as missing
  local display_name given_name family_name
  given_name=$(jq -r '(.[0].firstName // "") | if . == "" then "Platform" else . end' <<<"$user_data")
  family_name=$(jq -r '(.[0].lastName // "") | if . == "" then "Admin" else . end' <<<"$user_data")
  display_name=$(jq -r '.[0]
    | ([.firstName, .lastName] | map(select(. != null and . != "")) | join(" ")) as $name
    | if $name != "" then $name elif (.username // "") != "" then .username else "Platform Admin" end' <<<"$user_data")

  upsert_admin "$user_id" "$display_name" "$given_name" "$family_name"
}

# Display setup summary with URLs and next steps
show_summary() {
  echo ""
  print_info "Setup Summary"
  echo ""
  show_db_summary

  echo ""
  echo "Keycloak Information:"
  echo "  - Admin Console: $KEYCLOAK_URL/admin"
  echo "  - Realm: $KEYCLOAK_URL/admin/$ORG_NAME/console"

  echo ""
  echo "Next Steps:"
  echo "  1. Test login with the platform admin user"
  echo "  2. Verify token exchange with Auth Service"
  echo "  3. Check that users can access the Guardian Platform"
}

# Orchestrate the full post-install setup workflow
main() {
  echo "This script sets up database entries after Keycloak bootstrap"
  echo ""
  print_warn "Prerequisites:"
  echo "  - Keycloak must be deployed and running"
  echo "  - Keycloak bootstrap must be complete (realm, clients, users created)"
  echo "  - Guardian Platform must be deployed"
  echo ""

  wait_for_platform
  ensure_database_ready

  echo ""
  upsert_org

  echo ""
  setup_platform_admin

  echo ""
  verify_db_records

  show_summary

  echo ""
  print_info "Post-install setup complete!"
}

# shellcheck disable=SC2034 # read by helpers/idp-setup.sh
IDP_PROVIDER="keycloak"
ORG_NAME="governance"
DISPLAY_NAME="Guardian"

NAMESPACE=""
KEYCLOAK_URL=""
ADMIN_EMAIL=""
KEYCLOAK_ADMIN_USERNAME="${KEYCLOAK_ADMIN_USERNAME:-admin}"
KEYCLOAK_ADMIN_SECRET="${KEYCLOAK_ADMIN_SECRET:-keycloak-admin}"
KEYCLOAK_ADMIN_SECRET_KEY="${KEYCLOAK_ADMIN_SECRET_KEY:-password}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -D | --display-name)
    DISPLAY_NAME="$2"
    shift 2
    ;;
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
assert_not_empty "keycloak-url" "$KEYCLOAK_URL" "Use -k or --keycloak-url to provide the Keycloak URL."
assert_not_empty "admin-email" "$ADMIN_EMAIL" "Use -e or --admin-email to provide the email in keycloak-bootstrap users.admin.email."

# Run post-install setup
main
