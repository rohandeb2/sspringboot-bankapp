#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- Configuration ---
PROJECT_NAME="bankapp"
ENV="prod"
REGION="us-east-1"
# Fetch Account ID automatically to avoid hardcoding
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${PROJECT_NAME}-terraform-state-${ACCOUNT_ID}"
DYNAMO_TABLE="${PROJECT_NAME}-terraform-locks"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting Infrastructure Initialization for: ${PROJECT_NAME} (${ENV})${NC}"

# 1. Check if S3 Bucket exists (Bootstrap check)
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo -e "${GREEN}✔ S3 Backend Bucket found: $BUCKET_NAME${NC}"
else
    echo -e "\033[0;31m✘ Error: S3 Bucket $BUCKET_NAME not found. Run bootstrap first!${NC}"
    exit 1
fi

# 2. Initialize Terraform with Backend Config
echo -e "${YELLOW}Initializing Terraform Backend...${NC}"
cd ../prod/

terraform init \
    -backend-config="bucket=${BUCKET_NAME}" \
    -backend-config="key=${ENV}/terraform.tfstate" \
    -backend-config="region=${REGION}" \
    -backend-config="dynamodb_table=${DYNAMO_TABLE}" \
    -backend-config="encrypt=true" \
    -reconfigure

# 3. Create a workspace if it doesn't exist (Best practice for environment isolation)
if terraform workspace list | grep -q "$ENV"; then
    terraform workspace select "$ENV"
else
    terraform workspace new "$ENV"
fi

echo -e "${GREEN}✔ Initialization Complete! You are now in the '$ENV' workspace.${NC}"
echo -e "${YELLOW}Next Step: run './deploy.sh' to plan and apply.${NC}"