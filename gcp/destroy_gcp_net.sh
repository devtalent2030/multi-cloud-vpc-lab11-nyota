#!/usr/bin/env bash
# ======================================================================
# Title   : destroy_gcp_net.sh
# Purpose : Tear down resources created by build_gcp_net.sh
# Notes   : Deletes NAT first (only billable item), then router,
#           firewall rules, subnets, and VPC network.
# ======================================================================
set -euo pipefail

LASTNAME="nyota"
REGION="northamerica-northeast1"

VPC="${LASTNAME}-vpc"
PUB_SUB="${LASTNAME}-pub-subnet"
PRI_SUB="${LASTNAME}-pri-subnet"
ROUTER="${LASTNAME}-router"
NAT="${LASTNAME}-nat"
FW_INTERNAL="${LASTNAME}-allow-internal"
FW_IAP="${LASTNAME}-allow-iap-ssh"

echo "🧹  Starting clean-up in project: $(gcloud config get-value project)"
gcloud config set compute/region "$REGION" >/dev/null

# 1. Delete Cloud NAT
if gcloud compute routers nats describe "$NAT" --router "$ROUTER" --region "$REGION" &>/dev/null; then
  echo "▶︎ Deleting Cloud NAT $NAT"
  gcloud compute routers nats delete "$NAT" \
        --router "$ROUTER" --region "$REGION" -q
fi

# 2. Delete Router
gcloud compute routers delete "$ROUTER" --region "$REGION" -q || true

# 3. Delete firewall rules
gcloud compute firewall-rules delete "$FW_INTERNAL" "$FW_IAP" -q || true

# 4. Delete subnets (must specify region)
for SUB in "$PUB_SUB" "$PRI_SUB"; do
  gcloud compute networks subnets delete "$SUB" --region "$REGION" -q || true
done

# 5. Delete VPC network
gcloud compute networks delete "$VPC" -q || true

echo "✔️  All GCP lab resources removed"
