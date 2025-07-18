#!/bin/bash

# =====================================================
# Document AI Processing Script
# Complete Document Processing Workflow
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting Document AI processing workflow...${RESET}"

# =====================================================
# 1. PROCESSOR ID INPUT
# =====================================================
echo -e "${YELLOW}Step 1: Getting processor configuration...${RESET}"

# Get processor ID from user
read -p "${YELLOW}${BOLD}Enter the PROCESSOR_ID: ${RESET}" PROCESSOR_ID

if [ -z "$PROCESSOR_ID" ]; then
    echo -e "${RED}❌ Error: Processor ID cannot be empty${RESET}"
    exit 1
fi

echo -e "${GREEN}✅ Processor ID set: $PROCESSOR_ID${RESET}"

# =====================================================
# 2. INSTALL DEPENDENCIES
# =====================================================
echo -e "${YELLOW}Step 2: Installing required dependencies...${RESET}"

echo -e "${CYAN}Updating package list and installing jq, python3-pip...${RESET}"
sudo apt-get update && sudo apt-get install jq -y && sudo apt-get install python3-pip -y

echo -e "${GREEN}✅ Dependencies installed${RESET}"

# =====================================================
# 3. ENVIRONMENT SETUP
# =====================================================
echo -e "${YELLOW}Step 3: Setting up environment variables...${RESET}"

export PROJECT_ID=$(gcloud config get-value core/project)
export SA_NAME="document-ai-service-account"

echo -e "${GREEN}✅ Environment configured: $PROJECT_ID${RESET}"

# =====================================================
# 4. CREATE SERVICE ACCOUNT
# =====================================================
echo -e "${YELLOW}Step 4: Creating service account and credentials...${RESET}"

echo -e "${CYAN}Creating service account...${RESET}"
gcloud iam service-accounts create $SA_NAME --display-name $SA_NAME

echo -e "${CYAN}Adding IAM policy binding...${RESET}"
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:$SA_NAME@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/documentai.apiUser"

echo -e "${CYAN}Creating service account key...${RESET}"
gcloud iam service-accounts keys create key.json \
    --iam-account $SA_NAME@${PROJECT_ID}.iam.gserviceaccount.com

# Set credentials
export GOOGLE_APPLICATION_CREDENTIALS="$PWD/key.json"
echo -e "${GREEN}✅ Service account created: $GOOGLE_APPLICATION_CREDENTIALS${RESET}"

# =====================================================
# 5. DOWNLOAD SAMPLE DOCUMENT
# =====================================================
echo -e "${YELLOW}Step 5: Downloading sample document...${RESET}"

gsutil cp gs://cloud-training/gsp924/health-intake-form.pdf .

echo -e "${GREEN}✅ Sample document downloaded${RESET}"

# =====================================================
# 6. PREPARE API REQUEST
# =====================================================
echo -e "${YELLOW}Step 6: Preparing API request with base64 encoding...${RESET}"

echo -e "${CYAN}Creating JSON request payload...${RESET}"
echo '{"inlineDocument": {"mimeType": "application/pdf","content": "' > temp.json
base64 health-intake-form.pdf >> temp.json
echo '"}}' >> temp.json
cat temp.json | tr -d \\n > request.json

echo -e "${GREEN}✅ API request prepared${RESET}"

# =====================================================
# 7. FIRST API CALL
# =====================================================
echo -e "${YELLOW}Step 7: Making first API call to Document AI...${RESET}"

# Wait for service account propagation
echo -e "${CYAN}Waiting for service account propagation (65 seconds)...${RESET}"
for i in $(seq 65 -1 1); do
    echo -ne "\r${YELLOW}⏳ $i seconds remaining...${RESET}"
    sleep 1
done
echo -e "\r${GREEN}✅ Wait complete${RESET}                    "

export LOCATION="us"

echo -e "${CYAN}Processing document via REST API...${RESET}"
curl -X POST \
    -H "Authorization: Bearer "$(gcloud auth application-default print-access-token) \
    -H "Content-Type: application/json; charset=utf-8" \
    -d @request.json \
    https://${LOCATION}-documentai.googleapis.com/v1beta3/projects/${PROJECT_ID}/locations/${LOCATION}/processors/${PROCESSOR_ID}:process > output.json

echo -e "${GREEN}✅ First API call completed${RESET}"

# =====================================================
# 8. DISPLAY EXTRACTED TEXT
# =====================================================
echo -e "${YELLOW}Step 8: Displaying extracted text...${RESET}"

# Additional wait for processing
echo -e "${CYAN}Waiting for processing completion (65 seconds)...${RESET}"
for i in $(seq 65 -1 1); do
    echo -ne "\r${YELLOW}⏳ $i seconds remaining...${RESET}"
    sleep 1
done
echo -e "\r${GREEN}✅ Processing complete${RESET}                    "

echo -e "${CYAN}Extracted text from document:${RESET}"
echo -e "${BLUE}${BOLD}========================================${RESET}"
cat output.json | jq -r ".document.text"
echo -e "${BLUE}${BOLD}========================================${RESET}"

# =====================================================
# 9. PYTHON SDK PROCESSING
# =====================================================
echo -e "${YELLOW}Step 9: Processing with Python SDK...${RESET}"

echo -e "${CYAN}Downloading Python processing script...${RESET}"
gsutil cp gs://cloud-training/gsp924/synchronous_doc_ai.py .

echo -e "${CYAN}Installing Python dependencies...${RESET}"
python3 -m pip install --upgrade google-cloud-documentai google-cloud-storage prettytable

echo -e "${CYAN}Running Python Document AI processing...${RESET}"
export GOOGLE_APPLICATION_CREDENTIALS="$PWD/key.json"
python3 synchronous_doc_ai.py \
    --project_id=$PROJECT_ID \
    --processor_id=$PROCESSOR_ID \
    --location=us \
    --file_name=health-intake-form.pdf | tee results.txt

echo -e "${GREEN}✅ Python processing completed${RESET}"

# =====================================================
# 10. VERIFICATION API CALL
# =====================================================
echo -e "${YELLOW}Step 10: Making verification API call...${RESET}"

echo -e "${CYAN}Running final verification...${RESET}"
curl -X POST \
    -H "Authorization: Bearer "$(gcloud auth application-default print-access-token) \
    -H "Content-Type: application/json; charset=utf-8" \
    -d @request.json \
    https://${LOCATION}-documentai.googleapis.com/v1beta3/projects/${PROJECT_ID}/locations/${LOCATION}/processors/${PROCESSOR_ID}:process > output_final.json

echo -e "${GREEN}✅ Verification completed${RESET}"

echo -e "${GREEN}${BOLD}🎉 Document AI processing workflow complete!${RESET}"
echo -e "${CYAN}Generated files:${RESET}"
echo -e "${CYAN}  • output.json - First API response${RESET}"
echo -e "${CYAN}  • results.txt - Python processing results${RESET}"
echo -e "${CYAN}  • output_final.json - Final verification response${RESET}"