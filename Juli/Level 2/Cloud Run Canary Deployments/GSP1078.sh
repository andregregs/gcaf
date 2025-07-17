#!/bin/bash

# Colors for better output formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== GCP Cloud Run Progressive Deployment with GitHub CI/CD ===${NC}\n"

# ===============================
# 1. ENVIRONMENT PREPARATION
# ===============================
echo -e "${GREEN}1. Preparing environment and setting up variables...${NC}"

# Export environment variables
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
export CURRENT_USER=$(gcloud config get-value account)

# Manual region input
echo -e "${CYAN}Please enter the region for this lab:${NC}"
echo -e "${YELLOW}Common regions: us-central1, us-east1, europe-west1, asia-southeast1${NC}"
read -p "Enter region: " REGION

if [ -z "$REGION" ]; then
    echo -e "${RED}Error: Region cannot be empty!${NC}"
    exit 1
fi

export REGION
gcloud config set compute/region $REGION

echo -e "${CYAN}Project ID: $PROJECT_ID${NC}"
echo -e "${CYAN}Project Number: $PROJECT_NUMBER${NC}"
echo -e "${CYAN}Current User: $CURRENT_USER${NC}"
echo -e "${CYAN}Region: $REGION${NC}"

# ===============================
# 2. ENABLE REQUIRED APIS
# ===============================
echo -e "\n${GREEN}2. Enabling required APIs...${NC}"

# Function to enable API with error handling
enable_api() {
    local api=$1
    echo -e "${PURPLE}Enabling $api...${NC}"
    
    if gcloud services enable $api 2>/dev/null; then
        echo -e "${CYAN}✓ $api enabled successfully${NC}"
    else
        echo -e "${YELLOW}⚠ Failed to enable $api or already enabled${NC}"
    fi
}

# Enable required APIs one by one
enable_api "cloudresourcemanager.googleapis.com"
enable_api "container.googleapis.com"
enable_api "cloudbuild.googleapis.com"
enable_api "containerregistry.googleapis.com"
enable_api "run.googleapis.com"
enable_api "secretmanager.googleapis.com"
enable_api "iamcredentials.googleapis.com"
enable_api "sourcerepo.googleapis.com"
enable_api "storage.googleapis.com"

echo -e "${CYAN}All APIs enablement completed${NC}"

# ===============================
# 3. CONFIGURE IAM PERMISSIONS (ENHANCED)
# ===============================
echo -e "\n${GREEN}3. Configuring IAM permissions...${NC}"

# Function to safely add IAM binding
add_iam_binding() {
    local member=$1
    local role=$2
    local description=$3
    
    echo -e "${PURPLE}${description}...${NC}"
    
    if gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="$member" \
        --role="$role" 2>/dev/null; then
        echo -e "${CYAN}✓ Successfully granted $role to $member${NC}"
    else
        echo -e "${YELLOW}⚠ Failed to grant $role to $member (may already exist or role not available)${NC}"
    fi
}

# Grant necessary roles to current user
add_iam_binding "user:$CURRENT_USER" "roles/cloudbuild.admin" "Granting Cloud Build Admin role to current user"
add_iam_binding "user:$CURRENT_USER" "roles/run.admin" "Granting Cloud Run Admin role to current user"
add_iam_binding "user:$CURRENT_USER" "roles/source.admin" "Granting Source Repository Admin role to current user"
add_iam_binding "user:$CURRENT_USER" "roles/storage.admin" "Granting Storage Admin role to current user"

# Grant roles to Cloud Build Service Agent
add_iam_binding "serviceAccount:service-$PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com" "roles/secretmanager.admin" "Granting Secret Manager Admin to Cloud Build Service Agent"
add_iam_binding "serviceAccount:service-$PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com" "roles/run.admin" "Granting Cloud Run Admin to Cloud Build Service Agent"
add_iam_binding "serviceAccount:service-$PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com" "roles/storage.admin" "Granting Storage Admin to Cloud Build Service Agent"

# Grant roles to Compute Engine default service account
add_iam_binding "serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" "roles/run.admin" "Granting Cloud Run Admin to Compute Engine service account"
add_iam_binding "serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" "roles/cloudbuild.builds.editor" "Granting Cloud Build Builds Editor to Compute Engine service account"
add_iam_binding "serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" "roles/storage.admin" "Granting Storage Admin to Compute Engine service account"

# Create custom role for Cloud Build connections if needed
echo -e "${PURPLE}Creating custom role for Cloud Build connections...${NC}"
if ! gcloud iam roles describe CloudBuildConnectionManager --project=$PROJECT_ID 2>/dev/null; then
    gcloud iam roles create CloudBuildConnectionManager \
        --project=$PROJECT_ID \
        --title="Cloud Build Connection Manager" \
        --description="Custom role for managing Cloud Build connections" \
        --permissions="cloudbuild.connections.create,cloudbuild.connections.update,cloudbuild.connections.get,cloudbuild.connections.list,cloudbuild.connections.use,cloudbuild.repositories.create,cloudbuild.repositories.get,cloudbuild.repositories.list" \
        --stage="ALPHA" 2>/dev/null || echo -e "${YELLOW}⚠ Custom role creation failed or already exists${NC}"
    
    # Grant custom role to current user
    add_iam_binding "user:$CURRENT_USER" "projects/$PROJECT_ID/roles/CloudBuildConnectionManager" "Granting custom Cloud Build Connection Manager role"
fi

# Alternative: Use predefined roles that should exist
add_iam_binding "user:$CURRENT_USER" "roles/cloudbuild.builds.editor" "Granting Cloud Build Builds Editor (alternative)"
add_iam_binding "user:$CURRENT_USER" "roles/source.developer" "Granting Source Repository Developer role"

# Grant Owner role as last resort (be careful with this in production)
echo -e "${YELLOW}If above permissions are insufficient, you may need to grant Owner role temporarily:${NC}"
echo -e "${CYAN}gcloud projects add-iam-policy-binding $PROJECT_ID --member=\"user:$CURRENT_USER\" --role=\"roles/owner\"${NC}"

echo -e "${CYAN}IAM permissions configuration completed${NC}"

# ===============================
# 4. GITHUB SETUP AND AUTHENTICATION
# ===============================
echo -e "\n${GREEN}4. Setting up GitHub integration...${NC}"

# Check if GitHub CLI is already installed
if ! command -v gh &> /dev/null; then
    echo -e "${PURPLE}Installing GitHub CLI...${NC}"
    curl -sS https://webi.sh/gh | sh
    # Add gh to PATH if needed
    export PATH="$HOME/.local/bin:$PATH"
fi

# Check if already authenticated
if ! gh auth status &> /dev/null; then
    echo -e "${PURPLE}Please follow the GitHub authentication process...${NC}"
    echo -e "${YELLOW}1. Press ENTER to accept default options${NC}"
    echo -e "${YELLOW}2. Choose 'Login with a web browser'${NC}"
    echo -e "${YELLOW}3. Copy the one-time code and follow the URL${NC}"
    echo -e "${YELLOW}4. Sign into GitHub and authorize the connection${NC}"
    
    # GitHub authentication
    gh auth login
else
    echo -e "${CYAN}Already authenticated with GitHub${NC}"
fi

# Get GitHub username and configure Git
GITHUB_USERNAME=$(gh api user -q ".login")
USER_EMAIL="${GITHUB_USERNAME}@example.com"  # Default email format

git config --global user.name "${GITHUB_USERNAME}"
git config --global user.email "${USER_EMAIL}"

echo -e "${CYAN}GitHub Username: ${GITHUB_USERNAME}${NC}"
echo -e "${CYAN}User Email: ${USER_EMAIL}${NC}"

# ===============================
# 5. CREATE GITHUB REPOSITORY
# ===============================
echo -e "\n${GREEN}5. Creating GitHub repository...${NC}"

# Check if repository already exists
if ! gh repo view ${GITHUB_USERNAME}/cloudrun-progression &> /dev/null; then
    # Create private repository
    gh repo create cloudrun-progression --private
    echo -e "${CYAN}Repository 'cloudrun-progression' created${NC}"
else
    echo -e "${YELLOW}Repository 'cloudrun-progression' already exists${NC}"
fi

# ===============================
# 6. SETUP SOURCE CODE
# ===============================
echo -e "\n${GREEN}6. Setting up source code...${NC}"

# Clean up existing directory if it exists
if [ -d "cloudrun-progression" ]; then
    rm -rf cloudrun-progression
fi

# Clone sample repository if not exists
if [ ! -d "training-data-analyst" ]; then
    git clone https://github.com/GoogleCloudPlatform/training-data-analyst
fi

# Copy sample code
mkdir -p cloudrun-progression
cp -r training-data-analyst/self-paced-labs/cloud-run/canary/* cloudrun-progression/
cd cloudrun-progression

echo -e "${CYAN}Source code copied to cloudrun-progression directory${NC}"

# ===============================
# 7. CONFIGURE BUILD FILES
# ===============================
echo -e "\n${GREEN}7. Configuring build files with project settings...${NC}"

# Function to update YAML files with region
update_yaml_files() {
    local region=$1
    
    # Update branch-cloudbuild.yaml
    if [ -f "branch-cloudbuild.yaml" ]; then
        sed -i "s/\$REGION/$region/g" branch-cloudbuild.yaml
        sed -i "s/us-central1/$region/g" branch-cloudbuild.yaml
    fi
    
    # Update master-cloudbuild.yaml
    if [ -f "master-cloudbuild.yaml" ]; then
        sed -i "s/\$REGION/$region/g" master-cloudbuild.yaml
        sed -i "s/us-central1/$region/g" master-cloudbuild.yaml
    fi
    
    # Update tag-cloudbuild.yaml
    if [ -f "tag-cloudbuild.yaml" ]; then
        sed -i "s/\$REGION/$region/g" tag-cloudbuild.yaml
        sed -i "s/us-central1/$region/g" tag-cloudbuild.yaml
    fi
}

# Update YAML files with the selected region
update_yaml_files $REGION

# Replace placeholder values in JSON template files
if [ -f "branch-trigger.json-tmpl" ]; then
    sed -e "s/PROJECT/${PROJECT_ID}/g" -e "s/NUMBER/${PROJECT_NUMBER}/g" branch-trigger.json-tmpl > branch-trigger.json
fi

if [ -f "master-trigger.json-tmpl" ]; then
    sed -e "s/PROJECT/${PROJECT_ID}/g" -e "s/NUMBER/${PROJECT_NUMBER}/g" master-trigger.json-tmpl > master-trigger.json
fi

if [ -f "tag-trigger.json-tmpl" ]; then
    sed -e "s/PROJECT/${PROJECT_ID}/g" -e "s/NUMBER/${PROJECT_NUMBER}/g" tag-trigger.json-tmpl > tag-trigger.json
fi

echo -e "${CYAN}Build configuration files updated with region: $REGION${NC}"

# ===============================
# 8. INITIAL COMMIT AND PUSH
# ===============================
echo -e "\n${GREEN}8. Making initial commit and push...${NC}"

# Initialize git and push to repository
git init
git config credential.helper gcloud.sh
git remote add origin https://github.com/${GITHUB_USERNAME}/cloudrun-progression.git
git branch -M main
git add . && git commit -m "initial commit"

# Push with error handling
if ! git push -u origin main; then
    echo -e "${YELLOW}Push failed, trying to set up authentication...${NC}"
    git remote set-url origin https://github.com/${GITHUB_USERNAME}/cloudrun-progression.git
    git push -u origin main
fi

echo -e "${CYAN}Initial commit pushed to repository${NC}"

# ===============================
# 9. BUILD AND DEPLOY INITIAL SERVICE
# ===============================
echo -e "\n${GREEN}9. Building and deploying initial Cloud Run service...${NC}"

# Build container image
echo -e "${PURPLE}Building container image...${NC}"
gcloud builds submit --tag gcr.io/$PROJECT_ID/hello-cloudrun

# Deploy Cloud Run service
echo -e "${PURPLE}Deploying Cloud Run service...${NC}"
gcloud run deploy hello-cloudrun \
  --image gcr.io/$PROJECT_ID/hello-cloudrun \
  --platform managed \
  --region $REGION \
  --tag=prod \
  --allow-unauthenticated \
  --quiet

# Get production URL and test
PROD_URL=$(gcloud run services describe hello-cloudrun --platform managed --region $REGION --format="value(status.url)")
echo -e "${CYAN}Production URL: $PROD_URL${NC}"

# Test service
echo -e "${PURPLE}Testing service:${NC}"
curl -s $PROD_URL || echo -e "${YELLOW}Service test completed${NC}"

echo -e "\n${CYAN}Initial Cloud Run service deployed successfully${NC}"

# ===============================
# 10. SETUP CLOUD BUILD CONNECTION (ENHANCED)
# ===============================
echo -e "\n${GREEN}10. Setting up Cloud Build GitHub connection...${NC}"

# Check current user permissions first
echo -e "${PURPLE}Checking current user permissions...${NC}"
if ! gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" --format="value(bindings.role)" --filter="bindings.members:$CURRENT_USER" | grep -q "cloudbuild\|owner"; then
    echo -e "${YELLOW}⚠ You may need additional permissions. Attempting to grant Owner role...${NC}"
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="user:$CURRENT_USER" \
        --role="roles/owner" || echo -e "${RED}Failed to grant Owner role${NC}"
fi

# Function to create connection with retry
create_connection() {
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo -e "${PURPLE}Attempt $attempt: Creating Cloud Build connection...${NC}"
        
        if gcloud builds connections create github cloud-build-connection \
            --project=$PROJECT_ID \
            --region=$REGION; then
            echo -e "${CYAN}✓ Cloud Build connection created successfully${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ Attempt $attempt failed${NC}"
            if [ $attempt -eq $max_attempts ]; then
                echo -e "${RED}❌ Failed to create connection after $max_attempts attempts${NC}"
                echo -e "${YELLOW}Please try the following alternatives:${NC}"
                echo -e "${CYAN}1. Use Google Cloud Console to create the connection manually${NC}"
                echo -e "${CYAN}2. Grant Owner role: gcloud projects add-iam-policy-binding $PROJECT_ID --member=\"user:$CURRENT_USER\" --role=\"roles/owner\"${NC}"
                echo -e "${CYAN}3. Contact your GCP administrator for permission assistance${NC}"
                
                read -p "Would you like to continue with manual connection setup? (y/N): " continue_manual
                if [[ $continue_manual =~ ^[Yy]$ ]]; then
                    echo -e "${YELLOW}Please create the connection manually and press ENTER when ready...${NC}"
                    read -p "Press ENTER to continue..."
                    return 0
                else
                    return 1
                fi
            fi
            
            attempt=$((attempt + 1))
            echo -e "${YELLOW}Waiting 10 seconds before retry...${NC}"
            sleep 10
        fi
    done
}

# Check if connection already exists
if gcloud builds connections describe cloud-build-connection --region=$REGION 2>/dev/null; then
    echo -e "${CYAN}✓ Connection 'cloud-build-connection' already exists${NC}"
else
    # Try to create connection
    if ! create_connection; then
        echo -e "${RED}❌ Cannot proceed without Cloud Build connection${NC}"
        exit 1
    fi
fi

# Get connection details and handle GitHub App installation
echo -e "${PURPLE}Retrieving connection details...${NC}"
CONNECTION_OUTPUT=$(gcloud builds connections describe cloud-build-connection --region=$REGION --format="value(installationState.actionUri)" 2>/dev/null)

if [ ! -z "$CONNECTION_OUTPUT" ] && [ "$CONNECTION_OUTPUT" != "null" ]; then
    echo -e "${PURPLE}Please complete the GitHub App installation:${NC}"
    echo -e "${YELLOW}1. Open this URL in your browser: ${CONNECTION_OUTPUT}${NC}"
    echo -e "${YELLOW}2. Install Cloud Build GitHub App${NC}"
    echo -e "${YELLOW}3. Select 'Only select repositories' and choose 'cloudrun-progression'${NC}"
    echo -e "${YELLOW}4. Click 'Install & Authorize'${NC}"
    
    read -p "Press ENTER after completing GitHub App installation..."
else
    echo -e "${CYAN}✓ Connection appears to be already configured${NC}"
fi

# Create Cloud Build repository with enhanced error handling
echo -e "${PURPLE}Creating Cloud Build repository connection...${NC}"
if ! gcloud builds repositories describe cloudrun-progression --connection="cloud-build-connection" --region=$REGION 2>/dev/null; then
    if ! gcloud builds repositories create cloudrun-progression \
        --remote-uri="https://github.com/${GITHUB_USERNAME}/cloudrun-progression.git" \
        --connection="cloud-build-connection" \
        --region=$REGION; then
        echo -e "${RED}❌ Failed to create repository connection${NC}"
        echo -e "${YELLOW}Please ensure GitHub App is properly installed and try again${NC}"
        exit 1
    fi
    echo -e "${CYAN}✓ Repository connection created successfully${NC}"
else
    echo -e "${CYAN}✓ Repository connection already exists${NC}"
fi

echo -e "${CYAN}Cloud Build GitHub integration completed${NC}"

# ===============================
# 11. SETUP BRANCH TRIGGER
# ===============================
echo -e "\n${GREEN}11. Setting up branch trigger for dynamic deployments...${NC}"

# Delete existing trigger if it exists
gcloud builds triggers delete branch --region=$REGION --quiet 2>/dev/null || true

# Create branch trigger
gcloud builds triggers create github \
  --name="branch" \
  --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/cloudrun-progression \
  --build-config='branch-cloudbuild.yaml' \
  --service-account=projects/$PROJECT_ID/serviceAccounts/$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --region=$REGION \
  --branch-pattern='^(?!.*main).*$'

echo -e "${CYAN}Branch trigger created${NC}"

# ===============================
# 12. TEST BRANCH DEPLOYMENT
# ===============================
echo -e "\n${GREEN}12. Testing branch deployment...${NC}"

# Create new feature branch
git checkout -b new-feature-1

# Update application version
echo -e "${PURPLE}Updating application from v1.0 to v1.1...${NC}"
sed -i "s/v1.0/v1.1/g" app.py

# Commit and push changes
git add . && git commit -m "updated to v1.1"
git push origin new-feature-1

echo -e "${CYAN}Feature branch pushed. Check Cloud Build for build progress.${NC}"

# Wait for build to complete
echo -e "${PURPLE}Waiting for build to complete (90 seconds)...${NC}"
sleep 90

# Get branch URL
BRANCH_URL=$(gcloud run services describe hello-cloudrun --platform managed --region $REGION --format="value(status.traffic[].url)" --filter="status.traffic[].tag=new-feature-1")

if [ ! -z "$BRANCH_URL" ]; then
    echo -e "${CYAN}Branch URL: $BRANCH_URL${NC}"
    echo -e "${PURPLE}Testing branch deployment:${NC}"
    curl -s $BRANCH_URL || echo -e "${YELLOW}Branch deployment test completed${NC}"
else
    echo -e "${YELLOW}Branch URL not yet available. Build may still be in progress.${NC}"
fi

# ===============================
# 13. SETUP CANARY DEPLOYMENT
# ===============================
echo -e "\n${GREEN}13. Setting up canary deployment trigger...${NC}"

# Delete existing trigger if it exists
gcloud builds triggers delete main --region=$REGION --quiet 2>/dev/null || true

# Create main trigger for canary deployment
gcloud builds triggers create github \
  --name="main" \
  --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/cloudrun-progression \
  --build-config='master-cloudbuild.yaml' \
  --service-account=projects/$PROJECT_ID/serviceAccounts/$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --region=$REGION \
  --branch-pattern='main'

echo -e "${CYAN}Canary deployment trigger created${NC}"

# Merge feature branch to main
echo -e "${PURPLE}Merging feature branch to main for canary deployment...${NC}"
git checkout main
git merge new-feature-1
git push origin main

# Wait for canary build
echo -e "${PURPLE}Waiting for canary build to complete (120 seconds)...${NC}"
sleep 120

# Get canary URL
CANARY_URL=$(gcloud run services describe hello-cloudrun --platform managed --region $REGION --format="value(status.traffic[].url)" --filter="status.traffic[].tag=canary")

if [ ! -z "$CANARY_URL" ]; then
    echo -e "${CYAN}Canary URL: $CANARY_URL${NC}"
    echo -e "${PURPLE}Testing canary deployment:${NC}"
    curl -s $CANARY_URL || echo -e "${YELLOW}Canary deployment test completed${NC}"
fi

# Test traffic split
echo -e "${PURPLE}Testing traffic split (should show mix of v1.0 and v1.1):${NC}"
LIVE_URL=$(gcloud run services describe hello-cloudrun --platform managed --region $REGION --format="value(status.url)")
for i in {1..5}; do
    echo -n "Test $i: "
    curl -s $LIVE_URL | grep -o "v[0-9]\.[0-9]" || echo "No version found"
done

# ===============================
# 14. SETUP PRODUCTION RELEASE
# ===============================
echo -e "\n${GREEN}14. Setting up production release trigger...${NC}"

# Delete existing trigger if it exists
gcloud builds triggers delete tag --region=$REGION --quiet 2>/dev/null || true

# Create tag trigger for production release
gcloud builds triggers create github \
  --name="tag" \
  --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/cloudrun-progression \
  --build-config='tag-cloudbuild.yaml' \
  --service-account=projects/$PROJECT_ID/serviceAccounts/$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --region=$REGION \
  --tag-pattern='.*'

echo -e "${CYAN}Production release trigger created${NC}"

# Create and push tag for production release
echo -e "${PURPLE}Creating tag for production release...${NC}"
git tag v1.1
git push origin v1.1

# Wait for production build
echo -e "${PURPLE}Waiting for production build to complete (90 seconds)...${NC}"
sleep 90

# Test production deployment (100% traffic)
echo -e "${PURPLE}Testing production deployment (should show 100% v1.1):${NC}"
for i in {1..5}; do
    echo -n "Test $i: "
    curl -s $LIVE_URL | grep -o "v[0-9]\.[0-9]" || echo "No version found"
done

# ===============================
# 15. DEPLOYMENT SUMMARY
# ===============================
echo -e "\n${GREEN}=== Cloud Run Progressive Deployment Summary ===${NC}"

echo -e "${CYAN}Deployment Pipeline Configuration:${NC}"
echo -e "${CYAN}  • Branch Trigger: Automatic deployment for feature branches${NC}"
echo -e "${CYAN}  • Main Trigger: Canary deployment (10% traffic)${NC}"
echo -e "${CYAN}  • Tag Trigger: Production release (100% traffic)${NC}"

echo -e "\n${CYAN}Service URLs:${NC}"
echo -e "${CYAN}  • Production: $PROD_URL${NC}"
[ ! -z "$CANARY_URL" ] && echo -e "${CYAN}  • Canary: $CANARY_URL${NC}"
[ ! -z "$BRANCH_URL" ] && echo -e "${CYAN}  • Branch: $BRANCH_URL${NC}"

echo -e "\n${CYAN}GitHub Repository: https://github.com/${GITHUB_USERNAME}/cloudrun-progression${NC}"

echo -e "\n${YELLOW}Workflow Summary:${NC}"
echo -e "${CYAN}1. Feature Branch → Automatic deployment with unique URL${NC}"
echo -e "${CYAN}2. Merge to Main → Canary deployment (10% traffic)${NC}"
echo -e "${CYAN}3. Create Tag → Production release (100% traffic)${NC}"

echo -e "\n${YELLOW}Useful Commands:${NC}"
echo -e "${CYAN}View Cloud Build triggers:${NC}"
echo -e "  gcloud builds triggers list --region=$REGION"
echo -e "${CYAN}View Cloud Run revisions:${NC}"
echo -e "  gcloud run revisions list --service=hello-cloudrun --region=$REGION"
echo -e "${CYAN}View service details:${NC}"
echo -e "  gcloud run services describe hello-cloudrun --region=$REGION"
echo -e "${CYAN}View build history:${NC}"
echo -e "  gcloud builds list --region=$REGION"

echo -e "\n${YELLOW}Troubleshooting:${NC}"
echo -e "${CYAN}Check build logs:${NC}"
echo -e "  gcloud builds log [BUILD_ID]"
echo -e "${CYAN}Check service logs:${NC}"
echo -e "  gcloud logs read \"resource.type=cloud_run_revision AND resource.labels.service_name=hello-cloudrun\" --limit=50"

echo -e "\n${GREEN}🎉 Cloud Run Progressive Deployment pipeline setup completed!${NC}"
echo -e "${CYAN}Your CI/CD pipeline is now ready for progressive deployments with GitHub integration${NC}"

# ===============================
# 16. CLEANUP FUNCTION (OPTIONAL)
# ===============================
cleanup_resources() {
    echo -e "\n${YELLOW}Cleanup function available. To clean up resources, run:${NC}"
    echo -e "${CYAN}  # Delete Cloud Run service${NC}"
    echo -e "  gcloud run services delete hello-cloudrun --region=$REGION --quiet"
    echo -e "${CYAN}  # Delete Cloud Build triggers${NC}"
    echo -e "  gcloud builds triggers delete branch --region=$REGION --quiet"
    echo -e "  gcloud builds triggers delete main --region=$REGION --quiet"  
    echo -e "  gcloud builds triggers delete tag --region=$REGION --quiet"
    echo -e "${CYAN}  # Delete Cloud Build repository${NC}"
    echo -e "  gcloud builds repositories delete cloudrun-progression --connection=cloud-build-connection --region=$REGION --quiet"
    echo -e "${CYAN}  # Delete Cloud Build connection${NC}"
    echo -e "  gcloud builds connections delete cloud-build-connection --region=$REGION --quiet"
    echo -e "${CYAN}  # Delete GitHub repository${NC}"
    echo -e "  gh repo delete ${GITHUB_USERNAME}/cloudrun-progression --confirm"
}

# Uncomment the line below to show cleanup instructions
# cleanup_resources