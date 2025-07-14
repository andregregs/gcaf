#!/bin/bash

# Colors for better output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}=== Google Cloud Storage Operations ===${NC}\n"

# Check authentication and project
echo -e "${CYAN}Checking authentication...${NC}"
gcloud auth list

echo -e "\n${CYAN}Current project configuration:${NC}"
gcloud config list project

# Set project ID variable
echo -e "\n${CYAN}Setting up project ID...${NC}"
export PROJECT_ID=$(gcloud config get-value project)
echo "Project ID: $PROJECT_ID"

# Create storage bucket
echo -e "\n${GREEN}Creating storage bucket...${NC}"
gsutil mb gs://$PROJECT_ID-gcaf

# Download and upload image
echo -e "\n${GREEN}Downloading sample image...${NC}"
curl https://upload.wikimedia.org/wikipedia/commons/thumb/a/a4/Ada_Lovelace_portrait.jpg/800px-Ada_Lovelace_portrait.jpg --output ada.jpg

echo -e "\n${GREEN}Uploading image to bucket...${NC}"
gsutil cp ada.jpg gs://$PROJECT_ID-gcaf

# Clean up local file
echo -e "\n${GREEN}Removing local file...${NC}"
rm ada.jpg

# Download file back from bucket
echo -e "\n${GREEN}Downloading file back from bucket...${NC}"
gsutil cp -r gs://$PROJECT_ID-gcaf/ada.jpg .

# Copy to another location (requires destination bucket to exist)
echo -e "\n${GREEN}Copying to image folder...${NC}"
gsutil cp gs://$PROJECT_ID-gcaf/ada.jpg gs://$PROJECT_ID-gcaf/image-folder/

# List bucket contents
echo -e "\n${CYAN}Listing bucket contents:${NC}"
gsutil ls gs://$PROJECT_ID-gcaf

echo -e "\n${CYAN}Detailed file information:${NC}"
gsutil ls -l gs://$PROJECT_ID-gcaf/ada.jpg

# Make file publicly readable
echo -e "\n${GREEN}Making file publicly accessible...${NC}"
gsutil acl ch -u AllUsers:R gs://$PROJECT_ID-gcaf/ada.jpg

echo -e "\n${GREEN}All operations completed successfully!${NC}"
echo -e "${BLUE}=================================${NC}"