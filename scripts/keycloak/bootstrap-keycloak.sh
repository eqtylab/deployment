#!/bin/bash

# Simplified bootstrap script for Keycloak without SPI mappers or groups
# Groups/projects are now managed in the governance service

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="governance"
BOOTSTRAP_RELEASE="keycloak-bootstrap"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "$SCRIPT_DIR/../../charts/keycloak-bootstrap" && pwd)"

echo -e "${BLUE}Simplified Keycloak Bootstrap for Governance Platform${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""
echo "This will create:"
echo "- Governance realm with token exchange enabled"
echo "- Platform admin user (no groups)"
echo "- Three OAuth clients:"
echo "  - Frontend (public client)"
echo "  - Backend (confidential with service account)"
echo "  - Worker (service account only)"
echo "- Custom authorization scopes"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check if Keycloak pod is running
KEYCLOAK_READY=$(kubectl get pod -l app=keycloak -n "$NAMESPACE" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$KEYCLOAK_READY" != "True" ]; then
  echo -e "${RED}Error: Keycloak pod is not ready${NC}"
  kubectl get pod -l app=keycloak -n "$NAMESPACE"
  exit 1
fi
echo -e "${GREEN}✓ Keycloak is running${NC}"

# Check required secrets
MISSING_SECRETS=()
for secret in keycloak-admin keycloak-backend-client keycloak-worker-client keycloak-admin-user; do
  if ! kubectl get secret "$secret" -n "$NAMESPACE" &>/dev/null; then
    MISSING_SECRETS+=("$secret")
  fi
done

if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
  echo -e "${RED}Error: Missing required secrets:${NC}"
  printf '%s\n' "${MISSING_SECRETS[@]}"
  echo ""
  echo "Create them with:"
  echo "  kubectl create secret generic keycloak-admin --from-literal=password=<admin-password> -n $NAMESPACE"
  echo "  kubectl create secret generic keycloak-backend-client --from-literal=client-secret=<backend-secret> -n $NAMESPACE"
  echo "  kubectl create secret generic keycloak-worker-client --from-literal=client-secret=<worker-secret> -n $NAMESPACE"
  echo "  kubectl create secret generic keycloak-admin-user --from-literal=password=<platform-admin-password> -n $NAMESPACE"
  exit 1
fi
echo -e "${GREEN}✓ All required secrets exist${NC}"

# Clean up any existing bootstrap jobs
echo ""
echo -e "${YELLOW}Cleaning up any existing bootstrap jobs...${NC}"
kubectl delete job -l app.kubernetes.io/instance="$BOOTSTRAP_RELEASE" -n "$NAMESPACE" --ignore-not-found

# Run the bootstrap
echo ""
echo -e "${YELLOW}Running Keycloak bootstrap...${NC}"

# Install the bootstrap chart with values
helm upgrade --install "$BOOTSTRAP_RELEASE" "$CHART_DIR" \
  -n "$NAMESPACE" \
  -f "$SCRIPT_DIR/values-bootstrap-keycloak.yaml" \
  --wait \
  --timeout 10m

# Get the job name
JOB_NAME=$(kubectl get job -l app.kubernetes.io/instance="$BOOTSTRAP_RELEASE" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$JOB_NAME" ]; then
  echo -e "${RED}Error: Bootstrap job not found${NC}"
  exit 1
fi

echo "Bootstrap job: $JOB_NAME"

# Monitor job completion
echo ""
echo -e "${YELLOW}Monitoring bootstrap job...${NC}"

# Wait for job to complete
TIMEOUT=300
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  JOB_STATUS=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
  JOB_FAILED=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)

  if [ "$JOB_STATUS" = "True" ]; then
    echo -e "${GREEN}✓ Bootstrap completed successfully${NC}"
    break
  elif [ "$JOB_FAILED" = "True" ]; then
    echo -e "${RED}Bootstrap job failed${NC}"
    echo "Job logs:"
    kubectl logs job/"$JOB_NAME" -n "$NAMESPACE" --tail=50
    exit 1
  fi

  echo -n "."
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo -e "${RED}Bootstrap job timed out${NC}"
  kubectl logs job/"$JOB_NAME" -n "$NAMESPACE" --tail=50
  exit 1
fi

# Show logs
echo ""
echo -e "${YELLOW}Bootstrap logs (last 20 lines):${NC}"
kubectl logs job/"$JOB_NAME" -n "$NAMESPACE" --tail=20

# Display results
echo ""
echo -e "${BLUE}Bootstrap Complete!${NC}"
echo -e "${BLUE}=================${NC}"
echo ""
echo "Keycloak URLs:"
echo "- Admin Console: https://DOMAIN/keycloak/admin"
echo "- Governance Realm: https://DOMAIN/keycloak/admin/governance/console"
echo ""

# Show credentials
if kubectl get secret keycloak-admin -n "$NAMESPACE" &>/dev/null; then
  ADMIN_PASSWORD=$(kubectl get secret --namespace "$NAMESPACE" keycloak-admin -o jsonpath="{.data.password}" | base64 -d)
  echo "Keycloak Admin (master realm):"
  echo "  Username: admin"
  echo "  Password: $ADMIN_PASSWORD"
  echo ""
fi

if kubectl get secret keycloak-admin-user -n "$NAMESPACE" &>/dev/null; then
  PLATFORM_ADMIN_PASSWORD=$(kubectl get secret --namespace "$NAMESPACE" keycloak-admin-user -o jsonpath="{.data.password}" | base64 -d)
  echo "Platform Admin (governance realm):"
  echo "  Username: platform-admin"
  echo "  Password: $PLATFORM_ADMIN_PASSWORD"
  echo ""
fi

echo "OAuth Clients:"
echo "- Frontend: governance-platform-frontend (public client)"
echo "- Backend: governance-platform-backend (confidential with service account)"
echo "- Worker: governance-worker (service account only)"
echo ""
echo "Token Exchange: Enabled for Auth Service integration"

# Cleanup
echo ""
echo -e "${YELLOW}Cleaning up completed job...${NC}"
kubectl delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found

echo ""
echo -e "${GREEN}Bootstrap process completed!${NC}"
