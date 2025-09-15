# AWS Scripts 🚀

A collection of shell scripts to automate common AWS tasks such as creating and deleting VPCs and EC2 instances.

---

## 📂 Included Scripts
- **`cr-vpc-ec2.sh`** → Creates a VPC and an EC2 instance.
- **`rm-vpc-ec2.sh`** → Deletes the created VPC and EC2 instance.

---

## ⚡ Usage

### 1. Clone the repo
```bash
git clone https://github.com/Bilaalofficial/aws-script.git
cd aws-script


2. Make scripts executable
chmod +x cr-vpc-ec2.sh rm-vpc-ec2.sh


3. Run the scripts
./cr-vpc-ec2.sh   # Create resources
./rm-vpc-ec2.sh   # Delete resources

🔑 Requirements
AWS CLI installed (aws --version)
Valid AWS credentials

🔧 How to Configure AWS

Before running the scripts, configure your AWS credentials:

Step 1: Install AWS CLI

Ubuntu/Debian

sudo apt update
sudo apt install awscli -y


Step 2: Configure Credentials

Run:

aws configure


Enter your details:

AWS Access Key ID [None]: <Your Access Key>
AWS Secret Access Key [None]: <Your Secret Key>
Default region name [None]: ap-south-1
Default output format [None]: json
