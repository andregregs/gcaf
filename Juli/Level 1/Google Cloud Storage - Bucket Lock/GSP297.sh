#!/bin/bash

# Colors for better output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Google Cloud Storage Retention Policy Demo ===${NC}\n"

# Setup bucket name using project ID
export BUCKET=$(gcloud config get-value project)
echo -e "${CYAN}Using bucket name: gs://$BUCKET${NC}"

# Create storage bucket
echo -e "\n${GREEN}Creating storage bucket...${NC}"
gsutil mb "gs://$BUCKET"

# Wait for bucket creation to complete
echo -e "\n${YELLOW}Waiting for bucket setup...${NC}"
sleep 5

# Set retention policy (10 seconds for demo)
echo -e "\n${GREEN}Setting retention policy (10 seconds)...${NC}"
gsutil retention set 10s "gs://$BUCKET"

# Display retention policy
echo -e "\n${CYAN}Current retention policy:${NC}"
gsutil retention get "gs://$BUCKET"

# Upload first test file
echo -e "\n${GREEN}Uploading dummy_transactions file...${NC}"
gsutil cp gs://spls/gsp297/dummy_transactions "gs://$BUCKET/"

# Show file details
echo -e "\n${CYAN}File details for dummy_transactions:${NC}"
gsutil ls -L "gs://$BUCKET/dummy_transactions"

# Wait before locking
echo -e "\n${YELLOW}Waiting before locking retention policy...${NC}"
sleep 5

# Lock retention policy
echo -e "\n${GREEN}Locking retention policy...${NC}"
gsutil retention lock "gs://$BUCKET/"

# Set temporary hold on file
echo -e "\n${GREEN}Setting temporary hold on dummy_transactions...${NC}"
gsutil retention temp set "gs://$BUCKET/dummy_transactions"

# Try to delete file (will fail due to hold)
echo -e "\n${RED}Attempting to delete file (should fail due to hold)...${NC}"
gsutil rm "gs://$BUCKET/dummy_transactions"

# Release temporary hold
echo -e "\n${GREEN}Releasing temporary hold...${NC}"
gsutil retention temp release "gs://$BUCKET/dummy_transactions"

# Set event-based default hold
echo -e "\n${GREEN}Setting event-based default hold...${NC}"
gsutil retention event-default set "gs://$BUCKET/"

# Upload second test file
echo -e "\n${GREEN}Uploading dummy_loan file...${NC}"
gsutil cp gs://spls/gsp297/dummy_loan "gs://$BUCKET/"

# Show file details with event hold
echo -e "\n${CYAN}File details for dummy_loan (with event hold):${NC}"
gsutil ls -L "gs://$BUCKET/dummy_loan"

# Release event-based hold
echo -e "\n${GREEN}Releasing event-based hold on dummy_loan...${NC}"
gsutil retention event release "gs://$BUCKET/dummy_loan"

# Show file details after release
echo -e "\n${CYAN}File details after event hold release:${NC}"
gsutil ls -L "gs://$BUCKET/dummy_loan"

echo -e "\n${GREEN}All operations completed successfully!${NC}"
echo -e "${BLUE}================================================${NC}"
echo -e "${CYAN}Retention Policy Demo Summary:${NC}"
echo -e "${CYAN}• Bucket: gs://$BUCKET${NC}"
echo -e "${CYAN}• Retention Policy: 10 seconds (locked)${NC}"
echo -e "${CYAN}• Demonstrated: Temporary & Event-based holds${NC}"
echo -e "${CYAN}• Files: dummy_transactions, dummy_loan${NC}"
echo -e "${BLUE}================================================${NC}"