#!/usr/bin/env bash

# This script installs an nginx ingress controller
set -e

NAMESPACE=ingress-nginx

echo "Installing ingress-nginx to $NAMESPACE namespace"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --create-namespace \
  --namespace $NAMESPACE \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
