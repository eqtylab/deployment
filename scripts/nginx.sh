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
Install an NGINX ingress controller via Helm

Usage: $0 [options]
  -n, --namespace <namespace>     Namespace for ingress-nginx (default: $NAMESPACE)
  -h, --help                      Show this help message

Examples:
  $0
  $0 --namespace somewhere-else
"
}

# Install NGINX ingress controller into the specified namespace
install() {
  print_info "Installing ingress-nginx to $NAMESPACE namespace"

  # Add the ingress-nginx Helm repository
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  
  # Update your local Helm chart repository cache
  helm repo update

  # Install the ingress-nginx Helm chart
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --create-namespace \
    --namespace "$NAMESPACE" \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

  print_info "ingress-nginx installed"
}

# Default values
NAMESPACE="ingress-nginx"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -n | --namespace)
    NAMESPACE="$2"
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

# Install ingress-nginx
install
