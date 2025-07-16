#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}=== GCP Hello App Deployment ===${NC}\n"

# ===============================
# 1. AUTHENTICATION & SETUP
# ===============================
echo -e "${GREEN}1. Setting up authentication and environment...${NC}"

# Check current authentication
gcloud auth list

# Set compute zone from project metadata
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
gcloud config set compute/zone "$ZONE"

echo -e "${CYAN}Using Zone: $ZONE${NC}"
echo -e "${CYAN}Project ID: $DEVSHELL_PROJECT_ID${NC}"

# ===============================
# 2. CREATE KUBERNETES CLUSTER
# ===============================
echo -e "\n${GREEN}2. Creating Kubernetes cluster...${NC}"

gcloud container clusters create hello-world --zone="$ZONE"

# ===============================
# 3. GET SAMPLE APPLICATION
# ===============================
echo -e "\n${GREEN}3. Downloading sample application...${NC}"

# Clone Google's official sample repository
git clone https://github.com/GoogleCloudPlatform/kubernetes-engine-samples

# Navigate to hello-app directory
cd kubernetes-engine-samples/quickstarts/hello-app

# Show Dockerfile content
echo -e "\n${CYAN}Dockerfile content:${NC}"
cat Dockerfile

# ===============================
# 4. BUILD & PUSH DOCKER IMAGE
# ===============================
echo -e "\n${GREEN}4. Building and pushing Docker image...${NC}"

# Build Docker image with version tag
docker build -t gcr.io/$DEVSHELL_PROJECT_ID/hello-app:1.0 .

# Push image to Google Container Registry
gcloud docker -- push gcr.io/$DEVSHELL_PROJECT_ID/hello-app:1.0

# ===============================
# 5. DEPLOY TO KUBERNETES
# ===============================
echo -e "\n${GREEN}5. Deploying to Kubernetes...${NC}"

# Create deployment
kubectl create deployment hello-app --image=gcr.io/$DEVSHELL_PROJECT_ID/hello-app:1.0

# Check deployment status
echo -e "\n${CYAN}Checking deployment status...${NC}"
kubectl get deployments

echo -e "\n${CYAN}Checking pods...${NC}"
kubectl get pods

# ===============================
# 6. EXPOSE SERVICE
# ===============================
echo -e "\n${GREEN}6. Exposing service...${NC}"

# Expose deployment as LoadBalancer service
kubectl expose deployment hello-app \
  --name=hello-app \
  --type=LoadBalancer \
  --port=80 \
  --target-port=8080

# Get service details
echo -e "\n${CYAN}Service information:${NC}"
kubectl get svc hello-app

echo -e "\n${GREEN}=== Deployment completed! ===${NC}"
echo -e "${CYAN}Note: It may take a few minutes for the external IP to be assigned.${NC}"
echo -e "${CYAN}Run 'kubectl get svc hello-app' again to check for external IP.${NC}"