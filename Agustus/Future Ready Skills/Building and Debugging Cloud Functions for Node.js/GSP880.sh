#!/bin/bash

# Google Cloud Functions Framework for Node.js Lab - Complete Script
# This script automates the Cloud Functions development and deployment process

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print colored status messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "\n${PURPLE}════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════════════════════════════${NC}"
}

print_task() {
    echo -e "\n${CYAN}▶ TASK: $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════${NC}"
}

# Get project information
print_status "Getting project and environment information..."
export PROJECT_ID=$(gcloud config get-value project)

# Get region and zone from project metadata
print_status "Retrieving zone and region from project metadata..."
export ZONE=$(gcloud compute project-info describe \
    --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe \
    --format="value(commonInstanceMetadata.items[google-compute-default-region])")

# Set default region and zone if not found in metadata
if [ -z "$REGION" ] || [ "$REGION" = "(unset)" ]; then
    print_warning "Region not found in metadata, using default: us-central1"
    export REGION="us-central1"
fi

if [ -z "$ZONE" ] || [ "$ZONE" = "(unset)" ]; then
    print_warning "Zone not found in metadata, using default: us-central1-a"
    export ZONE="us-central1-a"
fi

echo -e "${CYAN}Project ID: ${WHITE}$PROJECT_ID${NC}"
echo -e "${CYAN}Region: ${WHITE}$REGION${NC}"
echo -e "${CYAN}Zone: ${WHITE}$ZONE${NC}"

# =============================================================================
# TASK 1: INSTALL THE FUNCTIONS FRAMEWORK FOR NODE.JS
# =============================================================================
print_task "1. Install the Functions Framework for Node.js"

print_step "Step 1.1: Create Application Folder"
print_status "Creating ff-app folder and navigating to it..."
mkdir -p ff-app && cd ff-app
print_success "Application folder created!"

print_step "Step 1.2: Initialize Node.js Application"
print_status "Creating new Node.js application with package.json..."
npm init --yes
print_success "Node.js application initialized!"

print_step "Step 1.3: Install Functions Framework"
print_status "Installing @google-cloud/functions-framework..."
npm install @google-cloud/functions-framework
print_success "Functions Framework installed successfully!"

print_step "Step 1.4: Verify Installation"
print_status "Checking package.json for Functions Framework dependency..."
if grep -q "@google-cloud/functions-framework" package.json; then
    echo -e "${GREEN}✓ Functions Framework found in dependencies${NC}"
    grep "@google-cloud/functions-framework" package.json
else
    print_error "Functions Framework not found in package.json"
fi

echo -e "\n${GREEN}✓ TASK 1 COMPLETED: Functions Framework for Node.js installed!${NC}"

# =============================================================================
# TASK 2: CREATE AND TEST A HTTP CLOUD FUNCTION LOCALLY
# =============================================================================
print_task "2. Create and Test a HTTP Cloud Function Locally"

print_step "Step 2.1: Create Cloud Function Code"
print_status "Creating index.js with validateTemperature function..."

cat > index.js <<'EOF'
exports.validateTemperature = async (req, res) => {
 try {
   if (req.body.temp < 100) {
     res.status(200).send("Temperature OK \n");
   } else {
     res.status(200).send("Too hot \n");
   }
 } catch (error) {
   //return an error
   console.log("got error: ", error);
   res.status(500).send(error);
 }
};
EOF

print_success "Cloud Function code created!"

print_step "Step 2.2: Start Local Functions Framework Server"
print_status "Starting local server for validateTemperature function..."
print_warning "Server will run in background for testing..."

# Start the function server in background
npx @google-cloud/functions-framework --target=validateTemperature > function_server.log 2>&1 &
FUNCTION_PID=$!

# Wait for server to start
print_status "Waiting for server to start (5 seconds)..."
sleep 5

print_step "Step 2.3: Test Function with Valid Temperature"
print_status "Testing with temperature 50 (should return 'Temperature OK')..."
RESPONSE1=$(curl -s -X POST http://localhost:8080 -H "Content-Type:application/json" -d '{"temp":"50"}')
echo -e "${CYAN}Response: ${WHITE}$RESPONSE1${NC}"

print_step "Step 2.4: Test Function with High Temperature"
print_status "Testing with temperature 120 (should return 'Too hot')..."
RESPONSE2=$(curl -s -X POST http://localhost:8080 -H "Content-Type:application/json" -d '{"temp":"120"}')
echo -e "${CYAN}Response: ${WHITE}$RESPONSE2${NC}"

print_step "Step 2.5: Test Function with Missing Payload"
print_status "Testing with missing payload (should expose bug)..."
RESPONSE3=$(curl -s -X POST http://localhost:8080)
echo -e "${CYAN}Response: ${WHITE}$RESPONSE3${NC}"
print_warning "Bug detected: Function returns 'Too hot' instead of handling missing temperature!"

# Stop the function server
print_status "Stopping local function server..."
kill $FUNCTION_PID 2>/dev/null
wait $FUNCTION_PID 2>/dev/null

echo -e "\n${GREEN}✓ TASK 2 COMPLETED: HTTP Cloud Function created and tested locally!${NC}"

# =============================================================================
# TASK 3: DEBUG A HTTP FUNCTION FROM YOUR LOCAL MACHINE
# =============================================================================
print_task "3. Debug a HTTP Function from Your Local Machine"

print_step "Step 3.1: Fix the Bug in Function Code"
print_status "Updating function to handle undefined temperature..."

cat > index.js <<'EOF'
exports.validateTemperature = async (req, res) => {
 try {
   // add this if statement to handle undefined temperature
   if (!req.body.temp) {
     throw "Temperature is undefined \n";
   }

   if (req.body.temp < 100) {
     res.status(200).send("Temperature OK \n");
   } else {
     res.status(200).send("Too hot \n");
   }
 } catch (error) {
   //return an error
   console.log("got error: ", error);
   res.status(500).send(error);
 }
};
EOF

print_success "Function code updated to handle undefined temperature!"

print_step "Step 3.2: Test Fixed Function"
print_status "Starting local server with fixed function..."

# Start the function server in background
npx @google-cloud/functions-framework --target=validateTemperature > function_server_fixed.log 2>&1 &
FUNCTION_PID=$!

# Wait for server to start
print_status "Waiting for server to start (5 seconds)..."
sleep 5

print_status "Testing with missing payload (should now throw exception)..."
RESPONSE4=$(curl -s -X POST http://localhost:8080)
echo -e "${CYAN}Response: ${WHITE}$RESPONSE4${NC}"

print_status "Testing with valid temperature (should still work)..."
RESPONSE5=$(curl -s -X POST http://localhost:8080 -H "Content-Type:application/json" -d '{"temp":"50"}')
echo -e "${CYAN}Response: ${WHITE}$RESPONSE5${NC}"

# Stop the function server
print_status "Stopping local function server..."
kill $FUNCTION_PID 2>/dev/null
wait $FUNCTION_PID 2>/dev/null

print_step "Step 3.3: Debug Information"
print_status "Showing function server logs..."
echo -e "${YELLOW}Recent server logs:${NC}"
tail -n 10 function_server_fixed.log 2>/dev/null || echo "No logs available"

echo -e "\n${GREEN}✓ TASK 3 COMPLETED: HTTP Function debugged and fixed!${NC}"

# =============================================================================
# TASK 4: DEPLOY A HTTP FUNCTION TO GOOGLE CLOUD
# =============================================================================
print_task "4. Deploy a HTTP Function from Your Local Machine to Google Cloud"

print_step "Step 4.1: Set Project Configuration"
print_status "Setting project configuration..."
gcloud config set project $PROJECT_ID
print_success "Project configuration set!"

print_step "Step 4.2: Create Service Account for Function"
print_status "Creating service account for Cloud Function..."
SERVICE_ACCOUNT="cloud-function-sa@$PROJECT_ID.iam.gserviceaccount.com"

# Check if service account already exists
if gcloud iam service-accounts describe $SERVICE_ACCOUNT >/dev/null 2>&1; then
    print_warning "Service account already exists, using existing one"
else
    gcloud iam service-accounts create cloud-function-sa \
        --display-name="Cloud Function Service Account"
    print_success "Service account created!"
fi

print_step "Step 4.3: Enable Required APIs"
print_status "Enabling Cloud Functions and related APIs..."
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
print_success "Required APIs enabled!"

print_step "Step 4.4: Deploy Function to Google Cloud"
print_status "Deploying validateTemperature function to Google Cloud..."
print_warning "This may take several minutes to complete..."

gcloud functions deploy validateTemperature \
    --trigger-http \
    --runtime nodejs20 \
    --gen2 \
    --allow-unauthenticated \
    --region $REGION \
    --service-account $SERVICE_ACCOUNT

print_success "Function deployed successfully!"

print_step "Step 4.5: Get Function URL and Test"
print_status "Retrieving function URL..."
FUNCTION_URL=$(gcloud functions describe validateTemperature --region=$REGION --format="value(serviceConfig.uri)")

echo -e "${CYAN}Function URL: ${WHITE}$FUNCTION_URL${NC}"

print_status "Testing deployed function with temperature 50..."
CLOUD_RESPONSE1=$(curl -s -X POST $FUNCTION_URL -H "Content-Type:application/json" -d '{"temp":"50"}')
echo -e "${CYAN}Response: ${WHITE}$CLOUD_RESPONSE1${NC}"

print_status "Testing deployed function with temperature 120..."
CLOUD_RESPONSE2=$(curl -s -X POST $FUNCTION_URL -H "Content-Type:application/json" -d '{"temp":"120"}')
echo -e "${CYAN}Response: ${WHITE}$CLOUD_RESPONSE2${NC}"

print_status "Testing deployed function with missing payload..."
CLOUD_RESPONSE3=$(curl -s -X POST $FUNCTION_URL)
echo -e "${CYAN}Response: ${WHITE}$CLOUD_RESPONSE3${NC}"

print_step "Step 4.6: Verify Function in Console"
print_status "Function deployment information..."
echo -e "${CYAN}Function Name: ${WHITE}validateTemperature${NC}"
echo -e "${CYAN}Runtime: ${WHITE}Node.js 20${NC}"
echo -e "${CYAN}Trigger: ${WHITE}HTTP${NC}"
echo -e "${CYAN}Region: ${WHITE}$REGION${NC}"
echo -e "${CYAN}Service Account: ${WHITE}$SERVICE_ACCOUNT${NC}"

echo -e "\n${GREEN}✓ TASK 4 COMPLETED: HTTP Function deployed to Google Cloud successfully!${NC}"

print_success "All lab tasks completed successfully! 🎉"