#!/usr/bin/env bash
# =======================================================================
# Title: destroy_aws_net.sh
# Purpose: Tear down the lab environment created by build_aws_net.sh
#          – delete NAT first (billing), then subnets, IGW, and VPC.
# =======================================================================
set -euo pipefail

PREFIX="nyota"
AWS_REGION="us-east-1"

VPC_NAME="${PREFIX}-vpc"
IGW_NAME="${PREFIX}-igw"
NAT_NAME="${PREFIX}-natgw"
PUB_SUB="${PREFIX}-pub-subnet"
PRI_SUB="${PREFIX}-pri-subnet"
PUB_RT="${PREFIX}-pub-rt"
PRI_RT="${PREFIX}-pri-rt"

aws configure set default.region "$AWS_REGION"

# ── Locate IDs (skip if not found) ──────────────────────────────────────
get_id() { aws ec2 "$1" --filters "Name=tag:Name,Values=$2" \
           --query "$3" --output text 2>/dev/null || true; }

VPC_ID=$(get_id describe-vpcs       "$VPC_NAME" 'Vpcs[0].VpcId')
IGW_ID=$(get_id describe-internet-gateways "$IGW_NAME" 'InternetGateways[0].InternetGatewayId')
NAT_ID=$(get_id describe-nat-gateways "$NAT_NAME" 'NatGateways[0].NatGatewayId')
PUB_RT_ID=$(get_id describe-route-tables "$PUB_RT" 'RouteTables[0].RouteTableId')
PRI_RT_ID=$(get_id describe-route-tables "$PRI_RT" 'RouteTables[0].RouteTableId')
PUB_SUB_ID=$(get_id describe-subnets "$PUB_SUB" 'Subnets[0].SubnetId')
PRI_SUB_ID=$(get_id describe-subnets "$PRI_SUB" 'Subnets[0].SubnetId')

# ── 1. Delete NAT + release EIP ─────────────────────────────────────────
if [[ -n "$NAT_ID" && "$NAT_ID" != "None" ]]; then
  echo "▶︎ Deleting NAT Gateway ($NAT_ID)"
  ALLOC_ID=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$NAT_ID" \
               --query 'NatGateways[0].NatGatewayAddresses[0].AllocationId' --output text)
  aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID"
  aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID"
  aws ec2 release-address --allocation-id "$ALLOC_ID"
fi

# ── 2. Detach & delete IGW ──────────────────────────────────────────────
if [[ -n "$IGW_ID" && "$IGW_ID" != "None" ]]; then
  aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" || true
  aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"
fi

# ── 3. Delete custom route tables ───────────────────────────────────────
for RT_ID in "$PUB_RT_ID" "$PRI_RT_ID"; do
  [[ -n "$RT_ID" && "$RT_ID" != "None" ]] && aws ec2 delete-route-table --route-table-id "$RT_ID"
done

# ── 4. Delete subnets ───────────────────────────────────────────────────
for SUB_ID in "$PUB_SUB_ID" "$PRI_SUB_ID"; do
  [[ -n "$SUB_ID" && "$SUB_ID" != "None" ]] && aws ec2 delete-subnet --subnet-id "$SUB_ID"
done

# ── 5. Delete the VPC ───────────────────────────────────────────────────
[[ -n "$VPC_ID" && "$VPC_ID" != "None" ]] && aws ec2 delete-vpc --vpc-id "$VPC_ID"

echo "✔︎ Environment destroyed – billing safe"
