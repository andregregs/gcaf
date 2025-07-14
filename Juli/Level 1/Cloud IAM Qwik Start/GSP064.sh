#!/bin/bash

# Colors for better output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}=== Google Cloud IAM & Storage Setup ===${NC}\n"

# Check authentication
echo -e "${CYAN}Checking authentication...${NC}"
gcloud auth list

# Get username input
echo -e "\n${YELLOW}${BOLD}Enter the USERNAME_2 (email address):${NC}"
read -p "Username: " USERNAME_2
echo "Setting up permissions for: $USERNAME_2"

# Create sample file
echo -e "\n${GREEN}Creating sample file...${NC}"
touch sample.txt
echo "Sample content for testing" > sample.txt

# Create storage bucket
echo -e "\n${GREEN}Creating storage bucket...${NC}"
gsutil mb gs://$DEVSHELL_PROJECT_ID

# Upload file to bucket
echo -e "\n${GREEN}Uploading sample file to bucket...${NC}"
gsutil cp sample.txt gs://$DEVSHELL_PROJECT_ID

# Remove viewer role (if exists)
echo -e "\n${GREEN}Removing viewer role from user...${NC}"
gcloud projects remove-iam-policy-binding $DEVSHELL_PROJECT_ID \
  --member="user:$USERNAME_2" \
  --role="roles/viewer" \
  --quiet

# Add storage object viewer role
echo -e "\n${GREEN}Adding storage object viewer role to user...${NC}"
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
  --member="user:$USERNAME_2" \
  --role="roles/storage.objectViewer"

echo -e "\n${GREEN}All operations completed successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${CYAN}IAM and Storage setup completed:${NC}"
echo -e "${CYAN}• Bucket created: gs://$DEVSHELL_PROJECT_ID${NC}"
echo -e "${CYAN}• Sample file uploaded: sample.txt${NC}"
echo -e "${CYAN}• User: $USERNAME_2${NC}"
echo -e "${CYAN}• Permission: Storage Object Viewer${NC}"
echo -e "${BLUE}========================================${NC}"