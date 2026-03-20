#!/bin/bash

echo "🚀 Creating Terraform Infrastructure Structure..."

# Root folder
mkdir -p infrastructure
cd infrastructure || exit

# -------------------------
# Modules
# -------------------------
MODULES=("networking" "eks" "rds" "alb" "iam" "security" "s3" "cloudwatch" "route53")

for module in "${MODULES[@]}"; do
  mkdir -p modules/$module
  touch modules/$module/main.tf
  touch modules/$module/variables.tf
  touch modules/$module/outputs.tf
done

# -------------------------
# Production Environment
# -------------------------
mkdir -p prod
touch prod/main.tf
touch prod/variables.tf
touch prod/outputs.tf
touch prod/terraform.tfvars
touch prod/backend.tf

# -------------------------
# Global Infrastructure
# -------------------------
mkdir -p global/route53
mkdir -p global/acm
mkdir -p global/s3-backend

for dir in route53 acm s3-backend; do
  touch global/$dir/main.tf
  touch global/$dir/variables.tf
  touch global/$dir/outputs.tf
done

# -------------------------
# Bootstrap (One-time setup)
# -------------------------
mkdir -p bootstrap/s3-backend
mkdir -p bootstrap/dynamodb-lock

for dir in s3-backend dynamodb-lock; do
  touch bootstrap/$dir/main.tf
  touch bootstrap/$dir/variables.tf
  touch bootstrap/$dir/outputs.tf
done

# -------------------------
# Scripts
# -------------------------
mkdir -p scripts
touch scripts/deploy.sh
touch scripts/destroy.sh
touch scripts/init.sh

chmod +x scripts/*.sh

# -------------------------
# GitHub Actions
# -------------------------
mkdir -p .github/workflows

# -------------------------
# README
# -------------------------
touch README.md

echo "✅ Terraform structure created successfully!"
