#!/usr/bin/env bash
# ======================================================================
# Title   : build_gcp_net.sh
# Author  : <your-name>
# Purpose : Provision a public / private network baseline in GCP
#           (Custom VPC, two /24 subnets, Cloud Router + Cloud NAT,
#            minimal firewall rules).
# Notes   : • Runs in Cloud Shell (uses gcloud SDK already authenticated)
#           • Idempotent: re-runs skip existing resources.
#           • Edit ONLY the USER VARIABLES section.
# ======================================================================

set -euo pipefail

# ── USER VARIABLES ────────────────────────────────────────────────────
LASTNAME="nyota"                      # personal prefix
REGION="northamerica-northeast1"      # Montréal (use northeast2 for Toronto)
VPC_CIDR="10.0.0.0/16"
PUB_CIDR="10.0.1.0/24"
PRI_CIDR="10.0.2.0/24"
# ──────────────────────────────────────────────────────────────────────

# Derived names
VPC="${LASTNAME}-vpc"
PUB_SUB="${LASTNAME}-pub-subnet"
PRI_SUB="${LASTNAME}-pri-subnet"
ROUTER="${LASTNAME}-router"
NAT="${LASTNAME}-nat"
FW_INTERNAL="${LASTNAME}-allow-internal"
FW_IAP="${LASTNAME}-allow-iap-ssh"

echo "👷  Project: $(gcloud config get-value project)  •  Region: $REGION"
gcloud config set compute/region "$REGION"   >/dev/null

# ── 1. VPC NETWORK ────────────────────────────────────────────────────
if ! gcloud compute networks describe "$VPC" &>/dev/null; then
  echo "▶︎ Creating custom VPC $VPC"
  gcloud compute networks create "$VPC" \
        --subnet-mode=custom \
        --bgp-routing-mode=regional
else
  echo "ℹ︎ VPC $VPC already exists"
fi

# ── 2. SUBNETS ────────────────────────────────────────────────────────
create_subnet () {
  local NAME=$1 CIDR=$2
  if ! gcloud compute networks subnets describe "$NAME" --region "$REGION" &>/dev/null; then
    echo "▶︎ Creating subnet $NAME ($CIDR)"
    gcloud compute networks subnets create "$NAME" \
          --network "$VPC" \
          --region  "$REGION" \
          --range   "$CIDR" \
          --enable-private-ip-google-access
  else
    echo "ℹ︎ Subnet $NAME exists"
  fi
}
create_subnet "$PUB_SUB" "$PUB_CIDR"
create_subnet "$PRI_SUB" "$PRI_CIDR"

# ── 3. FIREWALL RULES (SG analogue) ───────────────────────────────────
# Allow intra-VPC traffic
gcloud compute firewall-rules describe "$FW_INTERNAL" &>/dev/null || \
gcloud compute firewall-rules create "$FW_INTERNAL" \
        --network "$VPC" \
        --allow tcp,udp,icmp \
        --source-ranges "$VPC_CIDR"

# Allow IAP-based SSH (no public IP required)
gcloud compute firewall-rules describe "$FW_IAP" &>/dev/null || \
gcloud compute firewall-rules create "$FW_IAP" \
        --network "$VPC" \
        --allow tcp:22 \
        --source-ranges 35.235.240.0/20 \
        --target-tags ssh-iap

# ── 4. CLOUD ROUTER & CLOUD NAT (egress only) ─────────────────────────
if ! gcloud compute routers describe "$ROUTER" --region "$REGION" &>/dev/null; then
  echo "▶︎ Creating Cloud Router $ROUTER"
  gcloud compute routers create "$ROUTER" \
        --network "$VPC" \
        --region  "$REGION"
else
  echo "ℹ︎ Router exists"
fi

if ! gcloud compute routers nats describe "$NAT" \
        --router "$ROUTER" --region "$REGION" &>/dev/null; then
  echo "▶︎ Creating Cloud NAT $NAT"
  gcloud compute routers nats create "$NAT" \
        --router "$ROUTER" \
        --region "$REGION" \
        --auto-allocate-nat-external-ips \
        --nat-all-subnet-ip-ranges
else
  echo "ℹ︎ Cloud NAT exists"
fi

echo "✅  GCP network build complete"
