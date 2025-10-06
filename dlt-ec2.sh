```bash
#!/bin/bash
set -euo pipefail

# ---------- Configurable Variables ----------
REGION="ap-south-1"     # Same region used in create script
KEY_NAME="my-key"       # Same key name used before
TAG="MyDefault"         # Same tag prefix used in create script
DRY_RUN=false           # Set to true for testing (no actual deletion)
# -------------------------------------------

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo "[Dry Run] $*"
  else
    eval "$@"
  fi
}

echo "Fetching resources with tag prefix: $TAG ..."

# Get VPC
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=$TAG-VPC" \
  --region $REGION \
  --query "Vpcs[0].VpcId" \
  --output text)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
  echo "No VPC found with tag $TAG. Exiting."
  exit 0
fi

# -------------------- Deletion Steps --------------------

# 1. Terminate EC2 Instances
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,stopped" \
  --region $REGION \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

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

# 2. Delete ENIs (Network Interfaces)
ENIS=$(aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --region $REGION \
  --query "NetworkInterfaces[].NetworkInterfaceId" \
  --output text)

if [ -n "$ENIS" ]; then
  for eni in $ENIS; do
    echo "Deleting ENI: $eni ..."
    run_cmd "aws ec2 delete-network-interface --network-interface-id $eni --region $REGION || true"
  done
fi

# 3. Delete Subnets
SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --region $REGION \
  --query "Subnets[].SubnetId" \
  --output text)

if [ -n "$SUBNETS" ]; then
  for subnet in $SUBNETS; do
    echo "Deleting Subnet: $subnet ..."
    run_cmd "aws ec2 delete-subnet --subnet-id $subnet --region $REGION || true"
  done
fi

# 4. Detach & Delete Internet Gateways
IGWS=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --region $REGION \
  --query "InternetGateways[].InternetGatewayId" \
  --output text)

if [ -n "$IGWS" ]; then
  for igw in $IGWS; do
    echo "Detaching and Deleting Internet Gateway: $igw ..."
    run_cmd "aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID --region $REGION || true"
    run_cmd "aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $REGION || true"
  done
fi

# 5. Delete Route Tables (except main)
RTBS=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --region $REGION \
  --query "RouteTables[].RouteTableId" \
  --output text)

if [ -n "$RTBS" ]; then
  for rtb in $RTBS; do
    MAIN=$(aws ec2 describe-route-tables --route-table-ids $rtb --region $REGION \
      --query "RouteTables[0].Associations[?Main==true]" --output text)
    if [ -z "$MAIN" ]; then
      echo "Deleting Route Table: $rtb ..."
      run_cmd "aws ec2 delete-route-table --route-table-id $rtb --region $REGION || true"
    fi
  done
fi

# 6. Delete Security Groups (except default)
SGS=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --region $REGION \
  --query "SecurityGroups[].GroupId" \
  --output text)

if [ -n "$SGS" ]; then
  for sg in $SGS; do
    NAME=$(aws ec2 describe-security-groups --group-ids $sg --region $REGION \
      --query "SecurityGroups[0].GroupName" --output text)
    if [ "$NAME" != "default" ]; then
      echo "Deleting Security Group: $sg ..."
      run_cmd "aws ec2 delete-security-group --group-id $sg --region $REGION || true"
    fi
  done
fi

# 7. Delete VPC
echo "Deleting VPC: $VPC_ID ..."
run_cmd "aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION || true"
echo "VPC deleted."

# 8. Delete Key Pair
echo "⚠️ Deleting Key Pair: $KEY_NAME (make sure it's not shared)..."
run_cmd "aws ec2 delete-key-pair --key-name $KEY_NAME --region $REGION || true"
run_cmd "rm -f $KEY_NAME.pem"
echo "Key Pair deleted."

echo "---------------------------------------"
echo "✅ Cleanup Complete: All resources with tag $TAG removed."
echo "---------------------------------------"
```
