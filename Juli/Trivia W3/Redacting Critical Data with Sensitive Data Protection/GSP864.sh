#!/bin/bash

# =====================================================
# Google Cloud DLP (Data Loss Prevention) Operations
# Complete Demo Script with Inspection, De-identification, and Redaction
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting Google Cloud DLP operations demo...${RESET}"

# =====================================================
# 1. AUTHENTICATION & ENVIRONMENT SETUP
# =====================================================
echo -e "${YELLOW}Step 1: Setting up authentication and environment...${RESET}"

# Check current authentication
gcloud auth list

# Set up environment variables
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export BUCKET_NAME=$DEVSHELL_PROJECT_ID-bucket
export PROJECT_ID=$DEVSHELL_PROJECT_ID

# Configure gcloud project
gcloud config set project $DEVSHELL_PROJECT_ID

echo -e "${GREEN}✅ Environment configured: $PROJECT_ID | $REGION | $ZONE${RESET}"

# =====================================================
# 2. CLONE DLP SAMPLES REPOSITORY
# =====================================================
echo -e "${YELLOW}Step 2: Cloning DLP samples repository...${RESET}"

echo -e "${CYAN}Cloning synthtool repository...${RESET}"
git clone https://github.com/googleapis/synthtool

echo -e "${CYAN}Installing npm dependencies...${RESET}"
cd synthtool/tests/fixtures/nodejs-dlp/samples/ && npm install

echo -e "${GREEN}✅ Repository cloned and dependencies installed${RESET}"

# =====================================================
# 3. ENABLE REQUIRED SERVICES
# =====================================================
echo -e "${YELLOW}Step 3: Enabling required Google Cloud services...${RESET}"

gcloud services enable \
  dlp.googleapis.com \
  cloudkms.googleapis.com \
  --project=$DEVSHELL_PROJECT_ID

echo -e "${GREEN}✅ DLP and Cloud KMS services enabled${RESET}"

# =====================================================
# 4. STRING INSPECTION
# =====================================================
echo -e "${YELLOW}Step 4: Performing DLP string inspection...${RESET}"

echo -e "${CYAN}Inspecting string for sensitive data...${RESET}"
node inspectString.js $PROJECT_ID "My email address is jenny@somedomain.com and you can call me at 555-867-5309" > inspected-string.txt

echo -e "${CYAN}String inspection results saved to inspected-string.txt${RESET}"
echo -e "${GREEN}✅ String inspection completed${RESET}"

# =====================================================
# 5. FILE INSPECTION
# =====================================================
echo -e "${YELLOW}Step 5: Performing DLP file inspection...${RESET}"

echo -e "${CYAN}Inspecting file for sensitive data...${RESET}"
node inspectFile.js $PROJECT_ID resources/accounts.txt > inspected-file.txt

echo -e "${CYAN}File inspection results saved to inspected-file.txt${RESET}"
echo -e "${GREEN}✅ File inspection completed${RESET}"

# =====================================================
# 6. UPLOAD INSPECTION RESULTS
# =====================================================
echo -e "${YELLOW}Step 6: Uploading inspection results to Cloud Storage...${RESET}"

echo -e "${CYAN}Uploading inspected-string.txt...${RESET}"
gsutil cp inspected-string.txt gs://$BUCKET_NAME

echo -e "${CYAN}Uploading inspected-file.txt...${RESET}"
gsutil cp inspected-file.txt gs://$BUCKET_NAME

echo -e "${GREEN}✅ Inspection results uploaded${RESET}"

# =====================================================
# 7. DE-IDENTIFICATION WITH MASKING
# =====================================================
echo -e "${YELLOW}Step 7: Performing de-identification with masking...${RESET}"

echo -e "${CYAN}De-identifying sensitive data with masking...${RESET}"
node deidentifyWithMask.js $PROJECT_ID "My order number is F12312399. Email me at anthony@somedomain.com" > de-identify-output.txt

echo -e "${CYAN}Uploading de-identification results...${RESET}"
gsutil cp de-identify-output.txt gs://$BUCKET_NAME

echo -e "${GREEN}✅ De-identification completed and uploaded${RESET}"

# =====================================================
# 8. TEXT REDACTION
# =====================================================
echo -e "${YELLOW}Step 8: Performing text redaction...${RESET}"

echo -e "${CYAN}Redacting credit card number from text...${RESET}"
node redactText.js $PROJECT_ID "Please refund the purchase to my credit card 4012888888881881" CREDIT_CARD_NUMBER > redacted-string.txt

echo -e "${CYAN}Uploading redacted text results...${RESET}"
gsutil cp redacted-string.txt gs://$BUCKET_NAME

echo -e "${GREEN}✅ Text redaction completed and uploaded${RESET}"

# =====================================================
# 9. IMAGE REDACTION
# =====================================================
echo -e "${YELLOW}Step 9: Performing image redaction...${RESET}"

echo -e "${CYAN}Redacting phone numbers from image...${RESET}"
node redactImage.js $PROJECT_ID resources/test.png "" PHONE_NUMBER ./redacted-phone.png

echo -e "${CYAN}Redacting email addresses from image...${RESET}"
node redactImage.js $PROJECT_ID resources/test.png "" EMAIL_ADDRESS ./redacted-email.png

echo -e "${GREEN}✅ Image redaction completed${RESET}"

# =====================================================
# 10. UPLOAD REDACTED IMAGES
# =====================================================
echo -e "${YELLOW}Step 10: Uploading redacted images to Cloud Storage...${RESET}"

echo -e "${CYAN}Uploading redacted-phone.png...${RESET}"
gsutil cp redacted-phone.png gs://$BUCKET_NAME

echo -e "${CYAN}Uploading redacted-email.png...${RESET}"
gsutil cp redacted-email.png gs://$BUCKET_NAME

echo -e "${GREEN}✅ Redacted images uploaded${RESET}"

echo -e "${GREEN}${BOLD}🎉 Complete! All DLP operations finished successfully.${RESET}"
echo -e "${CYAN}Generated files:${RESET}"
echo -e "${CYAN}  - inspected-string.txt (string inspection results)${RESET}"
echo -e "${CYAN}  - inspected-file.txt (file inspection results)${RESET}"
echo -e "${CYAN}  - de-identify-output.txt (de-identification results)${RESET}"
echo -e "${CYAN}  - redacted-string.txt (text redaction results)${RESET}"
echo -e "${CYAN}  - redacted-phone.png (image with phone numbers redacted)${RESET}"
echo -e "${CYAN}  - redacted-email.png (image with emails redacted)${RESET}"
echo -e "${CYAN}Cloud Storage bucket: gs://$BUCKET_NAME${RESET}"