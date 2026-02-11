#!/usr/bin/env bash
set -e


SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do SOURCE="$(readlink "$SOURCE")"; done
ROOTDIR="$(cd -P "$(dirname "$SOURCE")/.." && pwd)"

# shellcheck source=./helpers/output.sh
source "$ROOTDIR/scripts/helpers/output.sh"
# shellcheck source=./helpers/assert.sh
source "$ROOTDIR/scripts/helpers/assert.sh"

# Function to display usage
usage() {
  echo -e "\
Install cert-manager and create a Let's Encrypt Issuer

Usage: $0 [options]
  -e, --email <email>             Email for Let's Encrypt registration (required)
  -n, --namespace <namespace>     Namespace for the Issuer (default: $NAMESPACE)
  -i, --issuer-name <name>        Issuer name (default: $ISSUER_NAME)
  -h, --help                      Show this help message

Examples:
  $0 -e admin@example.com
  $0 -e admin@example.com --namespace governance-stag
  $0 -e admin@example.com --issuer-name letsencrypt-stag
"
}

# Install cert-manager and create a Let's Encrypt Issuer in the specified namespace
install() {
  print_info "Installing cert-manager"

  # Add the Jetstack Helm repository
  helm repo add jetstack https://charts.jetstack.io

  # Update your local Helm chart repository cache
  helm repo update

  # Install the cert-manager Helm chart
  helm install \
    cert-manager jetstack/cert-manager \
    --namespace ingress-nginx \
    --create-namespace \
    --set crds.enabled=true

  print_info "Creating Issuer '$ISSUER_NAME' in namespace: $NAMESPACE"

  kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: $ISSUER_NAME
  namespace: $NAMESPACE
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $EMAIL
    privateKeySecretRef:
      name: letsencrypt-production
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
EOF

  print_info "cert-manager installed and Issuer created"
}

# Default values
NAMESPACE="governance"
ISSUER_NAME="letsencrypt-prod"
EMAIL=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -e | --email)
    EMAIL="$2"
    shift 2
    ;;
  -n | --namespace)
    NAMESPACE="$2"
    shift 2
    ;;
  -i | --issuer-name)
    ISSUER_NAME="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
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
assert_not_empty "email" "$EMAIL" "Use -e or --email to provide a Let's Encrypt registration email."

# Install cert-manager
install
