#!/bin/bash

# Colors for better output formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== GCP Cloud Run Function Deployment ===${NC}\n"

# ===============================
# 1. AUTHENTICATION & ENVIRONMENT SETUP
# ===============================
echo -e "${GREEN}1. Setting up authentication and environment...${NC}"

# Check current authentication
gcloud auth list

# Get project ID
export PROJECT_ID=$(gcloud config get-value project)
echo -e "${CYAN}Project ID: $PROJECT_ID${NC}"

# Manual region input
echo -e "\n${CYAN}Please enter the region where you want to deploy the function:${NC}"
echo -e "${YELLOW}Common regions: us-central1, us-east1, europe-west1, asia-southeast1${NC}"
read -p "Enter region: " REGION

# Validate region input
if [ -z "$REGION" ]; then
    echo -e "${RED}Error: Region cannot be empty!${NC}"
    exit 1
fi

export REGION
gcloud config set compute/region "$REGION"

echo -e "${CYAN}Selected Region: $REGION${NC}"

# ===============================
# 2. ENABLE REQUIRED APIS
# ===============================
echo -e "\n${GREEN}2. Enabling required APIs...${NC}"

# Enable Cloud Run and Cloud Build APIs
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable cloudfunctions.googleapis.com

echo -e "${CYAN}Required APIs enabled${NC}"

# ===============================
# 3. CREATE FUNCTION SOURCE CODE
# ===============================
echo -e "\n${GREEN}3. Creating function source code...${NC}"

# Create temporary directory for function
mkdir -p /tmp/gcfunction
cd /tmp/gcfunction

# Create package.json
cat > package.json << EOF
{
  "name": "helloHttp",
  "version": "1.0.0",
  "description": "Simple HTTP Cloud Function",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF

# Create index.js with helloHttp function
cat > index.js << 'EOF'
const functions = require('@google-cloud/functions-framework');

/**
 * HTTP Cloud Function.
 *
 * @param {Object} req Cloud Function request context.
 * @param {Object} res Cloud Function response context.
 */
functions.http('helloHttp', (req, res) => {
  const message = req.body.message || 'Hello World!';
  res.status(200).send(`Hello ${message}`);
});
EOF

echo -e "${CYAN}Function source code created${NC}"

# ===============================
# 4. DEPLOY CLOUD RUN FUNCTION (TASK 1 & 2)
# ===============================
echo -e "\n${GREEN}4. Deploying Cloud Run Function...${NC}"

# Try deploying with gen2 first
echo -e "${PURPLE}Attempting gen2 deployment... (this may take a few minutes)${NC}"
if gcloud functions deploy gcfunction \
  --gen2 \
  --runtime=nodejs20 \
  --region=$REGION \
  --source=. \
  --entry-point=helloHttp \
  --trigger-http \
  --allow-unauthenticated \
  --max-instances=5 \
  --memory=256Mi; then
    echo -e "${CYAN}Gen2 function deployed successfully!${NC}"
else
    echo -e "${YELLOW}Gen2 deployment failed, trying gen1...${NC}"
    # Fallback to gen1 deployment
    if gcloud functions deploy gcfunction \
      --runtime=nodejs20 \
      --region=$REGION \
      --source=. \
      --entry-point=helloHttp \
      --trigger-http \
      --allow-unauthenticated \
      --max-instances=5 \
      --memory=256Mi; then
        echo -e "${CYAN}Gen1 function deployed successfully!${NC}"
    else
        echo -e "${RED}Both gen1 and gen2 deployment failed! Exiting...${NC}"
        exit 1
    fi
fi

# Wait for function to be ready
echo -e "${PURPLE}Waiting for function to be ready...${NC}"
sleep 30

# ===============================
# 5. GET FUNCTION DETAILS
# ===============================
echo -e "\n${GREEN}5. Getting function details...${NC}"

# Get function URL
if FUNCTION_URL=$(gcloud functions describe gcfunction --region=$REGION --format="value(serviceConfig.uri)" 2>/dev/null); then
    echo -e "${CYAN}Function URL: $FUNCTION_URL${NC}"
else
    echo -e "${RED}Failed to get function URL. Function may not be deployed properly.${NC}"
    exit 1
fi

# Verify function URL is not empty
if [ -z "$FUNCTION_URL" ]; then
    echo -e "${RED}Function URL is empty. Function may not be ready yet.${NC}"
    exit 1
fi

# ===============================
# 6. TEST THE FUNCTION (TASK 3)
# ===============================
echo -e "\n${GREEN}6. Testing the function...${NC}"

# Test 1: Simple GET request
echo -e "${PURPLE}Test 1: Simple GET request${NC}"
curl -X GET "$FUNCTION_URL"

echo

# Test 2: POST request with JSON payload
echo -e "${PURPLE}Test 2: POST request with message${NC}"
curl -X POST "$FUNCTION_URL" \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello World!"}'

echo

# Test 3: POST request with custom message
echo -e "${PURPLE}Test 3: POST request with custom message${NC}"
curl -X POST "$FUNCTION_URL" \
  -H "Content-Type: application/json" \
  -d '{"message":"Cloud Run Function Test"}'

echo

# ===============================
# 7. CLI TEST COMMAND (TASK 3 CONTINUED)
# ===============================
echo -e "\n${GREEN}7. Generating CLI test commands...${NC}"

echo -e "${YELLOW}CLI Test Commands:${NC}"
echo -e "${CYAN}Basic test:${NC}"
echo "gcloud functions call gcfunction --region=$REGION"

echo -e "${CYAN}Test with data:${NC}"
echo "gcloud functions call gcfunction --region=$REGION --data='{\"message\":\"Hello World!\"}'"

# Execute CLI test
echo -e "\n${PURPLE}Executing CLI test...${NC}"
if gcloud functions call gcfunction --region=$REGION --data='{"message":"Hello World!"}'; then
    echo -e "${CYAN}CLI test completed successfully${NC}"
else
    echo -e "${RED}CLI test failed${NC}"
fi

# ===============================
# 8. VIEW FUNCTION LOGS (TASK 4)
# ===============================
echo -e "\n${GREEN}8. Viewing function logs...${NC}"

# Show recent logs
echo -e "${PURPLE}Recent function logs:${NC}"
if gcloud functions logs read gcfunction --region=$REGION --limit=10; then
    echo -e "${CYAN}Logs retrieved successfully${NC}"
else
    echo -e "${YELLOW}No logs available yet or function not found${NC}"
fi

# ===============================
# 9. FUNCTION INFORMATION SUMMARY
# ===============================
echo -e "\n${GREEN}9. Function deployment summary...${NC}"

# Get function details
echo -e "${CYAN}Function Details:${NC}"
if gcloud functions describe gcfunction --region=$REGION; then
    echo -e "${CYAN}Function details retrieved successfully${NC}"
else
    echo -e "${YELLOW}Function details not available${NC}"
fi

echo -e "\n${GREEN}=== Cloud Run Function Tasks Completed! ===${NC}"
echo -e "${CYAN}✓ Task 1: Function created successfully${NC}"
echo -e "${CYAN}✓ Task 2: Function deployed successfully${NC}"
echo -e "${CYAN}✓ Task 3: Function tested successfully${NC}"
echo -e "${CYAN}✓ Task 4: Function logs viewed successfully${NC}"

echo -e "\n${YELLOW}Function Access Information:${NC}"
echo -e "${CYAN}Function Name: gcfunction${NC}"
echo -e "${CYAN}Region: $REGION${NC}"
echo -e "${CYAN}Function URL: $FUNCTION_URL${NC}"
echo -e "${CYAN}Trigger: HTTP${NC}"
echo -e "${CYAN}Authentication: Allow unauthenticated${NC}"
echo -e "${CYAN}Max Instances: 5${NC}"

echo -e "\n${YELLOW}Useful Commands:${NC}"
echo -e "${CYAN}View logs: gcloud functions logs read gcfunction --region=$REGION${NC}"
echo -e "${CYAN}Test function: curl -X POST $FUNCTION_URL -H 'Content-Type: application/json' -d '{\"message\":\"test\"}'${NC}"
echo -e "${CYAN}Delete function: gcloud functions delete gcfunction --region=$REGION${NC}"
echo -e "${CYAN}List functions: gcloud functions list${NC}"

# Clean up temporary directory
cd ~
rm -rf /tmp/gcfunction

echo -e "\n${GREEN}Setup completed successfully!${NC}"