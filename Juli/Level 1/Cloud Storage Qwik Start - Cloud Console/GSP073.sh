#!/bin/bash

# Simple color setup
GREEN=`tput setaf 2`
BOLD=`tput bold`
RESET=`tput sgr0`

echo "${GREEN}${BOLD}Starting Cloud Storage Setup...${RESET}"

# Set region configuration
gcloud config set compute/region $REGION

# Create storage bucket
gsutil mb gs://$DEVSHELL_PROJECT_ID

# Download sample image
curl https://upload.wikimedia.org/wikipedia/commons/thumb/a/a4/Ada_Lovelace_portrait.jpg/800px-Ada_Lovelace_portrait.jpg --output ada.jpg

# Rename file
mv ada.jpg kitten.png

# Upload file to bucket
gsutil cp kitten.png gs://$DEVSHELL_PROJECT_ID

# Copy file from bucket to local
gsutil cp -r gs://$DEVSHELL_PROJECT_ID/kitten.png .

# Copy file to subfolder in bucket
gsutil cp gs://$DEVSHELL_PROJECT_ID/kitten.png gs://$DEVSHELL_PROJECT_ID/image-folder/

# Make bucket publicly readable
gsutil iam ch allUsers:objectViewer gs://$DEVSHELL_PROJECT_ID

echo "${GREEN}${BOLD}Lab completed successfully!${RESET}"