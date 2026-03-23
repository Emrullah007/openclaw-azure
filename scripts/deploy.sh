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

# Detect unfilled placeholders in parameters.json before touching Azure
if grep -qE "your-public-key-here|YOUR_IP_ADDRESS" "$PARAMS_FILE"; then
  echo -e "${RED}❌ infra/parameters.json still contains example placeholder values.${NC}"
  echo "   Fill in sshPublicKey (your actual public key) and allowedSshSourceIp (your IP/32)."
  exit 1
fi

# ── Azure login check ─────────────────────────────────────────
echo -e "${CYAN}🔐 Checking Azure login...${NC}"
az account show --output table 2>/dev/null || {
  echo -e "${RED}❌ Not logged in. Run: az login --use-device-code${NC}"
  exit 1
}

# ── Resource group name ───────────────────────────────────────
echo ""
read -p "   Resource group name [openclaw-rg]: " RESOURCE_GROUP
RESOURCE_GROUP="${RESOURCE_GROUP:-openclaw-rg}"
echo -e "   ${GREEN}✔ Resource group: $RESOURCE_GROUP${NC}"

# ── VM name with DNS availability check ───────────────────────
# (DNS is region-scoped; re-check happens inside the region loop if needed)
echo ""
while true; do
  read -p "   Enter VM name [openclaw-vm]: " VM_NAME
  VM_NAME="${VM_NAME:-openclaw-vm}"

  # 3-15 chars, start with letter, end with letter/number, hyphens in middle only
  if ! [[ "$VM_NAME" =~ ^[a-z][a-z0-9-]{1,13}[a-z0-9]$ ]]; then
    echo -e "   ${RED}❌ Name must be 3-15 chars, start with a letter, end with a letter or number, hyphens allowed in between.${NC}"
    continue
  fi
  break
done

# ── Admin username ────────────────────────────────────────────
echo ""
while true; do
  read -p "   Admin username [azureuser]: " ADMIN_USERNAME
  ADMIN_USERNAME="${ADMIN_USERNAME:-azureuser}"

  # Linux username rules: start with letter/underscore, letters/numbers/hyphens/underscores, max 32 chars
  if ! [[ "$ADMIN_USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo -e "   ${RED}❌ Username must start with a letter or underscore, contain only lowercase letters, numbers, hyphens, underscores, and be max 32 chars.${NC}"
    continue
  fi
  if [[ "$ADMIN_USERNAME" =~ ^(root|admin|administrator|guest|nobody|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|gnats|sshd|ubuntu)$ ]]; then
    echo -e "   ${RED}❌ '$ADMIN_USERNAME' is a reserved system username. Please choose another.${NC}"
    continue
  fi
  break
done
echo -e "   ${GREEN}✔ Admin username: $ADMIN_USERNAME${NC}"

# ── Region + deployment loop (retries on SKU capacity failure) ─
while true; do
  echo ""
  echo -e "${CYAN}🌍 Select Azure Region:${NC}"
  echo ""
  echo "   [1] East US          (Virginia)                        ~\$22/mo  ← most available"
  echo "   [2] West US 2        (Washington)                      ~\$24/mo"
  echo "   [3] West US 3        (Phoenix)                         ~\$24/mo"
  echo "   [4] Central US       (Iowa)                            ~\$23/mo"
  echo "   [5] West Europe      (Netherlands)                     ~\$27/mo"
  echo "   [6] North Europe     (Ireland)                         ~\$25/mo"
  echo ""
  read -p "   Enter number [1]: " REGION_CHOICE
  REGION_CHOICE="${REGION_CHOICE:-1}"

  case "$REGION_CHOICE" in
    1) LOCATION="eastus";      REGION_LABEL="East US (Virginia)" ;;
    2) LOCATION="westus2";     REGION_LABEL="West US 2 (Washington)" ;;
    3) LOCATION="westus3";     REGION_LABEL="West US 3 (Phoenix)" ;;
    4) LOCATION="centralus";   REGION_LABEL="Central US (Iowa)" ;;
    5) LOCATION="westeurope";  REGION_LABEL="West Europe (Netherlands)" ;;
    6) LOCATION="northeurope"; REGION_LABEL="North Europe (Ireland)" ;;
    *) echo -e "${RED}❌ Invalid choice.${NC}"; continue ;;
  esac

  echo -e "   ${GREEN}✔ Region: $REGION_LABEL ($LOCATION)${NC}"

  # DNS availability check (region-scoped)
  while true; do
    DNS_FQDN="${VM_NAME}.${LOCATION}.cloudapp.azure.com"
    echo -e "   Checking DNS availability for ${CYAN}${DNS_FQDN}${NC}..."
    if nslookup "$DNS_FQDN" &>/dev/null 2>&1; then
      echo -e "   ${RED}❌ '$DNS_FQDN' is already taken in this region.${NC}"
      read -p "   Enter a different VM name [openclaw-vm]: " VM_NAME
      VM_NAME="${VM_NAME:-openclaw-vm}"
      if ! [[ "$VM_NAME" =~ ^[a-z][a-z0-9-]{1,13}[a-z0-9]$ ]]; then
        echo -e "   ${RED}❌ Name must be 3-15 chars, start with a letter, end with a letter or number, hyphens allowed in between.${NC}"
        VM_NAME="openclaw-vm"
      fi
      continue
    fi
    echo -e "   ${GREEN}✔ '$DNS_FQDN' is available!${NC}"
    break
  done

  # ── Summary ─────────────────────────────────────────────────
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

  # ── Create Resource Group ───────────────────────────────────
  echo ""
  echo -e "${CYAN}📦 Creating resource group: $RESOURCE_GROUP in $LOCATION...${NC}"
  az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output table

  # ── Deploy Bicep ────────────────────────────────────────────
  DEPLOYMENT_NAME="openclaw-$(date +%Y%m%d-%H%M%S)"

  echo ""
  echo -e "${CYAN}🚀 Deploying infrastructure (~3 minutes)...${NC}"

  set +e
  DEPLOY_OUTPUT=$(az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" \
    --template-file "infra/main.bicep" \
    --parameters "@$PARAMS_FILE" \
    --parameters \
      location="$LOCATION" \
      vmName="$VM_NAME" \
      adminUsername="$ADMIN_USERNAME" \
    --output none 2>&1)
  DEPLOY_EXIT=$?
  set -e

  if [ $DEPLOY_EXIT -ne 0 ]; then
    if echo "$DEPLOY_OUTPUT" | grep -q "SkuNotAvailable"; then
      echo ""
      echo -e "${RED}❌ Standard_B2als_v2 is not available in $REGION_LABEL right now.${NC}"
      echo -e "   This is an Azure capacity issue — your configuration is correct."
      echo ""
      echo -e "   Cleaning up empty resource group (this takes ~1 minute)..."
      az group delete --name "$RESOURCE_GROUP" --yes 2>/dev/null || true
      echo ""
      read -p "   Try a different region? [Y/n]: " RETRY
      RETRY="${RETRY:-Y}"
      [[ "$RETRY" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
      continue
    else
      echo "$DEPLOY_OUTPUT"
      echo ""
      echo -e "${RED}❌ Deployment failed. See error above.${NC}"
      exit 1
    fi
  fi

  # Deployment succeeded — exit the loop
  break
done

# ── Print outputs ─────────────────────────────────────────────
PUBLIC_IP=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --query "properties.outputs.publicIpAddress.value" -o tsv)

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
echo -e "   Next steps: ${CYAN}./scripts/setup-vm.sh${NC}  →  ${CYAN}./scripts/configure-openclaw.sh${NC}"
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
