#!/bin/bash

# =====================================================
# Document AI Processing Script
# Complete Document Processing Workflow
# =====================================================

# Colors using tput (more compatible)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

echo "${BLUE}${BOLD}Starting Document AI processing workflow...${RESET}"

# =====================================================
# 1. PROCESSOR ID INPUT
# =====================================================
echo "${YELLOW}Step 1: Getting processor configuration...${RESET}"

# Get processor ID from user
read -p "${YELLOW}${BOLD}Enter the PROCESSOR_ID: ${RESET}" PROCESSOR_ID

if [ -z "$PROCESSOR_ID" ]; then
    echo "${RED}❌ Error: Processor ID cannot be empty${RESET}"
    exit 1
fi

echo "${GREEN}✅ Processor ID set: $PROCESSOR_ID${RESET}"

# =====================================================
# 2. INSTALL DEPENDENCIES
# =====================================================
echo "${YELLOW}Step 2: Installing required dependencies...${RESET}"

echo "${CYAN}Updating package list and installing jq, python3-pip...${RESET}"
sudo apt-get update && sudo apt-get install jq -y && sudo apt-get install python3-pip -y

echo "${GREEN}✅ Dependencies installed${RESET}"

# =====================================================
# 3. ENVIRONMENT SETUP
# =====================================================
echo "${YELLOW}Step 3: Setting up environment variables...${RESET}"

export PROJECT_ID=$(gcloud config get-value core/project)
export SA_NAME="document-ai-service-account"

echo "${GREEN}✅ Environment configured: $PROJECT_ID${RESET}"

# =====================================================
# 4. CREATE SERVICE ACCOUNT
# =====================================================
echo "${YELLOW}Step 4: Creating service account and credentials...${RESET}"

echo "${CYAN}Creating service account...${RESET}"
gcloud iam service-accounts create $SA_NAME --display-name $SA_NAME

echo "${CYAN}Adding IAM policy binding...${RESET}"
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:$SA_NAME@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/documentai.apiUser"

echo "${CYAN}Creating service account key...${RESET}"
gcloud iam service-accounts keys create key.json \
    --iam-account $SA_NAME@${PROJECT_ID}.iam.gserviceaccount.com

# Set credentials
export GOOGLE_APPLICATION_CREDENTIALS="$PWD/key.json"
echo "${GREEN}✅ Service account created: $GOOGLE_APPLICATION_CREDENTIALS${RESET}"

# =====================================================
# 5. DOWNLOAD SAMPLE DOCUMENT
# =====================================================
echo "${YELLOW}Step 5: Downloading sample document...${RESET}"

gsutil cp gs://cloud-training/gsp924/health-intake-form.pdf .

echo "${GREEN}✅ Sample document downloaded${RESET}"

# =====================================================
# 6. PREPARE API REQUEST
# =====================================================
echo "${YELLOW}Step 6: Preparing API request with base64 encoding...${RESET}"

echo "${CYAN}Creating JSON request payload...${RESET}"
echo '{"inlineDocument": {"mimeType": "application/pdf","content": "' > temp.json
base64 health-intake-form.pdf >> temp.json
echo '"}}' >> temp.json
cat temp.json | tr -d \\n > request.json

echo "${GREEN}✅ API request prepared${RESET}"

# =====================================================
# 7. FIRST API CALL
# =====================================================
echo "${YELLOW}Step 7: Making first API call to Document AI...${RESET}"

# Wait for service account propagation
echo "${CYAN}Waiting for service account propagation (65 seconds)...${RESET}"
for i in $(seq 65 -1 1); do
    echo -ne "\r${YELLOW}⏳ $i seconds remaining...${RESET}"
    sleep 1
done
echo "\r${GREEN}✅ Wait complete${RESET}                    "

export LOCATION="us"

echo "${CYAN}Processing document via REST API...${RESET}"
curl -X POST \
    -H "Authorization: Bearer "$(gcloud auth application-default print-access-token) \
    -H "Content-Type: application/json; charset=utf-8" \
    -d @request.json \
    https://${LOCATION}-documentai.googleapis.com/v1beta3/projects/${PROJECT_ID}/locations/${LOCATION}/processors/${PROCESSOR_ID}:process > output.json

echo "${GREEN}✅ First API call completed${RESET}"

# =====================================================
# 8. DISPLAY EXTRACTED TEXT
# =====================================================
echo "${YELLOW}Step 8: Displaying extracted text...${RESET}"

# Additional wait for processing
echo "${CYAN}Waiting for processing completion (65 seconds)...${RESET}"
for i in $(seq 65 -1 1); do
    echo -ne "\r${YELLOW}⏳ $i seconds remaining...${RESET}"
    sleep 1
done
echo "\r${GREEN}✅ Processing complete${RESET}                    "

echo "${CYAN}Extracted text from document:${RESET}"
echo "${BLUE}${BOLD}========================================${RESET}"
cat output.json | jq -r ".document.text"
echo "${BLUE}${BOLD}========================================${RESET}"

# =====================================================
# 9. PYTHON SDK PROCESSING
# =====================================================
echo "${YELLOW}Step 9: Processing with Python SDK...${RESET}"

echo "${CYAN}Downloading Python processing script...${RESET}"
gsutil cp gs://cloud-training/gsp924/synchronous_doc_ai.py .

echo "${CYAN}Installing Python dependencies...${RESET}"
python3 -m pip install --upgrade google-cloud-documentai google-cloud-storage prettytable

echo "${CYAN}Running Python Document AI processing...${RESET}"
export GOOGLE_APPLICATION_CREDENTIALS="$PWD/key.json"
python3 synchronous_doc_ai.py \
    --project_id=$PROJECT_ID \
    --processor_id=$PROCESSOR_ID \
    --location=us \
    --file_name=health-intake-form.pdf | tee results.txt

echo "${GREEN}✅ Python processing completed${RESET}"

# =====================================================
# 10. VERIFICATION API CALL
# =====================================================
echo "${YELLOW}Step 10: Making verification API call...${RESET}"

echo "${CYAN}Running final verification...${RESET}"
curl -X POST \
    -H "Authorization: Bearer "$(gcloud auth application-default print-access-token) \
    -H "Content-Type: application/json; charset=utf-8" \
    -d @request.json \
    https://${LOCATION}-documentai.googleapis.com/v1beta3/projects/${PROJECT_ID}/locations/${LOCATION}/processors/${PROCESSOR_ID}:process > output_final.json

echo "${GREEN}✅ Verification completed${RESET}"

echo "${GREEN}${BOLD}🎉 Document AI processing workflow complete!${RESET}"
echo "${CYAN}Generated files:${RESET}"
echo "${CYAN}  • output.json - First API response${RESET}"
echo "${CYAN}  • results.txt - Python processing results${RESET}"
echo "${CYAN}  • output_final.json - Final verification response${RESET}"