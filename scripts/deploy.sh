#!/usr/bin/env bash
# ============================================================
# OpenClaw — Interactive Azure Deployment Script
# Asks for region, resource group, and VM name interactively.
# Checks DNS availability before deploying.
# Usage: ./scripts/deploy.sh
# ============================================================

set -euo pipefail

PARAMS_FILE="infra/parameters.json"

# ── Colors ────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       OpenClaw — Azure Deployment        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────
if ! command -v az &>/dev/null; then
  echo -e "${RED}❌ Azure CLI not found.${NC}"
  echo "   Install: https://docs.microsoft.com/cli/azure/install-azure-cli"
  exit 1
fi

if [ ! -f "$PARAMS_FILE" ]; then
  echo -e "${RED}❌ infra/parameters.json not found.${NC}"
  echo "   Copy infra/parameters.example.json → infra/parameters.json and fill in sshPublicKey and allowedSshSourceIp."
  exit 1
fi

# ── Azure login check ─────────────────────────────────────────
echo -e "${CYAN}🔐 Checking Azure login...${NC}"
az account show --output table 2>/dev/null || {
  echo -e "${RED}❌ Not logged in. Run: az login --use-device-code${NC}"
  exit 1
}

# ── Region selection ──────────────────────────────────────────
echo ""
echo -e "${CYAN}🌍 Select Azure Region:${NC}"
echo ""
echo "   [1] West US 2        (Washington)                      ~\$24/mo"
echo "   [2] West US 3        (Phoenix)                         ~\$24/mo"
echo "   [3] East US          (Virginia)                        ~\$22/mo"
echo "   [4] Central US       (Iowa)                            ~\$23/mo"
echo "   [5] West Europe      (Netherlands)                     ~\$27/mo"
echo "   [6] North Europe     (Ireland)                         ~\$25/mo"
echo ""
read -p "   Enter number [1]: " REGION_CHOICE
REGION_CHOICE="${REGION_CHOICE:-1}"

case "$REGION_CHOICE" in
  1) LOCATION="westus2";    REGION_LABEL="West US 2 (Washington)" ;;
  2) LOCATION="westus3";    REGION_LABEL="West US 3 (Phoenix)" ;;
  3) LOCATION="eastus";     REGION_LABEL="East US (Virginia)" ;;
  4) LOCATION="centralus";  REGION_LABEL="Central US (Iowa)" ;;
  5) LOCATION="westeurope"; REGION_LABEL="West Europe (Netherlands)" ;;
  6) LOCATION="northeurope";REGION_LABEL="North Europe (Ireland)" ;;
  *) echo -e "${RED}❌ Invalid choice.${NC}"; exit 1 ;;
esac

echo -e "   ${GREEN}✔ Region: $REGION_LABEL ($LOCATION)${NC}"

# ── Resource group name ───────────────────────────────────────
echo ""
read -p "   Resource group name [openclaw-rg]: " RESOURCE_GROUP
RESOURCE_GROUP="${RESOURCE_GROUP:-openclaw-rg}"
echo -e "   ${GREEN}✔ Resource group: $RESOURCE_GROUP${NC}"

# ── VM name with DNS availability check ───────────────────────
echo ""
echo -e "${CYAN}🖥️  VM Name (used as DNS prefix: <name>.$LOCATION.cloudapp.azure.com)${NC}"
echo ""

while true; do
  read -p "   Enter VM name [openclaw-vm]: " VM_NAME
  VM_NAME="${VM_NAME:-openclaw-vm}"

  # Validate: lowercase letters, numbers, hyphens only
  if ! [[ "$VM_NAME" =~ ^[a-z0-9-]+$ ]]; then
    echo -e "   ${RED}❌ Name must contain only lowercase letters, numbers, and hyphens.${NC}"
    continue
  fi

  DNS_FQDN="${VM_NAME}.${LOCATION}.cloudapp.azure.com"
  echo -e "   Checking DNS availability for ${CYAN}${DNS_FQDN}${NC}..."

  if host "$DNS_FQDN" &>/dev/null 2>&1; then
    echo -e "   ${RED}❌ '$DNS_FQDN' is already taken. Please choose a different name.${NC}"
  else
    echo -e "   ${GREEN}✔ '$DNS_FQDN' is available!${NC}"
    break
  fi
done

# ── Admin username ────────────────────────────────────────────
echo ""
read -p "   Admin username [azureuser]: " ADMIN_USERNAME
ADMIN_USERNAME="${ADMIN_USERNAME:-azureuser}"
echo -e "   ${GREEN}✔ Admin username: $ADMIN_USERNAME${NC}"

# ── Summary ───────────────────────────────────────────────────
echo ""
echo -e "${CYAN}─────────────────────────────────────────────${NC}"
echo -e "  Region:         $REGION_LABEL"
echo -e "  Resource Group: $RESOURCE_GROUP"
echo -e "  VM Name:        $VM_NAME"
echo -e "  Admin User:     $ADMIN_USERNAME"
echo -e "  DNS:            $DNS_FQDN"
echo -e "${CYAN}─────────────────────────────────────────────${NC}"
echo ""
read -p "   Proceed with deployment? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Create Resource Group ─────────────────────────────────────
echo ""
echo -e "${CYAN}📦 Creating resource group: $RESOURCE_GROUP in $LOCATION...${NC}"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output table

# ── Deploy Bicep ──────────────────────────────────────────────
DEPLOYMENT_NAME="openclaw-$(date +%Y%m%d-%H%M%S)"

echo ""
echo -e "${CYAN}🚀 Deploying infrastructure (~3 minutes)...${NC}"
RESULT=$(az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "infra/main.bicep" \
  --parameters "@$PARAMS_FILE" \
  --parameters \
    location="$LOCATION" \
    vmName="$VM_NAME" \
    adminUsername="$ADMIN_USERNAME" \
  --output json)

# ── Print outputs ─────────────────────────────────────────────
PUBLIC_IP=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['properties']['outputs']['publicIpAddress']['value'])")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅  Deployment complete!                        ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}  Public IP  : $PUBLIC_IP"
echo -e "${GREEN}║${NC}  DNS        : $DNS_FQDN"
echo -e "${GREEN}║${NC}  SSH        : ssh $ADMIN_USERNAME@$PUBLIC_IP"
echo -e "${GREEN}║${NC}  Tunnel     : ssh -L 18789:localhost:18789 $ADMIN_USERNAME@$PUBLIC_IP"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "   Next step: ${CYAN}./scripts/setup-vm.sh $PUBLIC_IP${NC}"
echo ""

# Save deployment info for other scripts to use
cat > .deployment-info <<EOF
VM_NAME=$VM_NAME
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
ADMIN_USERNAME=$ADMIN_USERNAME
PUBLIC_IP=$PUBLIC_IP
DNS_FQDN=$DNS_FQDN
EOF
echo -e "   ${YELLOW}ℹ Deployment info saved to .deployment-info${NC}"
