# AWS Scripts 🚀

A collection of shell scripts to automate common AWS tasks such as creating and deleting VPCs and EC2 instances.

---

## 📂 Included Scripts
- **`cr-vpc-ec2.sh`** → Creates a VPC and an EC2 instance.
- **`rm-vpc-ec2.sh`** → Deletes the created VPC and EC2 instance.

---

## 🛠 Requirements
- AWS account with necessary IAM permissions.
- AWS CLI installed → [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
- A valid **Access Key** and **Secret Key**.
- Bash shell (Linux/MacOS or WSL for Windows).

---

## 🔑 How to Create AWS Access Key
1. Log in to the [AWS Management Console](https://console.aws.amazon.com/).
2. Navigate to **IAM (Identity & Access Management)**.
3. Go to **Users** → Select your IAM user.
4. Under **Security credentials** → click **Create access key**.
5. Copy the **Access Key ID** and **Secret Access Key** (keep them safe, don’t commit them to GitHub ❌).

---

## ⚙️ Configure AWS CLI
After you have your access key:

```bash
aws configure

aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
region = ap-south-1
output = json


⚡ Usage
1. Clone the repo
git clone https://github.com/Bilaalofficial/aws-script.git
cd aws-script

2. Make scripts executable
chmod +x cr-vpc-ec2.sh rm-vpc-ec2.sh

3. Run the scripts
./cr-vpc-ec2.sh   # Create resources
./rm-vpc-ec2.sh   # Delete resources






