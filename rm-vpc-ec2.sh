#!/bin/bash
set -e

# ---------- Configurable Variables ----------
REGION="ap-south-1"   # Same region as create script
TAG="MyDefault"       # Same tag prefix
KEY_NAME="my-key"     # Same key name
# -------------------------------------------

echo "Fetching resources with tag prefix: $TAG"

# Find resources
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$TAG-EC2" "Name=instance-state-name,Values=running,stopped" \
  --region $REGION \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text)

SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$TAG-sg" \
  --region $REGION \
  --query "SecurityGroups[0].GroupId" \
  --output text)

RTB_ID=$(aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=$TAG-RTB" \
  --region $REGION \
  --query "RouteTables[0].RouteTableId" \
  --output text)

IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=tag:Name,Values=$TAG-IGW" \
  --region $REGION \
  --query "InternetGateways[0].InternetGatewayId" \
  --output text)

SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=$TAG-Subnet" \
  --region $REGION \
  --query "Subnets[].SubnetId" \
  --output text)

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=$TAG-VPC" \
  --region $REGION \
  --query "Vpcs[0].VpcId" \
  --output text)

# Cleanup process
if [ -n "$INSTANCE_ID" ]; then
  echo "Terminating EC2 instance: $INSTANCE_ID"
  aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID --region $REGION
fi

if [ -n "$SG_ID" ]; then
  echo "Deleting Security Group: $SG_ID"
  aws ec2 delete-security-group --group-id $SG_ID --region $REGION || true
fi

if [ -n "$RTB_ID" ]; then
  echo "Disassociating Route Table associations..."
  ASSOC_IDS=$(aws ec2 describe-route-tables \
    --route-table-ids $RTB_ID \
    --region $REGION \
    --query "RouteTables[0].Associations[].RouteTableAssociationId" \
    --output text)

  for ASSOC_ID in $ASSOC_IDS; do
    if [ "$ASSOC_ID" != "None" ]; then
      aws ec2 disassociate-route-table --association-id $ASSOC_ID --region $REGION || true
    fi
  done

  echo "Deleting Route Table: $RTB_ID"
  aws ec2 delete-route-table --route-table-id $RTB_ID --region $REGION || true
fi

if [ -n "$IGW_ID" ] && [ -n "$VPC_ID" ]; then
  echo "Detaching and Deleting Internet Gateway: $IGW_ID"
  aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $REGION || true
  aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $REGION || true
fi

if [ -n "$SUBNET_IDS" ]; then
  for SUBNET_ID in $SUBNET_IDS; do
    echo "Deleting Subnet: $SUBNET_ID"
    aws ec2 delete-subnet --subnet-id $SUBNET_ID --region $REGION || true
  done
fi

if [ -n "$VPC_ID" ]; then
  echo "Deleting VPC: $VPC_ID"
  aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION || true
fi

echo "Deleting Key Pair: $KEY_NAME"
aws ec2 delete-key-pair --key-name $KEY_NAME --region $REGION || true
rm -f $KEY_NAME.pem

echo "---------------------------------------"
echo "Cleanup completed. All resources removed."
echo "---------------------------------------"
