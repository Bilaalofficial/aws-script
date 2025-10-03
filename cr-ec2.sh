#!/bin/bash
set -euo pipefail

# ---------- Configurable Variables ----------
REGION="ap-south-1"                     # Region: Mumbai
AZ="ap-south-1a"                        # Preferred Availability Zone (will be tried first)
# List of AZs to try (keeps same region)
AZ_LIST=("ap-south-1a" "ap-south-1b" "ap-south-1c")
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR_PREFIX="10.0"               # we'll append .1.0/24 / .2.0/24 ... for other AZs
KEY_NAME="my-key"
TAG="MyDefault"
INSTANCE_TYPE="t2.micro"                # Free Tier eligible (preferred)
FALLBACK_TYPE="t3.micro"                # Free Tier alternative if capacity not available
EC2_COUNT=1                             # number of instances
# -------------------------------------------

echo "Fetching latest Ubuntu AMI..."
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*" "Name=state,Values=available" \
  --region "$REGION" \
  --query "Images | sort_by(@, &CreationDate)[-1].ImageId" \
  --output text)

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

echo "Creating new Key Pair (or overwriting local file)..."
aws ec2 create-key-pair \
  --key-name "$KEY_NAME" \
  --region "$REGION" \
  --query 'KeyMaterial' \
  --output text > "$KEY_NAME.pem"
chmod 400 "$KEY_NAME.pem"
echo "Key Pair Created & saved: $KEY_NAME.pem"

# Helper: create (or reuse) a subnet in a given AZ
create_subnet_in_az() {
  local az="$1"
  local idx="$2"
  local cidr="${SUBNET_CIDR_PREFIX}.${idx}.0/24"
  echo "Creating Subnet in $az (CIDR: $cidr)..."
  SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$cidr" \
    --availability-zone "$az" \
    --region "$REGION" \
    --query 'Subnet.SubnetId' \
    --output text)
  aws ec2 create-tags --resources "$SUBNET_ID" --tags Key=Name,Value="$TAG-Subnet-$az"
  echo "Subnet Created: $SUBNET_ID ($az)"
  # associate route table
  aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET_ID" >/dev/null || true
  echo "$SUBNET_ID"
}

# Create subnets for each AZ we might try (so we have subnet per AZ)
declare -A SUBNET_BY_AZ
count=1
for az_try in "${AZ_LIST[@]}"; do
  # If user provided AZ variable and it matches az_try, ensure this created subnet uses SUBNET_CIDR_PREFIX.1.0/24
  SUBNET_ID=$(create_subnet_in_az "$az_try" "$count")
  SUBNET_BY_AZ["$az_try"]="$SUBNET_ID"
  count=$((count + 1))
done

# -------------------- EC2 LAUNCH with retries/fallbacks --------------------
INSTANCE_IDS=()
PUBLIC_IPS=()

try_launch_instance() {
  local subnet_id="$1"
  local inst_type="$2"

  echo "Attempting to launch instance type=$inst_type in subnet=$subnet_id ..."
  # run-instances can fail; capture output+exit code
  local out
  out=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$inst_type" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --subnet-id "$subnet_id" \
    --associate-public-ip-address \
    --region "$REGION" \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":8,"VolumeType":"gp2","DeleteOnTermination":true}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${TAG}-EC2}]" 2>&1) || true

  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "Run-instances failed (rc=$rc). Raw error:"
    echo "$out"
    # Return failure status to caller (non-zero)
    return 2
  fi

  # parse InstanceId from output
  local instance_id
  instance_id=$(echo "$out" | awk -F'"' '/InstanceId/{print $4; exit}') || instance_id=""

  if [ -z "$instance_id" ]; then
    echo "Could not parse InstanceId from output; output was:"
    echo "$out"
    return 3
  fi

  echo "Launched Instance: $instance_id - waiting to become 'running'..."
  aws ec2 wait instance-running --instance-ids "$instance_id" --region "$REGION"
  # Get Public IP
  local public_ip
  public_ip=$(aws ec2 describe-instances \
    --instance-ids "$instance_id" \
    --region "$REGION" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)
  echo "Instance $instance_id is running (IP: $public_ip)"
  INSTANCE_IDS+=("$instance_id")
  PUBLIC_IPS+=("$public_ip")
  return 0
}

# Launch loop: try preferred AZ first, then fallbacks
launched_ok=false
for az_try in "${AZ_LIST[@]}"; do
  subnet_to_use="${SUBNET_BY_AZ[$az_try]}"
  # try primary instance type first
  if try_launch_instance "$subnet_to_use" "$INSTANCE_TYPE"; then
    launched_ok=true
    break
  fi

  echo "Primary instance type $INSTANCE_TYPE failed in AZ $az_try. Trying fallback type $FALLBACK_TYPE in same AZ..."
  if try_launch_instance "$subnet_to_use" "$FALLBACK_TYPE"; then
    launched_ok=true
    break
  fi

  echo "Fallback type $FALLBACK_TYPE also failed in AZ $az_try. Moving to next AZ..."
done

if [ "$launched_ok" = false ]; then
  echo "All attempts to launch instances failed (all AZs and both instance types tried). Exiting with error."
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
