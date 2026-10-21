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
Post-install database setup for Entra ID integration
Performs the same steps as the guardian-platform chart's entra.createOrganization Helm hook.

Usage: $0 -n <namespace> -e <admin-email> [options]
  -D, --display-name <name>       Organization display name, used when creating it (default: $DISPLAY_NAME)
  -e, --admin-email <email>       Platform admin email in Entra tenant (required)
  -h, --help                      Show this help message
  -n, --namespace <namespace>     Kubernetes namespace (required)
  -o, --org-name <name>           Organization name (default: $ORG_NAME)

Graph API credentials:
  ENTRA_SECRET                    Secret holding them (default: $ENTRA_SECRET)
  ENTRA_TENANT_ID_KEY             Tenant ID key (default: $ENTRA_TENANT_ID_KEY)
  ENTRA_GRAPH_CLIENT_ID_KEY       Client ID key (default: $ENTRA_GRAPH_CLIENT_ID_KEY)
  ENTRA_GRAPH_CLIENT_SECRET_KEY   Client secret key (default: $ENTRA_GRAPH_CLIENT_SECRET_KEY)

$(idp_setup_env_usage)

Examples:
  $0 -n guardian -e admin@contoso.com
  $0 -n guardian-stag --admin-email admin@contoso.com --org-name my-org
"
}

# Look up the platform admin in Entra by email and create the database records
setup_platform_admin() {
  print_warn "Looking up '$ADMIN_EMAIL' in Entra..."

  local client_id client_secret tenant_id
  client_id=$(secret_value "$ENTRA_SECRET" "$ENTRA_GRAPH_CLIENT_ID_KEY")
  client_secret=$(secret_value "$ENTRA_SECRET" "$ENTRA_GRAPH_CLIENT_SECRET_KEY")
  tenant_id=$(secret_value "$ENTRA_SECRET" "$ENTRA_TENANT_ID_KEY")
  if [ -z "$client_id" ] || [ -z "$client_secret" ] || [ -z "$tenant_id" ]; then
    print_error "Could not read Graph API credentials and tenant ID from secret '$ENTRA_SECRET'"
    return 1
  fi

  local token
  token=$(idp_curl -X POST "https://login.microsoftonline.com/${tenant_id}/oauth2/v2.0/token" \
    --data-urlencode "client_id=$client_id" \
    --data-urlencode "client_secret=$client_secret" \
    --data-urlencode "scope=https://graph.microsoft.com/.default" \
    --data-urlencode "grant_type=client_credentials" | jq -r '.access_token // empty') || true
  if [ -z "$token" ]; then
    print_error "Could not get a Graph API token"
    return 1
  fi

  # Match on mail or userPrincipalName; single quotes are doubled for OData
  local odata_email
  odata_email=$(double_quotes "$ADMIN_EMAIL")
  local user_data user_id
  user_data=$(idp_curl -G -H "Authorization: Bearer $token" \
    --data-urlencode "\$filter=mail eq '$odata_email' or userPrincipalName eq '$odata_email'" \
    --data-urlencode "\$select=id,mail,displayName,givenName,surname" \
    "https://graph.microsoft.com/v1.0/users") || true
  user_id=$(jq -r '.value[0].id // empty' <<<"$user_data" 2>/dev/null || true)

  if [ -z "$user_id" ]; then
    print_error "User '$ADMIN_EMAIL' not found in Entra"
    return 1
  fi
  print_info "Found Entra user ID: $user_id"

  upsert_admin "$user_id" \
    "$(jq -r '.value[0].displayName // "Platform Admin"' <<<"$user_data")" \
    "$(jq -r '.value[0].givenName // "Platform"' <<<"$user_data")" \
    "$(jq -r '.value[0].surname // "Admin"' <<<"$user_data")"
}

# Display setup summary with next steps
show_summary() {
  echo ""
  print_info "Setup Summary"
  echo ""
  show_db_summary

  echo ""
  echo "Next Steps:"
  echo "  1. Test login with the platform admin user via Entra"
  echo "  2. Verify token exchange with Auth Service"
  echo "  3. Check that users can access the Guardian Platform"
}

# Orchestrate the full post-install setup workflow
main() {
  echo "This script sets up database entries after Entra bootstrap"
  echo ""
  print_warn "Prerequisites:"
  echo "  - Entra app registrations must be complete"
  echo "  - $ENTRA_SECRET secret must exist with Graph API credentials and tenant ID"
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
IDP_PROVIDER="entra"
ORG_NAME="guardian"
DISPLAY_NAME="Guardian"

NAMESPACE=""
ADMIN_EMAIL=""
ENTRA_SECRET="${ENTRA_SECRET:-platform-entra}"
ENTRA_TENANT_ID_KEY="${ENTRA_TENANT_ID_KEY:-tenant-id}"
ENTRA_GRAPH_CLIENT_ID_KEY="${ENTRA_GRAPH_CLIENT_ID_KEY:-graph-client-id}"
ENTRA_GRAPH_CLIENT_SECRET_KEY="${ENTRA_GRAPH_CLIENT_SECRET_KEY:-graph-client-secret}"

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
