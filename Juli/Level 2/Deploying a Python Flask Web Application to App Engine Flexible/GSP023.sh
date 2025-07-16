#!/bin/bash

# Colors for output formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== GCP Vision API App Engine Deployment ===${NC}\n"

# ===============================
# 1. AUTHENTICATION & ENVIRONMENT
# ===============================
echo -e "${GREEN}1. Setting up authentication and environment...${NC}"

# Check authentication
gcloud auth list

# Export environment variables
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

echo -e "${CYAN}Zone: $ZONE${NC}"
echo -e "${CYAN}Region: $REGION${NC}"
echo -e "${CYAN}Project ID: $PROJECT_ID${NC}"

# ===============================
# 2. DOWNLOAD APPLICATION FILES
# ===============================
echo -e "\n${GREEN}2. Downloading Vision API application files...${NC}"

# Copy sample application from Cloud Storage
gcloud storage cp -r gs://spls/gsp023/flex_and_vision/ .
cd flex_and_vision

# ===============================
# 3. CREATE SERVICE ACCOUNT
# ===============================
echo -e "\n${GREEN}3. Creating service account...${NC}"

# Create service account
gcloud iam service-accounts create qwiklab \
  --display-name "My Qwiklab Service Account"

# Bind owner role to service account
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member serviceAccount:qwiklab@${PROJECT_ID}.iam.gserviceaccount.com \
  --role roles/owner

# Create and download service account key
gcloud iam service-accounts keys create ~/key.json \
  --iam-account qwiklab@${PROJECT_ID}.iam.gserviceaccount.com

# Set environment variable for authentication
export GOOGLE_APPLICATION_CREDENTIALS="/home/${USER}/key.json"

echo -e "${CYAN}Service account created and configured${NC}"

# ===============================
# 4. PYTHON ENVIRONMENT SETUP
# ===============================
echo -e "\n${GREEN}4. Setting up Python environment...${NC}"

# Create virtual environment
virtualenv -p python3 env

# Activate virtual environment
source env/bin/activate

# Install required packages
pip install -r requirements.txt

echo -e "${CYAN}Python environment ready${NC}"

# ===============================
# 5. APP ENGINE SETUP
# ===============================
echo -e "\n${GREEN}5. Setting up App Engine...${NC}"

# Create App Engine application
gcloud app create --region=$REGION

# Set up Cloud Storage bucket
export CLOUD_STORAGE_BUCKET=${PROJECT_ID}
gsutil mb gs://${PROJECT_ID}

echo -e "${CYAN}Cloud Storage bucket created: gs://${PROJECT_ID}${NC}"

# ===============================
# 6. CREATE APP.YAML CONFIGURATION
# ===============================
echo -e "\n${GREEN}6. Creating App Engine configuration...${NC}"

# Create app.yaml for App Engine Flexible Environment
cat > app.yaml <<EOF
# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

runtime: python
env: flex 
entrypoint: gunicorn -b :8080 main:app

runtime_config:
    operating_system: "ubuntu22"
    runtime_version: "3.12"

env_variables:
  CLOUD_STORAGE_BUCKET: $PROJECT_ID

manual_scaling:
  instances: 1
EOF

echo -e "${CYAN}App.yaml configuration created${NC}"

# ===============================
# 7. DEPLOY TO APP ENGINE
# ===============================
echo -e "\n${GREEN}7. Deploying to App Engine...${NC}"

# Set build timeout for deployment
gcloud config set app/cloud_build_timeout 1000

# Deploy application (background process)
echo -e "${YELLOW}Starting deployment (this may take several minutes)...${NC}"
gcloud app deploy --quiet &

# Wait for deployment to start
sleep 45

# Check deployment status
timeout 1 gcloud app versions list

# ===============================
# 8. TEST APPLICATION LOCALLY
# ===============================
echo -e "\n${GREEN}8. Testing application locally...${NC}"

# Run application locally for testing
python main.py

echo -e "\n${GREEN}=== Setup completed! ===${NC}"
echo -e "${CYAN}Your Vision API application is being deployed to App Engine.${NC}"
echo -e "${CYAN}You can check deployment status with: gcloud app versions list${NC}"
echo -e "${CYAN}Once deployed, access your app at: https://${PROJECT_ID}.appspot.com${NC}"