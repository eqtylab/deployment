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
Install cert-manager via Helm

Usage: $0 [options]
  -n, --namespace <namespace>     Namespace for cert-manager (default: $NAMESPACE)
  -h, --help                      Show this help message

Examples:
  $0
  $0 --namespace cert-manager
"
}

# Install cert-manager
install() {
  print_info "Installing cert-manager"

  # Add the Jetstack Helm repository
  helm repo add jetstack https://charts.jetstack.io

  # Update your local Helm chart repository cache
  helm repo update

  # Install the cert-manager Helm chart
  helm install \
    cert-manager jetstack/cert-manager \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set crds.enabled=true

  print_info "cert-manager installed"
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

# Install cert-manager
install
