#!/bin/bash
set -euo pipefail

# ---------- Configurable Variables ----------
REGION="ap-south-1"
KEY_NAME="my-key"
TAG="MyDefault"
DRY_RUN=false   # Set true to simulate deletion
# -------------------------------------------

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo "[Dry Run] $*"
  else
    eval "$@"
  fi
}

echo "---------------------------------------"
echo "Starting cleanup for resources with tag: $TAG"
echo "Region: $REGION"
echo "---------------------------------------"

# Fetch VPC
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=$TAG-VPC" \
  --region $REGION \
  --query "Vpcs[0].VpcId" \
  --output text || echo "")

if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
  echo "No VPC found with tag $TAG. Nothing to delete."
else
  echo "VPC found: $VPC_ID"

  # Terminate EC2 Instances
  INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,stopped" \
    --region $REGION \
    --query "Reservations[].Instances[].InstanceId" \
    --output text || echo "")
  if [ -n "$INSTANCE_IDS" ]; then
    echo "Terminating EC2 Instances: $INSTANCE_IDS"
    run_cmd "aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region $REGION"
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --region $REGION
    echo "EC2 Instances terminated."
  else
    echo "No EC2 instances found."
  fi

  # Delete Security Groups
  SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$TAG-sg" \
    --region $REGION \
    --query "SecurityGroups[0].GroupId" \
    --output text || echo "")
  if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    echo "Deleting Security Group: $SG_ID"
    run_cmd "aws ec2 delete-security-group --group-id $SG_ID --region $REGION || true"
    echo "Security Group deleted."
  else
    echo "No Security Group found."
  fi

  # Delete Subnets
  SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --query "Subnets[].SubnetId" \
    --output text || echo "")
  if [ -n "$SUBNETS" ]; then
    for subnet in $SUBNETS; do
      echo "Deleting Subnet: $subnet"
      run_cmd "aws ec2 delete-subnet --subnet-id $subnet --region $REGION || true"
    done
  else
    echo "No Subnets found."
  fi

  # Delete Internet Gateways
  IGWS=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --query "InternetGateways[].InternetGatewayId" \
    --output text || echo "")
  if [ -n "$IGWS" ]; then
    for igw in $IGWS; do
      echo "Detaching and deleting Internet Gateway: $igw"
      run_cmd "aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID --region $REGION || true"
      run_cmd "aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $REGION || true"
    done
  else
    echo "No Internet Gateways found."
  fi

  # Delete Route Tables (except main)
  RTBS=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --query "RouteTables[].RouteTableId" \
    --output text || echo "")
  if [ -n "$RTBS" ]; then
    for rtb in $RTBS; do
      MAIN=$(aws ec2 describe-route-tables --route-table-ids $rtb --region $REGION \
        --query "RouteTables[0].Associations[?Main==true]" --output text)
      if [ -z "$MAIN" ]; then
        echo "Deleting Route Table: $rtb"
        run_cmd "aws ec2 delete-route-table --route-table-id $rtb --region $REGION || true"
      fi
    done
  else
    echo "No Route Tables found."
  fi

  # Delete VPC
  echo "Deleting VPC: $VPC_ID"
  run_cmd "aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION || true"
  echo "VPC deleted."
fi

# Delete Key Pair
echo "Deleting Key Pair: $KEY_NAME"
run_cmd "aws ec2 delete-key-pair --key-name $KEY_NAME --region $REGION || true"
run_cmd "rm -f $KEY_NAME.pem"
echo "Key Pair deleted."

echo "---------------------------------------"
echo "✅ Cleanup Complete for tag $TAG"
echo "---------------------------------------"
