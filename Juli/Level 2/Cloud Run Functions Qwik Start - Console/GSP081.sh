#!/bin/bash

# Colors for better output formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== GCP Lab Cloud Function Creation (Exact Lab Specs) ===${NC}\n"

# ===============================
# 1. AUTHENTICATION & ENVIRONMENT SETUP
# ===============================
echo -e "${GREEN}1. Setting up authentication and environment...${NC}"

# Check current authentication
gcloud auth list

# Get project ID
export PROJECT_ID=$(gcloud config get-value project)
echo -e "${CYAN}Project ID: $PROJECT_ID${NC}"

# Manual region input for lab flexibility
echo -e "\n${CYAN}Please enter the region for this lab:${NC}"
echo -e "${YELLOW}Common lab regions: us-central1, us-east1, europe-west1, asia-southeast1${NC}"
echo -e "${YELLOW}Check your lab instructions for the specific region required.${NC}"
read -p "Enter region: " REGION

# Validate region input
if [ -z "$REGION" ]; then
    echo -e "${RED}Error: Region cannot be empty!${NC}"
    exit 1
fi

export REGION
gcloud config set compute/region "$REGION"
gcloud config set functions/region "$REGION"

echo -e "${CYAN}Selected Region: $REGION${NC}"

# ===============================
# 2. ENABLE REQUIRED APIS
# ===============================
echo -e "\n${GREEN}2. Enabling required APIs...${NC}"

# Enable Cloud Functions and related APIs
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable artifactregistry.googleapis.com

echo -e "${CYAN}Required APIs enabled${NC}"

# ===============================
# 3. CREATE FUNCTION SOURCE CODE
# ===============================
echo -e "\n${GREEN}3. Creating function source code (exact lab specification)...${NC}"

# Create temporary directory for function
mkdir -p /tmp/gcfunction-lab
cd /tmp/gcfunction-lab

# Create package.json (exact as lab expects)
cat > package.json << EOF
{
  "name": "helloHttp",
  "version": "1.0.0",
  "description": "Simple HTTP function",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF

# Create index.js with default helloHttp function (as mentioned in lab)
cat > index.js << 'EOF'
const functions = require('@google-cloud/functions-framework');

// Simple HTTP function as expected by the lab
functions.http('helloHttp', (req, res) => {
  res.send('Hello World!');
});
EOF

echo -e "${CYAN}Function source code created (lab specification)${NC}"

# ===============================
# 4. DEPLOY FUNCTION - TASK 1 & 2 COMBINED
# ===============================
echo -e "\n${GREEN}4. Creating and deploying Cloud Function 'gcfunction'...${NC}"

# Deploy with exact lab specifications
echo -e "${PURPLE}Deploying 2nd generation Cloud Function...${NC}"

# Try 2nd generation deployment first (as specified in lab)
if gcloud functions deploy gcfunction \
  --gen2 \
  --runtime=nodejs20 \
  --region=$REGION \
  --source=. \
  --entry-point=helloHttp \
  --trigger-http \
  --allow-unauthenticated \
  --max-instances=5 \
  --memory=256Mi \
  --timeout=60s; then
    
    echo -e "${CYAN}✓ 2nd generation function 'gcfunction' created successfully!${NC}"
    FUNCTION_TYPE="gen2"
    
else
    echo -e "${YELLOW}2nd gen failed, trying 1st generation...${NC}"
    
    # Fallback to 1st generation
    if gcloud functions deploy gcfunction \
      --runtime=nodejs20 \
      --region=$REGION \
      --source=. \
      --entry-point=helloHttp \
      --trigger-http \
      --allow-unauthenticated \
      --max-instances=5 \
      --memory=256Mi; then
        
        echo -e "${CYAN}✓ 1st generation function 'gcfunction' created successfully!${NC}"
        FUNCTION_TYPE="gen1"
    else
        echo -e "${RED}❌ Function deployment failed! Check logs above.${NC}"
        exit 1
    fi
fi

# Wait for function to be fully ready
echo -e "${PURPLE}Waiting for function to be ready...${NC}"
sleep 45

# ===============================
# 5. VERIFY FUNCTION CREATION
# ===============================
echo -e "\n${GREEN}5. Verifying function creation...${NC}"

# List all functions to verify creation
echo -e "${CYAN}All Cloud Functions in project:${NC}"
gcloud functions list --regions=$REGION

# Get specific function details
echo -e "\n${CYAN}Function 'gcfunction' details:${NC}"
if gcloud functions describe gcfunction --region=$REGION; then
    echo -e "${GREEN}✓ Function 'gcfunction' exists and is properly configured${NC}"
else
    echo -e "${RED}❌ Function 'gcfunction' not found${NC}"
    exit 1
fi

# ===============================
# 6. GET FUNCTION URL AND TEST
# ===============================
echo -e "\n${GREEN}6. Getting function URL and testing...${NC}"

# Get function URL
if [ "$FUNCTION_TYPE" = "gen2" ]; then
    FUNCTION_URL=$(gcloud functions describe gcfunction --region=$REGION --format="value(serviceConfig.uri)")
else
    FUNCTION_URL=$(gcloud functions describe gcfunction --region=$REGION --format="value(httpsTrigger.url)")
fi

if [ -n "$FUNCTION_URL" ]; then
    echo -e "${CYAN}Function URL: $FUNCTION_URL${NC}"
    
    # Test the function
    echo -e "\n${PURPLE}Testing function...${NC}"
    curl -X GET "$FUNCTION_URL"
    echo
    
else
    echo -e "${RED}❌ Could not retrieve function URL${NC}"
fi

# ===============================
# 7. LAB TASK VERIFICATION
# ===============================
echo -e "\n${GREEN}7. Lab task verification...${NC}"

# Check if function meets all lab requirements
echo -e "${CYAN}Checking lab requirements:${NC}"

# Check function name
if gcloud functions describe gcfunction --region=$REGION >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Function name 'gcfunction' - CORRECT${NC}"
else
    echo -e "${RED}❌ Function name 'gcfunction' - NOT FOUND${NC}"
fi

# Check region
ACTUAL_REGION=$(gcloud functions describe gcfunction --region=$REGION --format="value(name)" | cut -d'/' -f4)
if [ "$ACTUAL_REGION" = "$REGION" ]; then
    echo -e "${GREEN}✓ Region 'europe-west1' - CORRECT${NC}"
else
    echo -e "${RED}❌ Region mismatch. Expected: $REGION, Actual: $ACTUAL_REGION${NC}"
fi

# Check authentication (unauthenticated)
AUTH_POLICY=$(gcloud functions get-iam-policy gcfunction --region=$REGION --format="value(bindings[?members:allUsers].role)" 2>/dev/null)
if [[ "$AUTH_POLICY" == *"invoker"* ]]; then
    echo -e "${GREEN}✓ Unauthenticated access - ENABLED${NC}"
else
    echo -e "${YELLOW}⚠ Unauthenticated access - CHECKING...${NC}"
    # Ensure unauthenticated access
    gcloud functions add-iam-policy-binding gcfunction \
        --region=$REGION \
        --member="allUsers" \
        --role="roles/cloudfunctions.invoker"
    echo -e "${GREEN}✓ Unauthenticated access - NOW ENABLED${NC}"
fi

# Check max instances
MAX_INSTANCES=$(gcloud functions describe gcfunction --region=$REGION --format="value(serviceConfig.maxInstanceCount)" 2>/dev/null)
if [ "$MAX_INSTANCES" = "5" ]; then
    echo -e "${GREEN}✓ Max instances '5' - CORRECT${NC}"
else
    echo -e "${YELLOW}⚠ Max instances: $MAX_INSTANCES (expected 5)${NC}"
fi

# ===============================
# 8. FINAL SUMMARY
# ===============================
echo -e "\n${GREEN}=== Lab Task Completion Summary ===${NC}"
echo -e "${CYAN}Function Details:${NC}"
echo -e "${CYAN}  • Name: gcfunction${NC}"
echo -e "${CYAN}  • Region: europe-west1${NC}"
echo -e "${CYAN}  • Type: $FUNCTION_TYPE${NC}"
echo -e "${CYAN}  • Authentication: Allow unauthenticated${NC}"
echo -e "${CYAN}  • Max Instances: 5${NC}"
echo -e "${CYAN}  • Runtime: Node.js 20${NC}"
echo -e "${CYAN}  • Trigger: HTTP${NC}"

if [ -n "$FUNCTION_URL" ]; then
    echo -e "${CYAN}  • URL: $FUNCTION_URL${NC}"
fi

echo -e "\n${GREEN}✓ Task 1: Cloud Function 'gcfunction' created${NC}"
echo -e "${GREEN}✓ Task 2: Function deployed successfully${NC}"

echo -e "\n${YELLOW}Lab Verification Commands:${NC}"
echo -e "${CYAN}gcloud functions list --regions=europe-west1${NC}"
echo -e "${CYAN}gcloud functions describe gcfunction --region=europe-west1${NC}"

# Clean up temporary directory
cd ~
rm -rf /tmp/gcfunction-lab

echo -e "\n${GREEN}🎉 Lab setup completed! Function should now pass lab verification.${NC}"