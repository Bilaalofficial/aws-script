#!/bin/bash
set -e

# ---------- Configurable Variables ----------
REGION="ap-south-1"     # Same region used in create script
KEY_NAME="my-key"       # Same key name used before
TAG="MyDefault"         # Same tag prefix used in create script
DRY_RUN=false           # 🔥 Set to true for testing (no actual deletion)
# -------------------------------------------

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo "[Dry Run] $*"
  else
    eval "$@"
  fi
}

echo "Fetching resources with tag prefix: $TAG ..."

# Get EC2 Instances
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$TAG-EC2-*" "Name=instance-state-name,Values=running,stopped" \
  --region $REGION \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

# Get Security Group
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$TAG-sg" \
  --region $REGION \
  --query "SecurityGroups[0].GroupId" \
  --output text)

# Get Route Table + Associations
RTB_ID=$(aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=$TAG-RTB" \
  --region $REGION \
  --query "RouteTables[0].RouteTableId" \
  --output text)

RTB_ASSOCIATIONS=$(aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=$TAG-RTB" \
  --region $REGION \
  --query "RouteTables[0].Associations[].RouteTableAssociationId" \
  --output text)

# Get Internet Gateway
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=tag:Name,Values=$TAG-IGW" \
  --region $REGION \
  --query "InternetGateways[0].InternetGatewayId" \
  --output text)

# Get Subnet
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=$TAG-Subnet" \
  --region $REGION \
  --query "Subnets[0].SubnetId" \
  --output text)

# Get VPC
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=$TAG-VPC" \
  --region $REGION \
  --query "Vpcs[0].VpcId" \
  --output text)

# -------------------- Deletion Steps --------------------

# Terminate EC2 Instances
if [ -n "$INSTANCE_IDS" ]; then
  echo "Terminating EC2 Instances: $INSTANCE_IDS ..."
  run_cmd "aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region $REGION"
  if [ "$DRY_RUN" = false ]; then
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --region $REGION
  fi
  echo "EC2 Instances terminated."
else
  echo "No EC2 instances found."
fi

# Delete Security Group
if [ "$SG_ID" != "None" ]; then
  echo "Deleting Security Group: $SG_ID ..."
  sleep 5 # give AWS time to detach
  run_cmd "aws ec2 delete-security-group --group-id $SG_ID --region $REGION || true"
  echo "Security Group deleted."
fi

# Disassociate & Delete Route Table
if [ "$RTB_ID" != "None" ]; then
  if [ -n "$RTB_ASSOCIATIONS" ]; then
    for assoc in $RTB_ASSOCIATIONS; do
      echo "Disassociating Route Table Association: $assoc ..."
      run_cmd "aws ec2 disassociate-route-table --association-id $assoc --region $REGION || true"
    done
  fi
  echo "Deleting Route Table: $RTB_ID ..."
  run_cmd "aws ec2 delete-route-table --route-table-id $RTB_ID --region $REGION || true"
  echo "Route Table deleted."
fi

# Detach & Delete Internet Gateway
if [ "$IGW_ID" != "None" ]; then
  echo "Detaching and Deleting Internet Gateway: $IGW_ID ..."
  run_cmd "aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $REGION || true"
  run_cmd "aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $REGION || true"
  echo "Internet Gateway deleted."
fi

# Delete Subnet
if [ "$SUBNET_ID" != "None" ]; then
  echo "Deleting Subnet: $SUBNET_ID ..."
  run_cmd "aws ec2 delete-subnet --subnet-id $SUBNET_ID --region $REGION || true"
  echo "Subnet deleted."
fi

# Delete VPC
if [ "$VPC_ID" != "None" ]; then
  echo "Deleting VPC: $VPC_ID ..."
  run_cmd "aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION || true"
  echo "VPC deleted."
fi

# Delete Key Pair
echo "⚠️ Deleting Key Pair: $KEY_NAME (make sure it's not shared)..."
run_cmd "aws ec2 delete-key-pair --key-name $KEY_NAME --region $REGION || true"
run_cmd "rm -f $KEY_NAME.pem"
echo "Key Pair deleted."

echo "---------------------------------------"
echo "✅ Cleanup Complete: All resources with tag $TAG removed."
echo "---------------------------------------"
