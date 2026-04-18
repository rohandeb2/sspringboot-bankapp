#!/bin/bash

set -e

echo "🚀 Starting DevOps Setup..."

# -------------------------------
# Base packages
# -------------------------------
sudo apt update
sudo apt install -y curl unzip git wget ca-certificates gnupg lsb-release

# -------------------------------
# AWS CLI (idempotent)
# -------------------------------
if command -v aws &> /dev/null; then
    echo "✅ AWS CLI already installed"
else
    echo "☁️ Installing AWS CLI..."
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
    unzip -oq awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
fi

# -------------------------------
# Terraform (FIXED)
# -------------------------------
if command -v terraform &> /dev/null; then
    echo "✅ Terraform already installed"
else
    echo "🏗️ Installing Terraform..."
    wget -q https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip
    unzip -oq terraform_1.9.0_linux_amd64.zip
    
    # Remove wrong directory if exists
    [ -d "terraform" ] && rm -rf terraform

    sudo mv terraform /usr/local/bin/
    rm terraform_1.9.0_linux_amd64.zip
fi

# -------------------------------
# kubectl
# -------------------------------
if command -v kubectl &> /dev/null; then
    echo "✅ kubectl already installed"
else
    echo "☸️ Installing kubectl..."
    K_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO https://dl.k8s.io/release/${K_VERSION}/bin/linux/amd64/kubectl
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
fi

# -------------------------------
# Helm
# -------------------------------
if command -v helm &> /dev/null; then
    echo "✅ Helm already installed"
else
    echo "⛵ Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# -------------------------------
# Docker
# -------------------------------
if command -v docker &> /dev/null; then
    echo "✅ Docker already installed"
else
    echo "🐳 Installing Docker..."
    sudo install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
    "deb [arch=$(dpkg --print-architecture) \
    signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo usermod -aG docker $USER
fi

# -------------------------------
# ArgoCD
# -------------------------------
if command -v argocd &> /dev/null; then
    echo "✅ ArgoCD already installed"
else
    echo "🚀 Installing ArgoCD..."
    sudo curl -sSL -o /usr/local/bin/argocd \
    https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64

    sudo chmod +x /usr/local/bin/argocd
fi

# -------------------------------
# Final check
# -------------------------------
echo "✅ Verification:"
aws --version
terraform -version
kubectl version --client || true
helm version || true
docker --version || true
argocd version --client || true

echo "🎉 Setup complete!"
echo "⚠️ Run: newgrp docker"
