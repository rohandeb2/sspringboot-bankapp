#!/bin/bash

# Exit on error
set -e

# --- Configuration ---
ENV="prod"
PLAN_FILE="tfplan-${ENV}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}--- Starting Deployment Process for ${ENV} ---${NC}"

cd ../prod/

# 1. Ensure we are in the correct workspace
echo -e "${YELLOW}Switching to workspace: ${ENV}${NC}"
terraform workspace select ${ENV} || terraform workspace new ${ENV}

# 2. Terraform Plan
# We save the plan to a file to ensure consistency between plan and apply
echo -e "${YELLOW}Generating Execution Plan...${NC}"
terraform plan -var-file="terraform.tfvars" -out=${PLAN_FILE}

echo -e "${GREEN}Plan generated successfully.${NC}"

# 3. Manual Confirmation (Safety Gate)
read -p "Do you want to apply this plan to the ${ENV} environment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo -e "${YELLOW}Deployment cancelled by user.${NC}"
    exit 1
fi

# 4. Terraform Apply
echo -e "${YELLOW}Applying Plan...${NC}"
terraform apply ${PLAN_FILE}

# 5. Cleanup
rm ${PLAN_FILE}

echo -e "${GREEN}✔ Deployment Complete!${NC}"