Perfect 👍 I’ve updated your README to use the new script names:

---

# AWS Scripts 🚀

A collection of shell scripts to automate common AWS tasks such as creating and deleting VPCs and EC2 instances.

---

## 📂 Included Scripts

* **`cr-ec2.sh`** → Creates a VPC, Subnet, Security Group, Internet Gateway, Route Table, Key Pair, and EC2 instance(s).
* **`dlt-ec2.sh`** → Deletes the created VPC, Subnet, Security Group, Internet Gateway, Route Table, EC2 instance(s), and Key Pair.

---

## 🛠 Requirements

* AWS account with necessary IAM permissions.
* AWS CLI installed → [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
* A valid **Access Key** and **Secret Key**.
* Bash shell (Linux/MacOS or WSL for Windows).

---

## 🔑 How to Create AWS Access Key

1. Log in to the [AWS Management Console](https://console.aws.amazon.com/).
2. Navigate to **IAM (Identity & Access Management)**.
3. Go to **Users** → Select your IAM user.
4. Under **Security credentials** → click **Create access key**.
5. Copy the **Access Key ID** and **Secret Access Key** (keep them safe, **don’t commit them to GitHub ❌**).

---

## ⚙️ Configure AWS CLI

After obtaining your access key, configure AWS CLI:

```bash
aws configure
```

Enter:

```
AWS Access Key ID [None]: YOUR_ACCESS_KEY
AWS Secret Access Key [None]: YOUR_SECRET_KEY
Default region name [None]: ap-south-1
Default output format [None]: json
```

---

## ⚡ Usage

1. **Clone the repo**

```bash
git clone https://github.com/Bilaalofficial/aws-script.git
cd aws-script
```

2. **Make scripts executable**

```bash
chmod +x cr-ec2.sh dlt-ec2.sh
```

3. **Run the scripts**

```bash
./cr-ec2.sh      # Create resources
./dlt-ec2.sh     # Delete resources
```

4. **Optional: Dry-Run Mode for Cleanup**

```bash
DRY_RUN=true ./dlt-ec2.sh
```

* Shows what would be deleted **without actually removing resources**.
* Recommended for safety before running the real cleanup.

---

## ⚠️ Notes

* **Free Tier Friendly:** By default, the scripts launch 1 `t2.micro` EC2 instance.
* **Resource Safety:** Scripts only affect resources with the configured `TAG`.
* **Check AWS Console:** Always verify resources before running `dlt-ec2.sh`.

---

