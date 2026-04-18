#!/bin/bash

set -e

echo "🚀 Starting DevOps Setup..."

# -------------------------------
# Base packages
# -------------------------------
sudo apt update
sudo apt install -y curl unzip git wget ca-certificates gnupg lsb-release

# -------------------------------
# AWS CLI
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
# Terraform
# -------------------------------
if command -v terraform &> /dev/null; then
    echo "✅ Terraform already installed"
else
    echo "🏗️ Installing Terraform..."
    wget -q https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip
    unzip -oq terraform_1.9.0_linux_amd64.zip
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
    sudo apt update && \
    sudo apt install -y ca-certificates curl gnupg && \
    sudo install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    sudo chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    sudo apt update && \
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && \
    sudo usermod -aG docker $USER && \
    newgrp docker && \
    docker --version
fi

# -------------------------------
# ArgoCD CLI
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
# eksctl
# -------------------------------
if command -v eksctl &> /dev/null; then
    echo "✅ eksctl already installed"
else
    echo "☸️ Installing eksctl..."
    curl --silent --location \
    "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" \
    | tar xz -C /tmp

    sudo mv /tmp/eksctl /usr/local/bin
fi

# -------------------------------
# Argo Rollouts CLI
# -------------------------------
if command -v kubectl-argo-rollouts &> /dev/null; then
    echo "✅ Argo Rollouts already installed"
else
    echo "🚀 Installing Argo Rollouts..."
    curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
    chmod +x kubectl-argo-rollouts-linux-amd64
    sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
fi

# -------------------------------
# Istioctl
# -------------------------------
if command -v istioctl &> /dev/null; then
    echo "✅ Istioctl already installed"
else
    echo "🌐 Installing Istioctl..."
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.22.0 sh -
    sudo mv istio-1.22.0/bin/istioctl /usr/local/bin/
    rm -rf istio-1.22.0
fi

# -------------------------------
# Velero
# -------------------------------
if command -v velero &> /dev/null; then
    echo "✅ Velero already installed"
else
    echo "💾 Installing Velero..."
    curl -L -o velero.tar.gz https://github.com/vmware-tanzu/velero/releases/download/v1.13.1/velero-v1.13.1-linux-amd64.tar.gz
    tar -xzf velero.tar.gz
    sudo mv velero-*/velero /usr/local/bin/
    rm -rf velero-*
fi

# -------------------------------
# Verification
# -------------------------------
echo "🔍 Running verification..."

echo "--------------------------------"
for cmd in docker aws terraform kubectl helm eksctl argocd istioctl velero; do
  if command -v $cmd &> /dev/null; then
    echo "✅ $cmd installed -> $($cmd version 2>/dev/null | head -1)"
  else
    echo "❌ $cmd NOT installed"
  fi
done
echo "--------------------------------"

echo "🎉 Setup complete!"
echo "⚠️ Run: newgrp docker"
