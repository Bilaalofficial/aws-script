#!/bin/bash
set -e

# ---------- Configurable Variables ----------
REGION="ap-south-1"                     # Region: Mumbai
AZ="ap-south-1a"                        # Availability Zone
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"
KEY_NAME="my-key"
TAG="MyDefault"
INSTANCE_TYPE="t2.micro"                # Primary type
FALLBACK_TYPE="t3.micro"                # Fallback if t2.micro fails
# -------------------------------------------

echo "Fetching latest Ubuntu AMI..."
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*" "Name=state,Values=available" \
  --region $REGION \
  --query "Images | sort_by(@, &CreationDate)[-1].ImageId" \
  --output text)

echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --region $REGION \
  --query 'Vpc.VpcId' \
  --output text)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$TAG-VPC
echo "VPC Created: $VPC_ID"

echo "Creating Subnet in $AZ..."
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $SUBNET_CIDR \
  --availability-zone $AZ \
  --region $REGION \
  --query 'Subnet.SubnetId' \
  --output text)
aws ec2 create-tags --resources $SUBNET_ID --tags Key=Name,Value=$TAG-Subnet
echo "Subnet Created: $SUBNET_ID"

echo "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --region $REGION \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value=$TAG-IGW
echo "Internet Gateway Created: $IGW_ID"

echo "Creating Route Table..."
RTB_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'RouteTable.RouteTableId' \
  --output text)
aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SUBNET_ID
aws ec2 create-route --route-table-id $RTB_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 create-tags --resources $RTB_ID --tags Key=Name,Value=$TAG-RTB
echo "Route Table Created: $RTB_ID"

echo "Creating Security Group..."
SG_ID=$(aws ec2 create-security-group \
  --group-name $TAG-sg \
  --description "Allow SSH, HTTP, HTTPS" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
echo "Security Group Created: $SG_ID"

echo "Creating new Key Pair..."
aws ec2 create-key-pair \
  --key-name $KEY_NAME \
  --region $REGION \
  --query 'KeyMaterial' \
  --output text > $KEY_NAME.pem
chmod 400 $KEY_NAME.pem
echo "Key Pair Created & saved: $KEY_NAME.pem"

echo "Launching EC2 Instance in $AZ with $INSTANCE_TYPE..."
set +e
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --subnet-id $SUBNET_ID \
  --associate-public-ip-address \
  --region $REGION \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":8,"VolumeType":"gp2","DeleteOnTermination":true}}]' \
  --query 'Instances[0].InstanceId' \
  --output text 2>/tmp/ec2_error.log)
EC2_EXIT=$?
set -e

if [ $EC2_EXIT -ne 0 ] || [[ "$INSTANCE_ID" == "None" ]]; then
  echo "⚠️ Failed with $INSTANCE_TYPE. Retrying with $FALLBACK_TYPE..."
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type $FALLBACK_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SG_ID \
    --subnet-id $SUBNET_ID \
    --associate-public-ip-address \
    --region $REGION \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":8,"VolumeType":"gp2","DeleteOnTermination":true}}]' \
    --query 'Instances[0].InstanceId' \
    --output text)
fi

aws ec2 create-tags --resources $INSTANCE_ID --tags Key=Name,Value=$TAG-EC2
echo "EC2 Instance Launched: $INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region $REGION \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "---------------------------------------"
echo "VPC: $VPC_ID"
echo "Subnet: $SUBNET_ID"
echo "Internet Gateway: $IGW_ID"
echo "Route Table: $RTB_ID"
echo "Security Group: $SG_ID"
echo "Key Pair: $KEY_NAME.pem"
echo "EC2 Instance: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo "---------------------------------------"
