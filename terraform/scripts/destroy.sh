#!/bin/bash

# Exit on error
set -e

ENV="prod"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
echo -e "${RED}WARNING: YOU ARE ABOUT TO DESTROY THE ${ENV} ENVIRONMENT${NC}"
echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"

cd ../prod/

# 1. Ensure we are in the correct workspace
terraform workspace select ${ENV}

# 2. Extra Security Check
read -p "Type the environment name '${ENV}' to confirm destruction: " CONFIRM
if [ "$CONFIRM" != "$ENV" ]; then
    echo -e "${YELLOW}Confirmation failed. Exiting...${NC}"
    exit 1
fi

# 3. Terraform Destroy
echo -e "${YELLOW}Starting destruction...${NC}"
terraform destroy -var-file="terraform.tfvars" -auto-approve

echo -e "${RED}✔ Environment ${ENV} has been destroyed.${NC}"