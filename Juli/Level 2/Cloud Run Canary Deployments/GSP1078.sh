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
echo -e "${CYAN}Region: $REGION${NC}"

# ===============================
# 2. ENABLE REQUIRED APIS
# ===============================
echo -e "\n${GREEN}2. Enabling required APIs...${NC}"

gcloud services enable \
  cloudresourcemanager.googleapis.com \
  container.googleapis.com \
  cloudbuild.googleapis.com \
  containerregistry.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com

echo -e "${CYAN}APIs enabled successfully${NC}"

# ===============================
# 3. CONFIGURE IAM PERMISSIONS
# ===============================
echo -e "\n${GREEN}3. Configuring IAM permissions...${NC}"

# Grant Secret Manager Admin role to Cloud Build Service Agent
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:service-$PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com \
  --role=roles/secretmanager.admin

echo -e "${CYAN}IAM permissions configured${NC}"

# ===============================
# 4. GITHUB SETUP AND AUTHENTICATION
# ===============================
echo -e "\n${GREEN}4. Setting up GitHub integration...${NC}"

# Install GitHub CLI
curl -sS https://webi.sh/gh | sh

echo -e "${PURPLE}Please follow the GitHub authentication process...${NC}"
echo -e "${YELLOW}1. Press ENTER to accept default options${NC}"
echo -e "${YELLOW}2. Choose 'Login with a web browser'${NC}"
echo -e "${YELLOW}3. Copy the one-time code and follow the URL${NC}"
echo -e "${YELLOW}4. Sign into GitHub and authorize the connection${NC}"

# GitHub authentication
gh auth login

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

# Create private repository
gh repo create cloudrun-progression --private

echo -e "${CYAN}Repository 'cloudrun-progression' created${NC}"

# ===============================
# 6. SETUP SOURCE CODE
# ===============================
echo -e "\n${GREEN}6. Setting up source code...${NC}"

# Clone sample repository
git clone https://github.com/GoogleCloudPlatform/training-data-analyst

# Copy sample code
mkdir -p cloudrun-progression
cp -r /home/$USER/training-data-analyst/self-paced-labs/cloud-run/canary/* cloudrun-progression
cd cloudrun-progression

echo -e "${CYAN}Source code copied to cloudrun-progression directory${NC}"

# ===============================
# 7. CONFIGURE BUILD FILES
# ===============================
echo -e "\n${GREEN}7. Configuring build files with project settings...${NC}"

# Update build configuration files with region
echo -e "${PURPLE}Please manually update the following files with REGION=$REGION:${NC}"
echo -e "${YELLOW}  - branch-cloudbuild.yaml${NC}"
echo -e "${YELLOW}  - master-cloudbuild.yaml${NC}"
echo -e "${YELLOW}  - tag-cloudbuild.yaml${NC}"
echo -e "${YELLOW}Set REGION in the Default Values section to: $REGION${NC}"

read -p "Press ENTER after updating the build files..."

# Replace placeholder values
sed -e "s/PROJECT/${PROJECT_ID}/g" -e "s/NUMBER/${PROJECT_NUMBER}/g" branch-trigger.json-tmpl > branch-trigger.json
sed -e "s/PROJECT/${PROJECT_ID}/g" -e "s/NUMBER/${PROJECT_NUMBER}/g" master-trigger.json-tmpl > master-trigger.json
sed -e "s/PROJECT/${PROJECT_ID}/g" -e "s/NUMBER/${PROJECT_NUMBER}/g" tag-trigger.json-tmpl > tag-trigger.json

echo -e "${CYAN}Build configuration files updated${NC}"

# ===============================
# 8. INITIAL COMMIT AND PUSH
# ===============================
echo -e "\n${GREEN}8. Making initial commit and push...${NC}"

# Initialize git and push to repository
git init
git config credential.helper gcloud.sh
git remote add gcp https://github.com/${GITHUB_USERNAME}/cloudrun-progression
git branch -m master
git add . && git commit -m "initial commit"
git push gcp master

echo -e "${CYAN}Initial commit pushed to repository${NC}"

# ===============================
# 9. BUILD AND DEPLOY INITIAL SERVICE
# ===============================
echo -e "\n${GREEN}9. Building and deploying initial Cloud Run service...${NC}"

# Build container image
gcloud builds submit --tag gcr.io/$PROJECT_ID/hello-cloudrun

# Deploy Cloud Run service
gcloud run deploy hello-cloudrun \
  --image gcr.io/$PROJECT_ID/hello-cloudrun \
  --platform managed \
  --region $REGION \
  --tag=prod -q

# Get production URL and test
PROD_URL=$(gcloud run services describe hello-cloudrun --platform managed --region $REGION --format=json | jq --raw-output ".status.url")
echo -e "${CYAN}Production URL: $PROD_URL${NC}"

# Test authenticated service
echo -e "${PURPLE}Testing authenticated service:${NC}"
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" $PROD_URL

echo -e "\n${CYAN}Initial Cloud Run service deployed successfully${NC}"

# ===============================
# 10. SETUP CLOUD BUILD CONNECTION
# ===============================
echo -e "\n${GREEN}10. Setting up Cloud Build GitHub connection...${NC}"

# Create Cloud Build connection
gcloud builds connections create github cloud-build-connection --project=$PROJECT_ID --region=$REGION

# Get connection details
CONNECTION_OUTPUT=$(gcloud builds connections describe cloud-build-connection --region=$REGION)
echo -e "${PURPLE}Connection created. Follow these steps:${NC}"
echo -e "${YELLOW}1. Copy the actionUri URL from the output below${NC}"
echo -e "${YELLOW}2. Open it in a new tab (don't click directly)${NC}"
echo -e "${YELLOW}3. Install Cloud Build GitHub App${NC}"
echo -e "${YELLOW}4. Select 'Only select repositories' and choose cloudrun-progression${NC}"
echo -e "${YELLOW}5. Click Save${NC}"

echo "$CONNECTION_OUTPUT"

read -p "Press ENTER after completing GitHub App installation..."

# Create Cloud Build repository
gcloud builds repositories create cloudrun-progression \
  --remote-uri="https://github.com/${GITHUB_USERNAME}/cloudrun-progression.git" \
  --connection="cloud-build-connection" --region=$REGION

echo -e "${CYAN}Cloud Build repository connection established${NC}"

# ===============================
# 11. SETUP BRANCH TRIGGER
# ===============================
echo -e "\n${GREEN}11. Setting up branch trigger for dynamic deployments...${NC}"

# Create branch trigger
gcloud builds triggers create github --name="branch" \
  --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/cloudrun-progression \
  --build-config='branch-cloudbuild.yaml' \
  --service-account=projects/$PROJECT_ID/serviceAccounts/$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --region=$REGION \
  --branch-pattern='[^(?!.*master)].*'

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
git add . && git commit -m "updated to v1.1" && git push gcp new-feature-1

echo -e "${CYAN}Feature branch pushed. Check Cloud Build for build progress.${NC}"

# Wait for build to complete
echo -e "${PURPLE}Waiting for build to complete (60 seconds)...${NC}"
sleep 60

# Get branch URL
BRANCH_URL=$(gcloud run services describe hello-cloudrun --platform managed --region $REGION --format=json | jq --raw-output ".status.traffic[] | select (.tag==\"new-feature-1\")|.url")
echo -e "${CYAN}Branch URL: $BRANCH_URL${NC}"

# Test branch deployment
echo -e "${PURPLE}Testing branch deployment:${NC}"
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" $BRANCH_URL

echo

# ===============================
# 13. SETUP CANARY DEPLOYMENT
# ===============================
echo -e "\n${GREEN}13. Setting up canary deployment trigger...${NC}"

# Create master trigger for canary deployment
gcloud builds triggers create github --name="master" \
  --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/cloudrun-progression \
  --build-config='master-cloudbuild.yaml' \
  --service-account=projects/$PROJECT_ID/serviceAccounts/$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --region=$REGION \
  --branch-pattern='master'

echo -e "${CYAN}Canary deployment trigger created${NC}"

# Merge feature branch to master
echo -e "${PURPLE}Merging feature branch to master for canary deployment...${NC}"
git checkout master
git merge new-feature-1
git push gcp master

# Wait for canary build
echo -e "${PURPLE}Waiting for canary build to complete (90 seconds)...${NC}"
sleep 90

# Get canary URL
CANARY_URL=$(gcloud run services describe hello-cloudrun --platform managed --region $REGION --format=json | jq --raw-output ".status.traffic[] | select (.tag==\"canary\")|.url")
echo -e "${CYAN}Canary URL: $CANARY_URL${NC}"

# Test canary deployment
echo -e "${PURPLE}Testing canary deployment:${NC}"
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" $CANARY_URL

echo

# Test traffic split
echo -e "${PURPLE}Testing traffic split (90% prod, 10% canary):${NC}"
LIVE_URL=$(gcloud run services describe hello-cloudrun --platform managed --region $REGION --format=json | jq --raw-output ".status.url")
for i in {0..10}; do
  curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" $LIVE_URL
  echo
done

# ===============================
# 14. SETUP PRODUCTION RELEASE
# ===============================
echo -e "\n${GREEN}14. Setting up production release trigger...${NC}"

# Create tag trigger for production release
gcloud builds triggers create github --name="tag" \
  --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/cloudrun-progression \
  --build-config='tag-cloudbuild.yaml' \
  --service-account=projects/$PROJECT_ID/serviceAccounts/$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --region=$REGION \
  --tag-pattern='.*'

echo -e "${CYAN}Production release trigger created${NC}"

# Create and push tag for production release
echo -e "${PURPLE}Creating tag for production release...${NC}"
git tag 1.1
git push gcp 1.1

# Wait for production build
echo -e "${PURPLE}Waiting for production build to complete (60 seconds)...${NC}"
sleep 60

# Test production deployment (100% traffic)
echo -e "${PURPLE}Testing production deployment (100% traffic):${NC}"
for i in {0..10}; do
  curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" $LIVE_URL
  echo
done

# ===============================
# 15. DEPLOYMENT SUMMARY
# ===============================
echo -e "\n${GREEN}=== Cloud Run Progressive Deployment Summary ===${NC}"

echo -e "${CYAN}Deployment Pipeline Configuration:${NC}"
echo -e "${CYAN}  • Branch Trigger: Automatic deployment for feature branches${NC}"
echo -e "${CYAN}  • Master Trigger: Canary deployment (10% traffic)${NC}"
echo -e "${CYAN}  • Tag Trigger: Production release (100% traffic)${NC}"

echo -e "\n${CYAN}Service URLs:${NC}"
echo -e "${CYAN}  • Production: $PROD_URL${NC}"
echo -e "${CYAN}  • Canary: $CANARY_URL${NC}"
echo -e "${CYAN}  • Branch: $BRANCH_URL${NC}"

echo -e "\n${CYAN}GitHub Repository: https://github.com/${GITHUB_USERNAME}/cloudrun-progression${NC}"

echo -e "\n${YELLOW}Workflow Summary:${NC}"
echo -e "${CYAN}1. Feature Branch → Automatic deployment with unique URL${NC}"
echo -e "${CYAN}2. Merge to Master → Canary deployment (10% traffic)${NC}"
echo -e "${CYAN}3. Create Tag → Production release (100% traffic)${NC}"

echo -e "\n${YELLOW}Useful Commands:${NC}"
echo -e "${CYAN}View Cloud Build triggers: gcloud builds triggers list --region=$REGION${NC}"
echo -e "${CYAN}View Cloud Run revisions: gcloud run revisions list --service=hello-cloudrun --region=$REGION${NC}"
echo -e "${CYAN}View service details: gcloud run services describe hello-cloudrun --region=$REGION${NC}"

echo -e "\n${GREEN}🎉 Cloud Run Progressive Deployment pipeline setup completed!${NC}"
echo -e "${CYAN}Your CI/CD pipeline is now ready for progressive deployments with GitHub integration${NC}"