#!/usr/bin/env bash

## This script installs cert-manager and creates a Let's Encrypt Issuer

set -e

# Default values
NAMESPACE="governance"
ISSUER_NAME="letsencrypt-prod"
EMAIL=""

# Function to print usage
usage() {
  echo "Usage: $0 -e <email> [OPTIONS]"
  echo ""
  echo "Required:"
  echo "  -e, --email <email>               Email address for Let's Encrypt registration"
  echo ""
  echo "Options:"
  echo "  -n, --namespace <namespace>       Namespace for the Issuer (default: $NAMESPACE)"
  echo "  -i, --issuer-name <name>          Issuer name (default: $ISSUER_NAME)"
  echo "  -h, --help                        Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0 -e admin@example.com"
  echo "  $0 -e admin@example.com --namespace governance-stag"
  echo "  $0 -e admin@example.com --issuer-name letsencrypt-staging"
}

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
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
  esac
done

# Validate required parameters
if [ -z "$EMAIL" ]; then
  echo "Error: Email is required"
  echo ""
  usage
  exit 1
fi

echo "Installing cert-manager"

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

echo "Creating Issuer '$ISSUER_NAME' in namespace: $NAMESPACE"

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

echo "cert-manager installed and Issuer created"
