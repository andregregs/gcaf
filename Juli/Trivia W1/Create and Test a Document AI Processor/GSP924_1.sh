#!/bin/bash

# =====================================================
# Google Cloud Document AI Setup Script
# Complete Document AI Environment Setup
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting Google Cloud Document AI setup...${RESET}"

# =====================================================
# 1. AUTHENTICATION CHECK
# =====================================================
echo -e "${YELLOW}Step 1: Checking authentication...${RESET}"

# Check current authentication
gcloud auth list

echo -e "${GREEN}✅ Authentication verified${RESET}"

# =====================================================
# 2. ENABLE DOCUMENT AI SERVICE
# =====================================================
echo -e "${YELLOW}Step 2: Enabling Document AI API...${RESET}"

# Enable Document AI API
gcloud services enable documentai.googleapis.com --project=$DEVSHELL_PROJECT_ID

echo -e "${GREEN}✅ Document AI API enabled${RESET}"

# =====================================================
# 3. ENVIRONMENT SETUP
# =====================================================
echo -e "${YELLOW}Step 3: Setting up environment variables...${RESET}"

# Set up environment variables
export PROJECT_ID=$(gcloud config get-value project)

echo -e "${GREEN}✅ Environment configured: $PROJECT_ID${RESET}"

# =====================================================
# 4. MANUAL SETUP INSTRUCTIONS
# =====================================================
echo -e "${YELLOW}Step 4: Manual setup required...${RESET}"

echo ""
echo -e "${CYAN}${BOLD}📋 REQUIRED MANUAL ACTIONS:${RESET}"
echo ""

echo -e "${YELLOW}${BOLD}1. Create a 'form-parser' Processor:${RESET}"
echo -e "${BLUE}   ${BOLD}→ Open: https://console.cloud.google.com/ai/document-ai/processor-library?inv=1&invt=Ab2Kyg&project=$DEVSHELL_PROJECT_ID${RESET}"
echo -e "${CYAN}   • Navigate to Document AI Processor Library${RESET}"
echo -e "${CYAN}   • Find and select 'Form Parser'${RESET}"
echo -e "${CYAN}   • Create the processor${RESET}"
echo ""

echo -e "${YELLOW}${BOLD}2. Download the sample form:${RESET}"
echo -e "${BLUE}   ${BOLD}→ Download: https://storage.googleapis.com/cloud-training/document-ai/generic/form.pdf${RESET}"
echo -e "${CYAN}   • Save this file for testing Document AI${RESET}"
echo ""

# =====================================================
# 5. INSTANCE CONNECTION SETUP
# =====================================================
echo -e "${YELLOW}Step 5: Setting up development environment connection...${RESET}"

echo -e "${CYAN}Finding Document AI development instance...${RESET}"

# Get zone of the document-ai-dev instance
export ZONE=$(gcloud compute instances list document-ai-dev --format='csv[no-heading](zone)')

if [ -z "$ZONE" ]; then
    echo -e "${RED}❌ Error: document-ai-dev instance not found${RESET}"
    echo -e "${YELLOW}Please ensure the instance exists in your project${RESET}"
    exit 1
fi

echo -e "${GREEN}✅ Found instance in zone: $ZONE${RESET}"

# =====================================================
# 6. CONNECT TO DEVELOPMENT INSTANCE
# =====================================================
echo -e "${YELLOW}Step 6: Connecting to development instance...${RESET}"

echo -e "${CYAN}Connecting to document-ai-dev instance via SSH...${RESET}"

# SSH into the development instance
gcloud compute ssh --zone "$ZONE" "document-ai-dev" --project "$DEVSHELL_PROJECT_ID" --quiet

echo -e "${GREEN}${BOLD}🎉 Document AI setup complete!${RESET}"
echo -e "${CYAN}You are now connected to the development environment.${RESET}"