# 🚀 Complete VM Setup & Deployment Guide
## Banking Platform – From Zero to Production

> **Written from the perspective of a Senior DevOps Engineer (10+ years)**  
> This guide covers everything you need to run this project on a freshly created VM — no assumptions, no skipped steps.

---

## 📌 Read This First

This project has **three deployment modes**. You need to decide which one you want before starting:

| Mode | What You Get | Time to Setup | Cost |
|------|-------------|---------------|------|
| **Mode 1: Local Docker** | App + MySQL + NGINX running locally | ~30 min | Free |
| **Mode 2: Full AWS Production** | EKS + RDS + ALB + All K8s tools | ~3–4 hours | AWS charges apply |
| **Mode 3: Jenkins CI/CD Only** | Jenkins pipeline for building/scanning | ~1 hour | VM cost only |

**Start with Mode 1 to verify the app works. Then move to Mode 2 for full production.**

---

## 🖥️ VM Recommendation

```
OS:       Ubuntu 22.04 LTS (recommended)
CPU:      4 cores minimum (8 recommended for Mode 2)
RAM:      8 GB minimum (16 GB recommended for Mode 2)
Disk:     50 GB minimum
Network:  Outbound internet access required
```

---

---

# ✅ MODE 1 — Local Docker (Run App Locally)

> **Goal:** Get the Spring Boot app + MySQL + NGINX running on the VM in 30 minutes.

---

## Step 1 — System Update

```bash
sudo apt update && sudo apt upgrade -y
```

---

## Step 2 — Install Git

```bash
sudo apt install -y git
git --version
```

---

## Step 3 — Install Docker

```bash
# Install dependencies
sudo apt install -y ca-certificates curl gnupg lsb-release

# Add Docker GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repo
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add your user to docker group (so you don't need sudo every time)
sudo usermod -aG docker $USER

# Apply group change (or logout and log back in)
newgrp docker

# Verify
docker --version
docker compose version
```

---

## Step 4 — Clone the Repository

```bash
git clone https://github.com/rohan/Springboot-BankApp.git
cd Springboot-BankApp
```

---

## Step 5 — Configure Environment Variables

The `.env` file already exists in the repo with default values. Review it:

```bash
cat .env
```

Expected output:
```
MYSQL_ROOT_PASSWORD=Test@123
MYSQL_DATABASE=bankappdb
```

> ⚠️ **For production, change this password.** For local testing, defaults are fine.

---

## Step 6 — Review the NGINX Config

```bash
cat nginx.conf
```

The `server_name` is set to `bank.joakim.online`. For local testing, **this doesn't matter** because you're hitting port 80 directly. If you want a custom domain, update line:
```nginx
server_name bank.joakim.online;
# Change to:
server_name localhost;
```

---

## Step 7 — Build and Start Everything

```bash
# This command builds the Docker image, starts MySQL, the app, and NGINX
docker compose up --build -d

# Watch the logs to confirm everything starts cleanly
docker compose logs -f
```

**What happens behind the scenes:**
1. Docker builds a 3-stage image (OTel agent download → Maven build → JRE runtime)
2. MySQL starts first (healthcheck gated)
3. Spring Boot app waits for MySQL to be healthy, then starts
4. NGINX starts and proxies port 80 → app port 8080

---

## Step 8 — Verify Everything is Running

```bash
# Check all containers are Up
docker compose ps

# Expected output:
# mysql     running (healthy)
# bankapp   running (healthy)
# nginx     running
```

```bash
# Test the health endpoint directly
curl http://localhost/actuator/health

# Expected output:
# {"status":"UP"}
```

```bash
# Test the app is reachable
curl -I http://localhost/login
# Expected: HTTP/1.1 200 OK
```

---

## Step 9 — Access the Application

Open your browser and go to:
```
http://<YOUR_VM_IP>
```

You should see the **Goldencat Bank login page**.

- Click **Register here** to create an account
- Login and test deposit, withdraw, transfer

---

## ✅ Mode 1 Checklist

```
[ ] Docker installed and running
[ ] docker compose up --build -d runs without errors
[ ] docker compose ps shows all 3 containers healthy
[ ] curl http://localhost/actuator/health returns {"status":"UP"}
[ ] Browser can access http://<VM_IP>
[ ] Can register, login, deposit, withdraw
```

---

## 🛑 Common Failures in Mode 1

| Error | Cause | Fix |
|-------|-------|-----|
| `Permission denied` on docker | User not in docker group | `newgrp docker` or re-login |
| `Port 80 already in use` | Something else using port 80 | `sudo lsof -i :80` then kill it |
| App crashes on startup | MySQL not ready yet | Wait 30s, check `docker compose logs mysql` |
| `OTel agent download fails` | No internet from VM | Check outbound access, retry |
| `ImagePullBackOff` or build failure | Docker build error | `docker compose logs mainapp` |

---

---

# ✅ MODE 2 — Full AWS Production (EKS + All K8s Tools)

> **Goal:** Deploy the entire platform on AWS EKS with all monitoring, GitOps, and security tools.

---

## Phase 0 — AWS Account Prerequisites

Before touching the VM, you need these ready in AWS:

```
1. AWS Account with admin IAM user OR IAM role with these permissions:
   - IAMFullAccess
   - AmazonEKSFullAccess
   - AmazonEC2FullAccess
   - AmazonRDSFullAccess
   - AmazonS3FullAccess
   - AmazonRoute53FullAccess
   - AmazonVPCFullAccess
   - AWSCertificateManagerFullAccess
   - CloudWatchFullAccess
   - AmazonDynamoDBFullAccess

2. A domain name you own (e.g., rohandevops.co.in)
   - Hosted Zone must exist in Route53
   - OR will be created by the global Terraform module

3. AWS CLI credentials ready:
   - Access Key ID
   - Secret Access Key
   - Region: us-east-1 (or your preferred region)
```

---

## Phase 1 — Install All Required Tools on VM

Run the following commands **in order**. Do not skip any.

### 1.1 — System Update & Base Packages

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  git curl wget unzip jq \
  ca-certificates gnupg lsb-release \
  apt-transport-https software-properties-common
```

### 1.2 — Install Docker

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker
docker --version    # Should print: Docker version 24.x.x
```

### 1.3 — Install AWS CLI v2

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws/

# Verify
aws --version    # Should print: aws-cli/2.x.x
```

### 1.4 — Configure AWS CLI

```bash
aws configure
# Enter when prompted:
# AWS Access Key ID:     <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region:        us-east-1
# Default output format: json

# Verify you can talk to AWS
aws sts get-caller-identity
# Should print your Account ID, UserID, ARN
```

### 1.5 — Install Terraform 1.9.0

```bash
wget https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip
unzip terraform_1.9.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
rm terraform_1.9.0_linux_amd64.zip

# Verify
terraform --version    # Should print: Terraform v1.9.0
```

### 1.6 — Install kubectl

```bash
curl -LO "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Verify
kubectl version --client    # Should print: Client Version: v1.31.0
```

### 1.7 — Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version    # Should print: version.BuildInfo{Version:"v3.x.x"}
```

### 1.8 — Install eksctl

```bash
curl --silent --location \
  "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" \
  | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Verify
eksctl version    # Should print: 0.x.x
```

### 1.9 — Install ArgoCD CLI

```bash
curl -sSL -o argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd /usr/local/bin/argocd
rm argocd

# Verify
argocd version --client
```

### 1.10 — Install Argo Rollouts Plugin

```bash
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x ./kubectl-argo-rollouts-linux-amd64
sudo mv ./kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts

# Verify
kubectl argo rollouts version
```

### 1.11 — Verify All Tools Are Installed

```bash
echo "=== Tool Versions ==="
docker --version
aws --version
terraform --version
kubectl version --client --short
helm version --short
eksctl version
argocd version --client --short 2>/dev/null | head -1
kubectl argo rollouts version
echo "=== All tools verified ==="
```

---

## Phase 2 — Clone the Repository

```bash
git clone https://github.com/rohan/Springboot-BankApp.git
cd Springboot-BankApp
ls -la
```

You should see: `Dockerfile`, `docker-compose.yml`, `terraform/`, `k8s-manifests/`, etc.

---

## Phase 3 — Bootstrap Terraform Backend (Run Once, Ever)

> This creates the S3 bucket and DynamoDB table that store Terraform state.
> **Without this, all subsequent Terraform commands will fail.**

```bash
cd terraform/bootstrap/s3-backend

# Initialize
terraform init

# Review what will be created
terraform plan -var="project_name=bankapp" \
               -var="aws_account_id=$(aws sts get-caller-identity --query Account --output text)" \
               -var='common_tags={"Environment":"bootstrap","ManagedBy":"Terraform"}'

# Apply (creates S3 bucket)
terraform apply -var="project_name=bankapp" \
                -var="aws_account_id=$(aws sts get-caller-identity --query Account --output text)" \
                -var='common_tags={"Environment":"bootstrap","ManagedBy":"Terraform"}' \
                -auto-approve

# Note the bucket name from output
```

```bash
cd ../dynamodb-lock

terraform init
terraform apply -var="project_name=bankapp" \
                -var="environment=bootstrap" \
                -var='common_tags={"Environment":"bootstrap","ManagedBy":"Terraform"}' \
                -auto-approve

# Note the table name from output
cd ../../..
```

---

## Phase 4 — Update terraform.tfvars

```bash
cd terraform/prod
nano terraform.tfvars
```

Update these values with your actual information:

```hcl
project_name = "bankapp-prod"       # Keep this
environment  = "prod"               # Keep this

vpc_cidr             = "10.0.0.0/16"
public_subnets       = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnets  = ["10.0.10.0/24", "10.0.11.0/24"]
private_data_subnets = ["10.0.20.0/24", "10.0.21.0/24"]

db_username       = "bankadmin"
db_instance_class = "db.t3.medium"

domain_name = "YOUR_ACTUAL_DOMAIN.com"    # ← Change this

common_tags = {
  Project            = "Banking-System"
  Environment        = "Production"
  ManagedBy          = "Terraform"
  CostCenter         = "Finance-IT"
  SecurityCompliance = "PCI-DSS"
}
```

Also update `backend.tf` with your actual bucket name from Phase 3:

```bash
nano backend.tf
# Update:
# bucket = "bankapp-terraform-state-YOUR_ACCOUNT_ID"
# dynamodb_table = "bankapp-terraform-locks"
```

---

## Phase 5 — Deploy Infrastructure

```bash
cd terraform/scripts
chmod +x init.sh deploy.sh destroy.sh

# Step 1: Initialize backend and create workspace
./init.sh

# Step 2: Review and deploy (will ask for confirmation)
./deploy.sh
```

> ⏱️ **This takes 15–25 minutes.** EKS cluster creation is the slowest part. Grab a coffee.

When complete, note these outputs — you'll need them:
```bash
cd ../prod
terraform output
# vpc_id
# eks_cluster_endpoint
# rds_endpoint
# app_iam_role_arn
```

---

## Phase 6 — Configure kubectl for EKS

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name bankapp-prod-eks

# Verify cluster access
kubectl get nodes
# Should show 2 nodes in Ready state
```

---

## Phase 7 — Install EKS Add-ons (CRITICAL ORDER)

These must be installed **in this exact order**. Each one is a dependency for the next.

### 7.1 — EBS CSI Driver (for persistent volumes)

```bash
eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster bankapp-prod-eks \
  --region us-east-1 \
  --force

# Verify
kubectl get pods -n kube-system | grep ebs-csi
# Should show 2 pods running
```

### 7.2 — gp3 StorageClass (required for Prometheus, Grafana)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
EOF

# Verify
kubectl get storageclass
# gp3 should show as (default)
```

### 7.3 — OIDC Provider for IRSA

```bash
eksctl utils associate-iam-oidc-provider \
  --region us-east-1 \
  --cluster bankapp-prod-eks \
  --approve

# Verify
aws iam list-open-id-connect-providers
```

### 7.4 — AWS Load Balancer Controller

```bash
# Download IAM policy
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

# Create the policy
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# Create service account with IRSA
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
  --cluster=bankapp-prod-eks \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve \
  --region us-east-1

# Install via Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=bankapp-prod-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Verify (wait ~60 seconds)
kubectl get pods -n kube-system | grep aws-load-balancer
# Should show 2 pods running
```

### 7.5 — External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --wait

# Verify
kubectl get pods -n external-secrets
```

### 7.6 — Create DB Secret in AWS Secrets Manager

```bash
aws secretsmanager create-secret \
  --name "prod/banking/db-credentials" \
  --region us-east-1 \
  --secret-string '{
    "username": "bankadmin",
    "password": "YourSecurePassword123!"
  }'

# Note: This password must match what you used in terraform.tfvars for db_password
```

### 7.7 — Create ClusterSecretStore (links External Secrets to AWS)

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
EOF
```

---

## Phase 8 — Install ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for all pods to be ready (takes ~2 minutes)
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
# Open browser: https://localhost:8080
# Username: admin
# Password: (from command above)
```

### 8.1 — Install Argo Rollouts

```bash
kubectl create namespace argo-rollouts

kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Verify
kubectl get pods -n argo-rollouts
```

---

## Phase 9 — Update K8s Manifests with Your Real Values

Before deploying via GitOps, you must replace placeholder values:

### 9.1 — Update values-prod.yaml

```bash
nano k8s-manifests/banking-platform/values-prod.yaml
```

Update:
```yaml
image:
  repository: YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/banking-api
  tag: "v1.0.0"

serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::YOUR_ACCOUNT_ID:role/banking-prod-irsa-role

ingress:
  certificateArn: arn:aws:acm:us-east-1:YOUR_ACCOUNT_ID:certificate/YOUR_CERT_ID
  hosts:
    - host: api.YOUR_DOMAIN.com
```

### 9.2 — Update repo-secret.yaml

```bash
nano k8s-manifests/argocd-infra/repo-secret.yaml
```

Update:
```yaml
stringData:
  url: https://github.com/YOUR_USERNAME/YOUR_REPO.git
  username: "your-github-username"
  password: "ghp_your_actual_github_token"
```

### 9.3 — Update IRSA ARNs for Loki and Tempo

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Update loki-service-account.yaml
sed -i "s/123456789012/${ACCOUNT_ID}/g" \
  k8s-manifests/argocd-infra/monitoring/loki-service-account.yaml

# Update tempo-sa.yaml
sed -i "s/123456789012/${ACCOUNT_ID}/g" \
  k8s-manifests/argocd-infra/monitoring/tempo-sa.yaml

# Update karpenter.yaml
sed -i "s/123456789012/${ACCOUNT_ID}/g" \
  k8s-manifests/argocd-infra/governance/karpenter.yaml
```

### 9.4 — Update Alertmanager Slack Webhook

```bash
nano k8s-manifests/argocd-infra/monitoring/prometheus-stack.yaml
# Replace all occurrences of "REPLACE_WITH_SECURE_SECRET" 
# with your actual Slack webhook URL
```

### 9.5 — Commit and Push All Changes

```bash
git add .
git commit -m "chore: update manifests with actual account values"
git push origin main
```

---

## Phase 10 — Deploy via GitOps (ArgoCD App-of-Apps)

This single command deploys **everything** — Istio, Karpenter, Kyverno, Monitoring stack, Velero, the banking app — everything.

```bash
# Apply the root App-of-Apps
kubectl apply -f k8s-manifests/argocd-infra/master-app.yaml

# Watch the sync progress
kubectl get applications -n argocd -w
```

ArgoCD will now automatically sync and deploy in dependency order:
```
master-app (root)
├── istio-base           (CRDs first)
├── istiod               (control plane)
├── istio-ingressgateway (NLB)
├── kyverno              (policy engine)
├── karpenter            (autoscaler)
├── kube-prometheus-stack (metrics)
├── loki-stack           (logs)
├── tempo-stack          (traces)
├── otel-collector       (telemetry pipeline)
├── kiali-server         (service mesh UI)
├── velero               (DR)
├── minio                (backup storage)
├── sonarqube            (code quality)
└── banking-app          (the actual application)
```

> ⏱️ **This takes 10–20 minutes.** The monitoring stack is heavy.

---

## Phase 11 — Configure DNS

Once Istio ingress gateway is up, get its DNS name:

```bash
kubectl get svc istio-ingressgateway -n istio-system
# Note the EXTERNAL-IP (NLB DNS name)
```

Go to AWS Console → Route53 → Your Hosted Zone → Create Record:
```
Type:  CNAME
Name:  api
Value: <NLB DNS name from above>
TTL:   60

Repeat for:
Name:  grafana
Name:  sonarqube
```

---

## Phase 12 — Verify Everything is Running

```bash
# Check all namespaces
kubectl get pods --all-namespaces

# Check ArgoCD app health
kubectl get applications -n argocd

# Check the banking app
kubectl get rollout -n banking-prod

# Check monitoring
kubectl get pods -n monitoring

# Check service mesh
kubectl get pods -n istio-system

# Test the app
curl https://api.YOUR_DOMAIN.com/actuator/health
```

---

## ✅ Mode 2 Final Checklist

```
[ ] AWS credentials configured (aws sts get-caller-identity works)
[ ] Terraform bootstrap completed (S3 bucket + DynamoDB table exist)
[ ] terraform/prod deploy completed (EKS + RDS + ALB provisioned)
[ ] kubectl get nodes shows 2 Ready nodes
[ ] EBS CSI driver installed, gp3 StorageClass is default
[ ] AWS Load Balancer Controller running in kube-system
[ ] External Secrets Operator running
[ ] ArgoCD installed and accessible
[ ] Argo Rollouts installed
[ ] All placeholder ARNs/Account IDs updated in manifests
[ ] Slack webhook updated in prometheus-stack.yaml
[ ] Git repo updated with real values and pushed
[ ] master-app.yaml applied to cluster
[ ] All ArgoCD apps show Healthy/Synced status
[ ] DNS records created in Route53
[ ] https://api.YOUR_DOMAIN.com/actuator/health returns UP
[ ] https://grafana.YOUR_DOMAIN.com is accessible
```

---

---

# ✅ MODE 3 — Jenkins CI/CD Pipeline Setup

> **Goal:** Set up Jenkins to run the DevSecOps pipeline (build → scan → push to ECR → deploy).

---

## Jenkins Server Requirements

```
OS:      Ubuntu 22.04 LTS
CPU:     4 cores (Jenkins + Docker + Scans are heavy)
RAM:     8 GB minimum
Disk:    50 GB
Ports:   8080 (Jenkins UI), 50000 (agent)
```

---

## Step 1 — Install Java 17

```bash
sudo apt update
sudo apt install -y openjdk-17-jdk

java -version
# Should print: openjdk version "17.x.x"

# Set JAVA_HOME
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' >> ~/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

## Step 2 — Install Jenkins

```bash
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" | \
  sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt update
sudo apt install -y jenkins

sudo systemctl enable jenkins
sudo systemctl start jenkins
sudo systemctl status jenkins

# Get initial admin password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Access Jenkins: `http://<VM_IP>:8080`

## Step 3 — Install Docker (Jenkins needs it)

```bash
# (Same Docker install as Mode 1 Step 3)
# CRITICAL: Add jenkins user to docker group
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# Verify jenkins can run docker
sudo -u jenkins docker ps
```

## Step 4 — Install Maven

```bash
sudo apt install -y maven
mvn --version
```

## Step 5 — Install Trivy (Container Scanner)

```bash
sudo apt-get install -y wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
  sudo apt-key add -
echo deb https://aquasecurity.github.io/trivy-repo/deb \
  $(lsb_release -sc) main | \
  sudo tee -a /etc/apt/sources.list.d/trivy.list

sudo apt-get update
sudo apt-get install -y trivy

trivy --version
```

## Step 6 — Install Jenkins Plugins

In Jenkins UI → **Manage Jenkins → Plugins → Available**:

Install these plugins:
```
Pipeline
Git
Docker Pipeline
SonarQube Scanner
OWASP Dependency-Check
Credentials Binding
AWS Credentials
GitHub Integration
Blue Ocean (optional but nice)
```

## Step 7 — Configure Jenkins Global Tools

Go to **Manage Jenkins → Tools**:

**SonarQube Scanner:**
```
Name: SonarScanner
Install automatically: ✓ (or specify path if manual install)
```

**Maven:**
```
Name: Maven
Install automatically: ✓
```

## Step 8 — Add Jenkins Credentials

Go to **Manage Jenkins → Credentials → Global → Add Credential**:

```
1. GitHub Token (for GitOps push):
   Kind: Secret text
   ID: github-token
   Secret: ghp_your_token

2. AWS Credentials (for ECR push):
   Kind: AWS Credentials
   ID: aws-credentials
   Access Key / Secret Key

3. SonarQube Token:
   Kind: Secret text
   ID: sonarqube-token
   Secret: your_sonar_token
```

## Step 9 — Configure SonarQube Server in Jenkins

Go to **Manage Jenkins → Configure System → SonarQube Servers**:
```
Name: SonarQube-Server
Server URL: http://<SONARQUBE_HOST>:9000
Server auth token: (your sonarqube token)
```

## Step 10 — Create ECR Repository

```bash
aws ecr create-repository \
  --repository-name banking-api \
  --region us-east-1

# Note the repository URI from output
# Format: YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/banking-api
```

## Step 11 — Create Jenkins Pipeline Job

In Jenkins UI:
1. **New Item → Pipeline**
2. Name: `banking-api-pipeline`
3. Pipeline → **Pipeline script from SCM**
4. SCM: Git
5. Repository URL: `https://github.com/YOUR_USERNAME/Springboot-BankApp.git`
6. Credentials: Add your GitHub credentials
7. Branch: `*/main`
8. Script Path: `Jenkinsfile`
9. Save

## Step 12 — Update Jenkinsfile

```bash
nano Jenkinsfile
```

Update with your actual values:
```groovy
devSecOpsPipeline(
    appName: 'banking-api',
    awsAccountId: 'YOUR_ACTUAL_ACCOUNT_ID',   // ← Change this
    awsRegion: 'us-east-1'
)
```

## Step 13 — Run the Pipeline

In Jenkins → Open your pipeline job → **Build Now**

Watch the stages execute:
```
✓ Initialize & Build
✓ SAST - SonarQube
✓ SCA - OWASP Dependency Check
✓ Docker Build & Security Scan (Trivy)
✓ Push to ECR
✗ DAST - OWASP ZAP  ← Will fail unless K8s preview env exists
✓ GitOps Trigger
```

> **Note on DAST:** The ZAP stage will fail unless the K8s preview environment is running. You can comment out that stage for initial testing.

---

## ✅ Mode 3 Jenkins Checklist

```
[ ] Java 17 installed
[ ] Jenkins installed and running on port 8080
[ ] Docker installed, jenkins user in docker group
[ ] Maven installed
[ ] Trivy installed
[ ] Jenkins plugins installed (Pipeline, Docker, SonarQube, OWASP DC, etc.)
[ ] SonarQube Scanner configured as Global Tool
[ ] GitHub token credential added (ID: github-token)
[ ] AWS credentials added
[ ] SonarQube server configured in Jenkins
[ ] ECR repository created
[ ] Jenkinsfile updated with real Account ID
[ ] Pipeline job created and pointing to correct repo
[ ] First build succeeds through ECR push stage
```

---

---

# 🔥 Quick Reference — All Commands

## Start/Stop Docker Compose (Mode 1)

```bash
# Start
docker compose up -d

# Stop
docker compose down

# Restart
docker compose restart

# View logs
docker compose logs -f

# Rebuild after code change
docker compose up --build -d
```

## Terraform Commands

```bash
# Initialize
cd terraform/scripts && ./init.sh

# Plan only (no changes)
cd terraform/prod && terraform plan -var-file=terraform.tfvars

# Deploy
cd terraform/scripts && ./deploy.sh

# Destroy (careful!)
cd terraform/scripts && ./destroy.sh
```

## Kubernetes Quick Checks

```bash
# All pods across all namespaces
kubectl get pods --all-namespaces

# Check a specific namespace
kubectl get pods -n banking-prod
kubectl get pods -n monitoring
kubectl get pods -n istio-system
kubectl get pods -n argocd

# Check ArgoCD app sync status
kubectl get applications -n argocd

# Check a rollout status
kubectl argo rollouts get rollout <rollout-name> -n banking-prod

# Check HPA
kubectl get hpa -n banking-prod

# Tail logs of a pod
kubectl logs -f <pod-name> -n banking-prod

# Describe a failing pod
kubectl describe pod <pod-name> -n banking-prod
```

## ArgoCD Quick Commands

```bash
# Login to ArgoCD CLI
argocd login localhost:8080 --username admin \
  --password $(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d) --insecure

# List apps
argocd app list

# Sync an app manually
argocd app sync <app-name>

# Check app health
argocd app get <app-name>
```

---

# ⚠️ Most Common Failures & Fixes

| Failure | What You'll See | Fix |
|---------|----------------|-----|
| Terraform init fails | "Backend S3 bucket not found" | Run bootstrap first |
| EKS nodes not joining | kubectl get nodes shows no nodes | Check IAM node role policies |
| Pods stuck in Pending | `kubectl describe pod` shows no storage | Install EBS CSI driver, create gp3 SC |
| ALB not created | Ingress stuck, no ADDRESS | Install AWS Load Balancer Controller |
| External secrets not working | Pod crashes, DB password missing | Check IRSA ARN matches, ClusterSecretStore exists |
| ArgoCD sync failed | App shows OutOfSync/Degraded | `argocd app sync <name>` and check logs |
| Karpenter not scaling | Pods stuck Pending but no new nodes | Check subnet tags `karpenter.sh/discovery` |
| Kyverno blocking deploy | Pod creation rejected | Ensure resource limits + runAsNonRoot set |
| Loki/Tempo crashloop | Pods restarting | Check S3 bucket name matches Terraform output |
| Jenkins Docker permission denied | docker: permission denied | `sudo usermod -aG docker jenkins && restart jenkins` |
| SonarQube quality gate fails | Pipeline aborts at SAST | Fix code issues OR adjust quality gate rules |
| Trivy blocks build | CRITICAL CVE found | Update base image, fix vulnerable dependencies |

---

# 💡 Senior Engineer Tips

**On first deployment — always do Mode 1 first.** Verify the Spring Boot app itself works before adding 20 layers of infrastructure around it.

**On Terraform — never run `apply` without reviewing `plan` first.** The `deploy.sh` script already enforces this with a manual confirmation step. Respect it.

**On ArgoCD — the App-of-Apps pattern means one bad YAML can block everything.** If the root app fails to sync, check `kubectl get applications -n argocd` and fix the failing child app individually before the root can converge.

**On Kyverno — the `Enforce` mode is unforgiving.** If you're testing a new deployment and it keeps getting blocked, use `kubectl describe` on the rejected pod — Kyverno prints exactly which policy rule blocked it.

**On EBS CSI driver and storage — this is the most commonly forgotten step.** Without it, every Prometheus, Grafana, and Loki pod will be stuck in Pending forever because PVCs can't bind.

**On secrets — never put real credentials in Git.** The `.env` file in this repo has `Test@123` for local development only. The production path uses AWS Secrets Manager → External Secrets Operator → Kubernetes Secret. That chain must be working before the app pod will start successfully.

**On cost — remember to destroy when not needed.** Run `./destroy.sh` when you're done experimenting. EKS, RDS, and NAT Gateway together cost roughly $5–10/day even with minimal load.