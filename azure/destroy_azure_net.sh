#!/usr/bin/env bash
# =========================================================================
# Title   : destroy_azure_net.sh
# Purpose : Remove every resource created by build_azure_net.sh
#           – simplest way is to delete the resource group.
#           – NAT Gateway goes first to stop hourly billing ASAP.
# =========================================================================
set -euo pipefail

PREFIX="nyota"
AZ_REGION="canadacentral"
RG="${PREFIX}-rg"
NATGW="${PREFIX}-natgw"
PIP="${NATGW}-pip"

echo "🗑  Cleaning up resource group $RG in $AZ_REGION"

# Optional: delete NAT explicitly so billing stops immediately
az network nat gateway show -g "$RG" -n "$NATGW" &>/dev/null && \
az network nat gateway delete -g "$RG" -n "$NATGW" -y

# Delete public IP (Standard SKU billed separately)
az network public-ip show -g "$RG" -n "$PIP" &>/dev/null && \
az network public-ip delete -g "$RG" -n "$PIP"

# Delete entire RG (includes VNet, NSG, route table, subnets, etc.)
az group delete -n "$RG" --yes --no-wait

echo "✔️  All Azure lab resources scheduled for deletion"
