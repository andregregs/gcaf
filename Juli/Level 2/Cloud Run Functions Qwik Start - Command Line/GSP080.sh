#!/bin/bash

# Colors for better output formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== GCP Pub/Sub Cloud Function Deployment ===${NC}\n"

# ===============================
# 1. AUTHENTICATION & ENVIRONMENT SETUP
# ===============================
echo -e "${GREEN}1. Setting up authentication and environment...${NC}"

# Check current authentication
gcloud auth list

# Export environment variables
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_ID=$DEVSHELL_PROJECT_ID

# Set project configuration
gcloud config set project $DEVSHELL_PROJECT_ID
gcloud config set compute/region $REGION

echo -e "${CYAN}Zone: $ZONE${NC}"
echo -e "${CYAN}Region: $REGION${NC}"
echo -e "${CYAN}Project ID: $PROJECT_ID${NC}"

# ===============================
# 2. ENABLE CLOUD FUNCTIONS API
# ===============================
echo -e "\n${GREEN}2. Configuring Cloud Functions API...${NC}"

# Disable and re-enable Cloud Functions API to refresh
gcloud services disable cloudfunctions.googleapis.com --project=$DEVSHELL_PROJECT_ID
gcloud services enable cloudfunctions.googleapis.com --project=$DEVSHELL_PROJECT_ID

echo -e "${CYAN}Cloud Functions API configured${NC}"

# ===============================
# 3. CREATE FUNCTION SOURCE CODE
# ===============================
echo -e "\n${GREEN}3. Creating function source code...${NC}"

# Create project directory
mkdir -p gcf_hello_world
cd gcf_hello_world

# Create index.js with Pub/Sub function
cat > index.js <<'EOF'
const functions = require('@google-cloud/functions-framework');

// Register a CloudEvent callback with the Functions Framework that will
// be executed when the Pub/Sub trigger topic receives a message.
functions.cloudEvent('helloPubSub', cloudEvent => {
  // The Pub/Sub message is passed as the CloudEvent's data payload.
  const base64name = cloudEvent.data.message.data;
  const name = base64name
    ? Buffer.from(base64name, 'base64').toString()
    : 'World';
  console.log(`Hello, ${name}!`);
});
EOF

# Create package.json
cat > package.json <<'EOF'
{
  "name": "gcf_hello_world",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF

echo -e "${CYAN}Function source code created${NC}"

# ===============================
# 4. CONFIGURE IAM PERMISSIONS
# ===============================
echo -e "\n${GREEN}4. Configuring IAM permissions...${NC}"

# Add IAM policy binding for artifact registry
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
  --member="serviceAccount:$DEVSHELL_PROJECT_ID@appspot.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"

echo -e "${CYAN}IAM permissions configured${NC}"

# ===============================
# 5. DEPLOY FUNCTION WITH RETRY LOGIC
# ===============================
echo -e "\n${GREEN}5. Deploying Cloud Function with Pub/Sub trigger...${NC}"

# Function to deploy the Cloud Function
deploy_function() {
  echo -e "${PURPLE}Attempting to deploy function...${NC}"
  gcloud functions deploy nodejs-pubsub-function \
    --gen2 \
    --runtime=nodejs20 \
    --region=$REGION \
    --source=. \
    --entry-point=helloPubSub \
    --trigger-topic cf-demo \
    --stage-bucket $DEVSHELL_PROJECT_ID-bucket \
    --service-account cloudfunctionsa@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com \
    --allow-unauthenticated \
    --quiet
}

# Deploy with retry logic
deploy_success=false
attempt=1
max_attempts=5

while [ "$deploy_success" = false ] && [ $attempt -le $max_attempts ]; do
  echo -e "${PURPLE}Deployment attempt $attempt/$max_attempts${NC}"
  
  if deploy_function; then
    echo -e "${GREEN}✓ Function deployed successfully!${NC}"
    deploy_success=true
  else
    echo -e "${YELLOW}⚠ Deployment failed. Retrying in 30 seconds...${NC}"
    sleep 30
    ((attempt++))
  fi
done

if [ "$deploy_success" = false ]; then
  echo -e "${RED}❌ Function deployment failed after $max_attempts attempts${NC}"
  exit 1
fi

# ===============================
# 6. VERIFY FUNCTION DEPLOYMENT
# ===============================
echo -e "\n${GREEN}6. Verifying function deployment...${NC}"

# Describe the deployed function
echo -e "${CYAN}Function details:${NC}"
gcloud functions describe nodejs-pubsub-function --region=$REGION

# ===============================
# 7. FUNCTION TESTING COMMANDS
# ===============================
echo -e "\n${GREEN}7. Function testing information...${NC}"

echo -e "${CYAN}Function deployed successfully with the following configuration:${NC}"
echo -e "${CYAN}  • Name: nodejs-pubsub-function${NC}"
echo -e "${CYAN}  • Region: $REGION${NC}"
echo -e "${CYAN}  • Runtime: Node.js 20${NC}"
echo -e "${CYAN}  • Trigger: Pub/Sub topic 'cf-demo'${NC}"
echo -e "${CYAN}  • Entry Point: helloPubSub${NC}"
echo -e "${CYAN}  • Generation: 2nd generation${NC}"

echo -e "\n${YELLOW}Testing Commands:${NC}"
echo -e "${CYAN}1. Test with gcloud:${NC}"
echo -e "   gcloud pubsub topics publish cf-demo --message='Hello Cloud Function!'"
echo -e "${CYAN}2. View function logs:${NC}"
echo -e "   gcloud functions logs read nodejs-pubsub-function --region=$REGION"
echo -e "${CYAN}3. List all functions:${NC}"
echo -e "   gcloud functions list --regions=$REGION"

echo -e "\n${GREEN}=== Pub/Sub Cloud Function Deployment Completed! ===${NC}"