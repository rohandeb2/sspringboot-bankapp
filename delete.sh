#!/bin/bash
# ============================================================
# Banking Platform — Full AWS Cleanup Script (Skip Terraform)
# ============================================================
# This script removes all Kubernetes resources and AWS assets
# created manually (outside of Terraform).
# Terraform-managed resources (VPC, EKS, RDS, ALB, ACM,
# Route53) are NOT touched — destroy those separately via
# `terraform destroy` when you are ready.
# ============================================================

set -e

CLUSTER_NAME="bankapp-prod-eks"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo ""
echo "============================================"
echo " Banking Platform Cleanup"
echo " Account : $ACCOUNT_ID"
echo " Cluster : $CLUSTER_NAME"
echo " Region  : $REGION"
echo "============================================"
echo ""
read -p "Are you sure you want to delete everything? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

# ============================================================
# STEP 1 — Karpenter
# ============================================================
echo ""
echo ">>> STEP 1: Removing Karpenter..."

kubectl delete nodepool default --ignore-not-found
kubectl delete ec2nodeclass default --ignore-not-found

helm uninstall karpenter -n karpenter 2>/dev/null || true
kubectl delete ns karpenter --ignore-not-found

# Clean up stale instance profiles created by Karpenter
echo "Cleaning up Karpenter-managed instance profiles..."
for profile in $(aws iam list-instance-profiles \
  --query "InstanceProfiles[?contains(InstanceProfileName,'bankapp-prod-eks')].InstanceProfileName" \
  --output text 2>/dev/null); do
  echo "  Deleting instance profile: $profile"
  # Remove roles from profile first
  for role in $(aws iam get-instance-profile \
    --instance-profile-name "$profile" \
    --query "InstanceProfile.Roles[].RoleName" \
    --output text 2>/dev/null); do
    aws iam remove-role-from-instance-profile \
      --instance-profile-name "$profile" \
      --role-name "$role" 2>/dev/null || true
  done
  aws iam delete-instance-profile \
    --instance-profile-name "$profile" 2>/dev/null || true
done

echo "  [DONE] Karpenter removed"

# ============================================================
# STEP 2 — Monitoring Stack (Prometheus + Grafana)
# ============================================================
echo ""
echo ">>> STEP 2: Removing Monitoring stack..."

helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true
helm uninstall loki -n monitoring 2>/dev/null || true
helm uninstall promtail -n monitoring 2>/dev/null || true
helm uninstall tempo -n monitoring 2>/dev/null || true
helm uninstall kiali -n monitoring 2>/dev/null || true
kubectl delete ns monitoring --ignore-not-found

echo "  [DONE] Monitoring stack removed"

# ============================================================
# STEP 3 — ArgoCD Apps + ArgoCD itself
# ============================================================
echo ""
echo ">>> STEP 3: Removing ArgoCD..."

# Delete all ArgoCD apps first (cascade=false to avoid deleting k8s resources twice)
kubectl get applications -n argocd \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | \
  tr ' ' '\n' | \
  while read app; do
    echo "  Deleting ArgoCD app: $app"
    kubectl delete application "$app" -n argocd --ignore-not-found 2>/dev/null || true
  done

kubectl delete ns argocd --ignore-not-found

echo "  [DONE] ArgoCD removed"

# ============================================================
# STEP 4 — Argo Rollouts
# ============================================================
echo ""
echo ">>> STEP 4: Removing Argo Rollouts..."

kubectl delete -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml \
  2>/dev/null || true
kubectl delete ns argo-rollouts --ignore-not-found

echo "  [DONE] Argo Rollouts removed"

# ============================================================
# STEP 5 — Banking App (Helm release)
# ============================================================
echo ""
echo ">>> STEP 5: Removing Banking App..."

helm uninstall bankapp -n banking-prod 2>/dev/null || true
kubectl delete ns banking-prod --ignore-not-found

echo "  [DONE] Banking App removed"

# ============================================================
# STEP 6 — Istio
# ============================================================
echo ""
echo ">>> STEP 6: Removing Istio..."

helm uninstall istio-ingressgateway -n istio-system 2>/dev/null || true
helm uninstall istiod -n istio-system 2>/dev/null || true
helm uninstall istio-base -n istio-system 2>/dev/null || true

# Also try ArgoCD-managed istio resources
kubectl delete ns istio-system --ignore-not-found

echo "  [DONE] Istio removed"

# ============================================================
# STEP 7 — Kyverno
# ============================================================
echo ""
echo ">>> STEP 7: Removing Kyverno..."

kubectl delete clusterpolicy banking-guardrails --ignore-not-found
helm uninstall kyverno -n kyverno 2>/dev/null || true
kubectl delete ns kyverno --ignore-not-found

echo "  [DONE] Kyverno removed"

# ============================================================
# STEP 8 — External Secrets Operator
# ============================================================
echo ""
echo ">>> STEP 8: Removing External Secrets..."

kubectl delete clustersecretstore aws-secretsmanager --ignore-not-found
helm uninstall external-secrets -n external-secrets 2>/dev/null || true
kubectl delete ns external-secrets --ignore-not-found

echo "  [DONE] External Secrets removed"

# ============================================================
# STEP 9 — AWS Load Balancer Controller
# ============================================================
echo ""
echo ">>> STEP 9: Removing AWS Load Balancer Controller..."

helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

# Delete IRSA service account
eksctl delete iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --region=$REGION 2>/dev/null || true

# Delete IAM policy
aws iam delete-policy \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  2>/dev/null || true

echo "  [DONE] AWS Load Balancer Controller removed"

# ============================================================
# STEP 10 — EBS CSI Driver IRSA
# ============================================================
echo ""
echo ">>> STEP 10: Removing EBS CSI IRSA service account..."

eksctl delete iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=ebs-csi-controller-sa \
  --region=$REGION 2>/dev/null || true

eksctl delete addon \
  --name aws-ebs-csi-driver \
  --cluster $CLUSTER_NAME \
  --region $REGION 2>/dev/null || true

# Delete gp3 storage class
kubectl delete storageclass gp3 --ignore-not-found

echo "  [DONE] EBS CSI removed"

# ============================================================
# STEP 11 — External Secrets IRSA
# ============================================================
echo ""
echo ">>> STEP 11: Removing External Secrets IRSA..."

eksctl delete iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=external-secrets \
  --name=external-secrets \
  --region=$REGION 2>/dev/null || true

echo "  [DONE] External Secrets IRSA removed"

# ============================================================
# STEP 12 — Karpenter IAM (manually created inline policies)
# ============================================================
echo ""
echo ">>> STEP 12: Removing Karpenter extra IAM policies..."

aws iam delete-role-policy \
  --role-name bankapp-karpenter-controller-irsa \
  --policy-name karpenter-extra-permissions \
  2>/dev/null || true

echo "  [DONE] Karpenter inline policy removed"

# ============================================================
# STEP 13 — ECR Repository
# ============================================================
echo ""
echo ">>> STEP 13: Removing ECR repository..."

aws ecr delete-repository \
  --repository-name banking-app \
  --region $REGION \
  --force \
  2>/dev/null || true

echo "  [DONE] ECR repository removed"

# ============================================================
# STEP 14 — Secrets Manager
# ============================================================
echo ""
echo ">>> STEP 14: Removing Secrets Manager secrets..."

aws secretsmanager delete-secret \
  --secret-id banking-prod-db-secret \
  --force-delete-without-recovery \
  --region $REGION 2>/dev/null || true

aws secretsmanager delete-secret \
  --secret-id banking-github-creds \
  --force-delete-without-recovery \
  --region $REGION 2>/dev/null || true

echo "  [DONE] Secrets removed"

# ============================================================
# STEP 15 — Scale down EKS node group to 0 (saves EC2 cost)
# while keeping cluster alive for Terraform destroy later
# ============================================================
echo ""
echo ">>> STEP 15: Scaling EKS node group to 0..."

aws eks update-nodegroup-config \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name general-purpose \
  --scaling-config minSize=0,maxSize=4,desiredSize=0 \
  --region $REGION 2>/dev/null || true

echo "  [DONE] Node group scaling to 0 (takes 2-3 mins)"

# ============================================================
echo ""
echo "============================================"
echo " Cleanup Complete!"
echo " Run the verification steps below to confirm"
echo "============================================"
echo ""
echo "Run this to verify nothing is left:"
echo "  bash verify_cleanup.sh"
