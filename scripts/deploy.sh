#!/usr/bin/env bash
# ============================================================
# OpenClaw — Azure Deployment Script
# Prerequisites: Azure CLI installed and logged in (az login)
# Usage: ./scripts/deploy.sh
# ============================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────
RESOURCE_GROUP="openclaw-rg"
LOCATION="westus2"          # West US 2 — closest to Seattle area
DEPLOYMENT_NAME="openclaw-$(date +%Y%m%d-%H%M%S)"
PARAMS_FILE="infra/parameters.json"

# ── Pre-flight checks ─────────────────────────────────────────
if ! command -v az &>/dev/null; then
  echo "❌ Azure CLI not found. Install: https://docs.microsoft.com/cli/azure/install-azure-cli"
  exit 1
fi

if [ ! -f "$PARAMS_FILE" ]; then
  echo "❌ parameters.json not found."
  echo "   Copy infra/parameters.example.json → infra/parameters.json and fill in your values."
  exit 1
fi

# ── Login check ───────────────────────────────────────────────
echo "🔐 Checking Azure login..."
az account show --output table || { echo "Run: az login"; exit 1; }

# ── Resource Group ────────────────────────────────────────────
echo ""
echo "📦 Creating resource group: $RESOURCE_GROUP in $LOCATION..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output table

# ── Deploy Bicep ──────────────────────────────────────────────
echo ""
echo "🚀 Deploying infrastructure (this takes ~2-3 minutes)..."
RESULT=$(az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "infra/main.bicep" \
  --parameters "@$PARAMS_FILE" \
  --output json)

# ── Print outputs ─────────────────────────────────────────────
PUBLIC_IP=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['properties']['outputs']['publicIpAddress']['value'])")
SSH_CMD=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['properties']['outputs']['sshCommand']['value'])")

echo ""
echo "✅ Deployment complete!"
echo ""
echo "   Public IP : $PUBLIC_IP"
echo "   SSH        : $SSH_CMD"
echo "   Tunnel     : ssh -L 18789:localhost:18789 azureuser@$PUBLIC_IP"
echo ""
echo "Next step: run ./scripts/setup-vm.sh $PUBLIC_IP"
