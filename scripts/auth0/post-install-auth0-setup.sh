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
Post-install database setup for Auth0 integration
Performs the same steps as the governance-platform auth0.createOrganization Helm hook.

Usage: $0 -n <namespace> -d <auth0-domain> -e <admin-email> [options]
  -D, --display-name <name>       Organization display name, used when creating it (default: $DISPLAY_NAME)
  -d, --auth0-domain <domain>     Auth0 tenant domain (required, e.g. tenant.us.auth0.com)
  -e, --admin-email <email>       Platform admin email in the Auth0 tenant (required)
  -h, --help                      Show this help message
  -n, --namespace <namespace>     Kubernetes namespace (required)
  -o, --org-name <name>           Organization name (default: $ORG_NAME)

Auth0 Management API credentials:
  AUTH0_SECRET                    Secret holding them (default: $AUTH0_SECRET)
  AUTH0_MGMT_CLIENT_ID_KEY        Client ID key (default: $AUTH0_MGMT_CLIENT_ID_KEY)
  AUTH0_MGMT_CLIENT_SECRET_KEY    Client secret key (default: $AUTH0_MGMT_CLIENT_SECRET_KEY)

$(idp_setup_env_usage)

Examples:
  $0 -n governance -d tenant.us.auth0.com -e admin@example.com
  $0 -n governance-stag --auth0-domain tenant.us.auth0.com --admin-email admin@example.com --org-name my-org
"
}

# Look up the platform admin in Auth0 by email and create the database records
setup_platform_admin() {
  print_warn "Looking up '$ADMIN_EMAIL' in Auth0 tenant $AUTH0_DOMAIN..."

  local client_id client_secret
  client_id=$(secret_value "$AUTH0_SECRET" "$AUTH0_MGMT_CLIENT_ID_KEY")
  client_secret=$(secret_value "$AUTH0_SECRET" "$AUTH0_MGMT_CLIENT_SECRET_KEY")
  if [ -z "$client_id" ] || [ -z "$client_secret" ]; then
    print_error "Could not read Management API credentials from secret '$AUTH0_SECRET'"
    return 1
  fi

  local token_request token
  token_request=$(jq -n \
    --arg client_id "$client_id" \
    --arg client_secret "$client_secret" \
    --arg audience "https://${AUTH0_DOMAIN}/api/v2/" \
    '{client_id: $client_id, client_secret: $client_secret, audience: $audience, grant_type: "client_credentials"}')
  token=$(idp_curl -X POST "https://${AUTH0_DOMAIN}/oauth/token" \
    -H "Content-Type: application/json" \
    -d "$token_request" | jq -r '.access_token // empty') || true
  if [ -z "$token" ]; then
    print_error "Could not get an Auth0 Management API token"
    return 1
  fi

  local user_data user_id
  user_data=$(idp_curl -G -H "Authorization: Bearer $token" \
    --data-urlencode "email=$ADMIN_EMAIL" \
    "https://${AUTH0_DOMAIN}/api/v2/users-by-email") || true
  user_id=$(jq -r '.[0].user_id // empty' <<<"$user_data" 2>/dev/null || true)

  if [ -z "$user_id" ]; then
    print_error "User '$ADMIN_EMAIL' not found in Auth0 tenant $AUTH0_DOMAIN"
    return 1
  fi
  print_info "Found Auth0 user ID: $user_id"

  upsert_admin "$user_id" \
    "$(jq -r '.[0].name // "Platform Admin"' <<<"$user_data")" \
    "$(jq -r '.[0].given_name // "Platform"' <<<"$user_data")" \
    "$(jq -r '.[0].family_name // "Admin"' <<<"$user_data")"
}

# Display setup summary with next steps
show_summary() {
  echo ""
  print_info "Setup Summary"
  echo ""
  show_db_summary

  echo ""
  echo "Auth0 Information:"
  echo "  - Tenant Domain: $AUTH0_DOMAIN"
  echo "  - Dashboard:     https://manage.auth0.com/"

  echo ""
  echo "Next Steps:"
  echo "  1. Test login with the platform admin user via Auth0"
  echo "  2. Verify token exchange with auth service"
  echo "  3. Check that users can access the governance platform"
}

# Orchestrate the full post-install setup workflow
main() {
  echo "This script sets up database entries after Auth0 bootstrap"
  echo ""
  print_warn "Prerequisites:"
  echo "  - Auth0 bootstrap must be complete (applications, API, scopes created)"
  echo "  - $AUTH0_SECRET secret must exist with Management API credentials"
  echo "  - Governance platform must be deployed"
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
IDP_PROVIDER="auth0"
ORG_NAME="governance"
DISPLAY_NAME="Governance Studio"

NAMESPACE=""
AUTH0_DOMAIN=""
ADMIN_EMAIL=""
AUTH0_SECRET="${AUTH0_SECRET:-platform-auth0}"
AUTH0_MGMT_CLIENT_ID_KEY="${AUTH0_MGMT_CLIENT_ID_KEY:-mgmt-client-id}"
AUTH0_MGMT_CLIENT_SECRET_KEY="${AUTH0_MGMT_CLIENT_SECRET_KEY:-mgmt-client-secret}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -D | --display-name)
    DISPLAY_NAME="$2"
    shift 2
    ;;
  -d | --auth0-domain)
    AUTH0_DOMAIN="$2"
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
assert_not_empty "auth0-domain" "$AUTH0_DOMAIN" "Use -d or --auth0-domain to provide the Auth0 tenant domain."
assert_not_empty "admin-email" "$ADMIN_EMAIL" "Use -e or --admin-email to provide the platform admin's Auth0 email."

# Run post-install setup
main
