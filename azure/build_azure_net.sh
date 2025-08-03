#!/usr/bin/env bash
# =========================================================================
# Title   : build_azure_net.sh
# Author  : <your-name>
# Purpose : Provision a two-tier VNet in Azure:
#           ▸ 1 VNet (/16)
#           ▸ Public + private /24 subnets
#           ▸ NAT Gateway for controlled egress
#           ▸ Route table for private subnet
#           ▸ NSG applied to both subnets (default deny-in / allow-out)
# Notes   : • Designed for Azure Cloud Shell (az CLI pre-installed).
#           • Re-runs are safe; existing resources are skipped.
# =========================================================================
set -euo pipefail

# ── USER VARIABLES ───────────────────────────────────────────────────────
PREFIX="nyota"                 # personal label for all names
AZ_REGION="canadacentral"      # or "canadaeast"
VNET_CIDR="10.0.0.0/16"
PUB_CIDR="10.0.1.0/24"
PRI_CIDR="10.0.2.0/24"
# ─────────────────────────────────────────────────────────────────────────

# Derived names
RG="${PREFIX}-rg"
VNET="${PREFIX}-vnet"
PUB_SN="${PREFIX}-pub-subnet"
PRI_SN="${PREFIX}-pri-subnet"
NATGW="${PREFIX}-natgw"
PIP="${NATGW}-pip"
RT="${PREFIX}-rt"
NSG="${PREFIX}-nsg"

echo "🔧  Subscription: $(az account show --query name -o tsv)"
echo "🔧  Region      : $AZ_REGION"

# ── 1. Resource Group ----------------------------------------------------
az group show -n "$RG" &>/dev/null || az group create -n "$RG" -l "$AZ_REGION"

# ── 2. VNet & subnets ----------------------------------------------------
az network vnet show -g "$RG" -n "$VNET" &>/dev/null || \
az network vnet create -g "$RG" -n "$VNET" -l "$AZ_REGION" \
    --address-prefix "$VNET_CIDR" \
    --subnet-name "$PUB_SN"     --subnet-prefix "$PUB_CIDR"

# Private subnet (created separately so we can attach RT later)
az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$PRI_SN" &>/dev/null || \
az network vnet subnet create -g "$RG" --vnet-name "$VNET" \
    -n "$PRI_SN" --address-prefix "$PRI_CIDR"

# ── 3. NAT Gateway (egress) ---------------------------------------------
if ! az network nat gateway show -g "$RG" -n "$NATGW" &>/dev/null; then
  az network public-ip create -g "$RG" -n "$PIP" \
        --sku Standard --allocation-method Static
  az network nat gateway create -g "$RG" -n "$NATGW" \
        --public-ip-addresses "$PIP" --idle-timeout 10
fi

# Attach NAT to both subnets (egress via same gateway)
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$PUB_SN" --nat-gateway "$NATGW"
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$PRI_SN" --nat-gateway "$NATGW"

# ── 4. Route table for private subnet -----------------------------------
az network route-table show -g "$RG" -n "$RT" &>/dev/null || \
az network route-table create -g "$RG" -n "$RT"

# Default route so private subnet can reach Internet via NAT GW
ROUTE_EXISTS=$(az network route-table route list -g "$RG" --route-table-name "$RT" \
                 --query "[?name=='default-to-internet']" -o tsv | wc -l)
if [[ "$ROUTE_EXISTS" -eq 0 ]]; then
  az network route-table route create -g "$RG" --route-table-name "$RT" \
       -n default-to-internet --address-prefix 0.0.0.0/0 --next-hop-type Internet
fi
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$PRI_SN" --route-table "$RT"

# ── 5. Network Security Group -------------------------------------------
az network nsg show -g "$RG" -n "$NSG" &>/dev/null || \
az network nsg create -g "$RG" -n "$NSG"

# Associate NSG with both subnets (defaults: deny-in / allow-out)
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$PUB_SN" --network-security-group "$NSG"
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$PRI_SN" --network-security-group "$NSG"

echo "✅  Azure network build complete"
