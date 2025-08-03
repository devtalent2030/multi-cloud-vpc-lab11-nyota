#!/usr/bin/env bash
# =======================================================================
# Title:  build_aws_net.sh
# Author:  <your-name>
# Purpose: Provision a two-tier VPC (public / private) with NAT egress
#          – designed for demos, labs, or green-field PoCs.
# Notes:   • Idempotent: re-runs skip resources that already exist
#          • All names are prefixed so multiple stacks can coexist
#          • No hard-coded IDs; tweak variables ↓ as needed
# =======================================================================

set -euo pipefail

# ── User-tunable variables ──────────────────────────────────────────────
PREFIX="nyota"            # ← change to your short unique label
AWS_REGION="us-east-1"    # us-east-1, ca-central-1, etc.
VPC_CIDR="10.0.0.0/16"
PUB_CIDR="10.0.1.0/24"
PRI_CIDR="10.0.2.0/24"
# ────────────────────────────────────────────────────────────────────────

# Derived names (do not edit)
VPC_NAME="${PREFIX}-vpc"
PUB_SUB="${PREFIX}-pub-subnet"
PRI_SUB="${PREFIX}-pri-subnet"
IGW_NAME="${PREFIX}-igw"
NAT_NAME="${PREFIX}-natgw"
PUB_RT="${PREFIX}-pub-rt"
PRI_RT="${PREFIX}-pri-rt"

echo "▶︎ Region set to $AWS_REGION"
aws configure set default.region "$AWS_REGION"

# ── 1. VPC ----------------------------------------------------------------
if ! aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" \
     --query 'Vpcs[0].VpcId' --output text 2>/dev/null | grep -q '^vpc-'; then
  echo "▶︎ Creating VPC $VPC_NAME ($VPC_CIDR)"
  VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" \
              --query 'Vpc.VpcId' --output text)
  aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="$VPC_NAME"
else
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" \
              --query 'Vpcs[0].VpcId' --output text)
  echo "ℹ︎ VPC already exists – $VPC_ID"
fi

# ── 2. Subnets ------------------------------------------------------------
create_subnet () {
  local NAME=$1 CIDR=$2 AZ=$3
  if ! aws ec2 describe-subnets --filters "Name=tag:Name,Values=$NAME" \
       --query 'Subnets[0].SubnetId' --output text 2>/dev/null | grep -q '^subnet-'; then
    echo "▶︎ Creating subnet $NAME ($CIDR, $AZ)"
    SUB_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$CIDR" \
                --availability-zone "$AZ" --query 'Subnet.SubnetId' --output text)
    aws ec2 create-tags --resources "$SUB_ID" --tags Key=Name,Value="$NAME"
    [[ "$NAME" == "$PUB_SUB" ]] && \
        aws ec2 modify-subnet-attribute --subnet-id "$SUB_ID" --map-public-ip-on-launch
  else
    echo "ℹ︎ Subnet $NAME already exists – skipping"
  fi
}

AZ_A="${AWS_REGION}a"
AZ_B="${AWS_REGION}b"
create_subnet "$PUB_SUB" "$PUB_CIDR" "$AZ_A"
create_subnet "$PRI_SUB" "$PRI_CIDR" "$AZ_B"

# ── 3. Internet Gateway ---------------------------------------------------
if ! aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=$IGW_NAME" \
     --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null | grep -q '^igw-'; then
  echo "▶︎ Creating and attaching IGW"
  IGW_ID=$(aws ec2 create-internet-gateway \
              --query 'InternetGateway.InternetGatewayId' --output text)
  aws ec2 create-tags --resources "$IGW_ID" --tags Key=Name,Value="$IGW_NAME"
  aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID"
else
  IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=$IGW_NAME" \
              --query 'InternetGateways[0].InternetGatewayId' --output text)
  echo "ℹ︎ IGW already exists – $IGW_ID"
fi

# ── 4. NAT Gateway --------------------------------------------------------
if ! aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=$NAT_NAME" \
     --query 'NatGateways[0].NatGatewayId' --output text 2>/dev/null | grep -q '^nat-'; then
  echo "▶︎ Allocating Elastic IP for NAT"
  ALLOC_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)

  PUB_SUB_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$PUB_SUB" \
                 --query 'Subnets[0].SubnetId' --output text)

  echo "▶︎ Creating NAT Gateway $NAT_NAME"
  NAT_ID=$(aws ec2 create-nat-gateway --subnet-id "$PUB_SUB_ID" \
              --allocation-id "$ALLOC_ID" \
              --query 'NatGateway.NatGatewayId' --output text)
  aws ec2 create-tags --resources "$NAT_ID" --tags Key=Name,Value="$NAT_NAME"

  echo "⏳ Waiting for NAT to become available..."
  aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID"
else
  NAT_ID=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=$NAT_NAME" \
              --query 'NatGateways[0].NatGatewayId' --output text)
  echo "ℹ︎ NAT Gateway already exists – $NAT_ID"
fi

# ── 5. Route tables -------------------------------------------------------
create_rt () {
  local RT_NAME=$1 DEST=$2 TARGET=$3 SUBNET=$4
  if ! aws ec2 describe-route-tables --filters "Name=tag:Name,Values=$RT_NAME" \
       --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null | grep -q '^rtb-'; then
    echo "▶︎ Creating route table $RT_NAME"
    RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
               --query 'RouteTable.RouteTableId' --output text)
    aws ec2 create-tags --resources "$RT_ID" --tags Key=Name,Value="$RT_NAME"
    aws ec2 create-route --route-table-id "$RT_ID" --destination-cidr-block "$DEST" --"$TARGET"
    SUB_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$SUBNET" \
                 --query 'Subnets[0].SubnetId' --output text)
    aws ec2 associate-route-table --route-table-id "$RT_ID" --subnet-id "$SUB_ID"
  else
    echo "ℹ︎ Route table $RT_NAME already exists – skipping"
  fi
}

create_rt "$PUB_RT" "0.0.0.0/0" "gateway-id $IGW_ID" "$PUB_SUB"
create_rt "$PRI_RT" "0.0.0.0/0" "nat-gateway-id $NAT_ID" "$PRI_SUB"

echo "✔︎ Build complete – VPC ID is $VPC_ID"
