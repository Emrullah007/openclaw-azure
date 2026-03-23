#!/usr/bin/env bash
# ============================================================
# OpenClaw — Teardown Script
# Deletes the entire resource group and all resources inside.
# ⚠️  This is IRREVERSIBLE. All data will be lost.
# Usage: ./scripts/destroy.sh
# ============================================================

set -euo pipefail

# ── Pre-flight checks ─────────────────────────────────────────
if ! command -v az &>/dev/null; then
  echo "❌ Azure CLI not found. Install: https://docs.microsoft.com/cli/azure/install-azure-cli"
  exit 1
fi

az account show --output none 2>/dev/null || {
  echo "❌ Not logged in to Azure. Run: az login --use-device-code"
  exit 1
}

# Read resource group from last deployment if available
if [ -f ".deployment-info" ]; then
  # shellcheck source=/dev/null
  source .deployment-info
  echo "ℹ️  Loaded deployment info: resource group '$RESOURCE_GROUP'"
else
  RESOURCE_GROUP="openclaw-rg"
  echo "ℹ️  No .deployment-info found, defaulting to: $RESOURCE_GROUP"
fi

echo ""
echo "⚠️  WARNING: This will permanently delete resource group: $RESOURCE_GROUP"
echo "   All VMs, disks, IPs, and networking resources will be destroyed."
echo ""
read -p "Type the resource group name to confirm: " CONFIRM

if [ "$CONFIRM" != "$RESOURCE_GROUP" ]; then
  echo "❌ Confirmation mismatch. Aborting."
  exit 1
fi

echo ""
echo "🗑️  Deleting resource group $RESOURCE_GROUP..."
az group delete \
  --name "$RESOURCE_GROUP" \
  --yes \
  --no-wait

echo ""
echo "✅ Deletion initiated. Azure is cleaning up in the background."
echo "   Check status: az group show --name $RESOURCE_GROUP"
