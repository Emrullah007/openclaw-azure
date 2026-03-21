#!/usr/bin/env bash
# ============================================================
# OpenClaw — Teardown Script
# Deletes the entire resource group and all resources inside.
# ⚠️  This is IRREVERSIBLE. All data will be lost.
# Usage: ./scripts/destroy.sh
# ============================================================

set -euo pipefail

RESOURCE_GROUP="openclaw-rg"

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
