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
  -h, --help                      Show this help message

Examples:
  $0
"
}

# Install NGINX ingress controller into the specified namespace
install() {
  print_info "Installing ingress-nginx to $NAMESPACE namespace"

  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm repo update

  helm install ingress-nginx ingress-nginx/ingress-nginx \
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
