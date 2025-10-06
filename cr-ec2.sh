#!/bin/bash
set -exuo pipefail

# ---------- Configurable Variables ----------
REGION="ap-south-1"                     # Mumbai
AZ_LIST=("ap-south-1a" "ap-south-1b" "ap-south-1c")
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR_PREFIX="10.0"               # We'll append .1.0/24, .2.0/24...
KEY_NAME="my-key"
TAG="MyDefault"
INSTANCE_TYPE="t2.micro"
FALLBACK_TYPE="t3.micro"
EC2_COUNT=1                            # Number of EC2 instances to launch
# -------------------------------------------

echo "Fetching latest Ubuntu AMI..."
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*" "Name=state,Values=available" \
  --region "$REGION" \
  --query "Images | sort_by(@, &CreationDate)[-1].ImageId" \
  --output text)
echo "Latest Ubuntu AMI: $AMI_ID"

echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block "$VPC_CIDR" \
  --region "$REGION" \
  --query 'Vpc.VpcId' \
  --output text)
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="$TAG-VPC"
echo "VPC Created: $VPC_ID"

echo "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --region "$REGION" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID"
aws ec2 create-tags --resources "$IGW_ID" --tags Key=Name,Value="$TAG-IGW"
echo "Internet Gateway Created: $IGW_ID"

echo "Creating Route Table..."
RTB_ID=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --region "$REGION" \
  --query 'RouteTable.RouteTableId' \
  --output text)
aws ec2 create-route --route-table-id "$RTB_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" || true
aws ec2 create-tags --resources "$RTB_ID" --tags Key=Name,Value="$TAG-RTB"
echo "Route Table Created: $RTB_ID"

echo "Creating Security Group..."
SG_ID=$(aws ec2 create-security-group \
  --group-name "$TAG-sg" \
  --description "Allow SSH, HTTP, HTTPS" \
  --vpc-id "$VPC_ID" \
  --region "$REGION" \
  --query 'GroupId' \
  --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 || true
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 || true
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0 || true
aws ec2 create-tags --resources "$SG_ID" --tags Key=Name,Value="$TAG-SG"
echo "Security Group Created: $SG_ID"

# Safe Key Pair creation
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" >/dev/null 2>&1; then
  aws ec2 create-key-pair \
    --key-name "$KEY_NAME" \
    --region "$REGION" \
    --query 'KeyMaterial' \
    --output text > "$KEY_NAME.pem"
  chmod 400 "$KEY_NAME.pem"
  echo "Key Pair Created & saved: $KEY_NAME.pem"
else
  echo "Key Pair $KEY_NAME already exists. Skipping creation."
fi

# Helper function: create subnet in given AZ
create_subnet_in_az() {
  local az="$1"
  local idx="$2"
  local cidr="${SUBNET_CIDR_PREFIX}.${idx}.0/24"
  SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$cidr" \
    --availability-zone "$az" \
    --region "$REGION" \
    --query 'Subnet.SubnetId' \
    --output text)
  aws ec2 create-tags --resources "$SUBNET_ID" --tags Key=Name,Value="$TAG-Subnet-$az"
  aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET_ID" >/dev/null || true
  echo "$SUBNET_ID"
}

# Create subnets per AZ
declare -A SUBNET_BY_AZ
count=1
for az_try in "${AZ_LIST[@]}"; do
  SUBNET_ID=$(create_subnet_in_az "$az_try" "$count")
  SUBNET_BY_AZ["$az_try"]="$SUBNET_ID"
  count=$((count+1))
done

# Launch instances with retries/fallbacks
INSTANCE_IDS=()
PUBLIC_IPS=()

try_launch_instance() {
  local subnet_id="$1"
  local inst_type="$2"

  echo "Launching instance type=$inst_type in subnet=$subnet_id ..."
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$inst_type" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --subnet-id "$subnet_id" \
    --associate-public-ip-address \
    --region "$REGION" \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":8,"VolumeType":"gp2","DeleteOnTermination":true}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${TAG}-EC2}]" \
    --query "Instances[0].InstanceId" --output text) || return 1

  echo "Instance launched: $INSTANCE_ID. Waiting for 'running'..."
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
  PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)
  echo "Instance $INSTANCE_ID running with Public IP: $PUBLIC_IP"

  INSTANCE_IDS+=("$INSTANCE_ID")
  PUBLIC_IPS+=("$PUBLIC_IP")
  return 0
}

launched=false
for az_try in "${AZ_LIST[@]}"; do
  subnet="${SUBNET_BY_AZ[$az_try]}"

  if try_launch_instance "$subnet" "$INSTANCE_TYPE"; then
    launched=true
    break
  fi

  echo "Primary $INSTANCE_TYPE failed in AZ $az_try. Trying fallback $FALLBACK_TYPE..."
  if try_launch_instance "$subnet" "$FALLBACK_TYPE"; then
    launched=true
    break
  fi

  echo "Fallback $FALLBACK_TYPE also failed in AZ $az_try. Moving to next AZ..."
done

if [ "$launched" = false ]; then
  echo "All attempts failed in all AZs and instance types. Exiting."
  exit 1
fi

# -------------------- Output --------------------
echo "---------------------------------------"
echo "VPC: $VPC_ID"
for az_try in "${!SUBNET_BY_AZ[@]}"; do
  echo "Subnet ($az_try): ${SUBNET_BY_AZ[$az_try]}"
done
echo "Internet Gateway: $IGW_ID"
echo "Route Table: $RTB_ID"
echo "Security Group: $SG_ID"
echo "Key Pair: $KEY_NAME.pem"

for i in "${!INSTANCE_IDS[@]}"; do
  idx=$((i+1))
  echo "EC2 Instance $idx: ${INSTANCE_IDS[$i]} (IP: ${PUBLIC_IPS[$i]})"
done
echo "---------------------------------------"
