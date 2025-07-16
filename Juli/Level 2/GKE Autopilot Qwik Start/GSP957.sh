#!/bin/bash

# Colors for better output formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== GCP Voting App Skaffold Deployment ===${NC}\n"

# ===============================
# 1. AUTHENTICATION & ENVIRONMENT
# ===============================
echo -e "${GREEN}1. Setting up authentication and environment...${NC}"

# Check current authentication
gcloud auth list

# Export environment variables
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

# Set compute region
gcloud config set compute/region "$REGION"

echo -e "${CYAN}Region: $REGION${NC}"
echo -e "${CYAN}Project ID: $PROJECT_ID${NC}"

# ===============================
# 2. CONNECT TO KUBERNETES CLUSTER
# ===============================
echo -e "\n${GREEN}2. Connecting to Kubernetes cluster...${NC}"

# Get credentials for dev-cluster
gcloud container clusters get-credentials dev-cluster --region $REGION

echo -e "${CYAN}Connected to dev-cluster${NC}"

# ===============================
# 3. DEPLOY APPLICATION WITH SKAFFOLD
# ===============================
echo -e "\n${GREEN}3. Deploying voting app with Skaffold...${NC}"

# Navigate to voting demo directory
cd ~/voting-demo/v2

# Deploy using Skaffold with Container Registry
echo -e "${YELLOW}Starting Skaffold deployment (this may take several minutes)...${NC}"
skaffold run --default-repo=gcr.io/$PROJECT_ID/voting-app --tail

# ===============================
# 4. GET APPLICATION URLs
# ===============================
echo -e "\n${GREEN}4. Getting application access information...${NC}"

# Get external IP of the web service
echo -e "${CYAN}Retrieving external IP address...${NC}"
kubectl get svc web-external --output=json | jq -r .status.loadBalancer.ingress[0].ip

# Store external IP in variable
web_external_ip=$(kubectl get svc web-external --output=json | jq -r .status.loadBalancer.ingress[0].ip)

# Display application URLs
echo
echo -e "${YELLOW}=== Application Access URLs ===${NC}"
echo
echo -e "${YELLOW}Voting App: http://$web_external_ip${NC}"
echo
echo -e "${YELLOW}Results Page: http://$web_external_ip/results${NC}"
echo

# ===============================
# 5. USER CONFIRMATION FOR CLEANUP
# ===============================
echo -e "${GREEN}5. Application deployed successfully!${NC}"
echo -e "${CYAN}You can now access the voting application using the URLs above.${NC}"
echo

# Interactive confirmation loop
while true; do
    echo -ne "${YELLOW}Do you want to clean up and delete the deployment? (Y/n): ${NC}"
    read confirm
    case "$confirm" in
        [Yy]) 
            echo -e "${BLUE}Running cleanup command...${NC}"
            break
            ;;
        [Nn]|"") 
            echo -e "${GREEN}Deployment will remain active. You can manually delete it later with 'skaffold delete'.${NC}"
            exit 0
            ;;
        *) 
            echo -e "${RED}Invalid input. Please enter Y or N.${NC}" 
            ;;
    esac
done

# ===============================
# 6. CLEANUP DEPLOYMENT
# ===============================
echo -e "\n${GREEN}6. Cleaning up deployment...${NC}"

# Delete Skaffold deployment
skaffold delete

echo -e "\n${GREEN}=== Cleanup completed! ===${NC}"
echo -e "${CYAN}All resources have been removed from the cluster.${NC}"