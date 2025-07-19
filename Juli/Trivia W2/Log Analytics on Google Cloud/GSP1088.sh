#!/bin/bash


# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting GKE Day 2 Operations setup...${RESET}"

# =====================================================
# 1. AUTHENTICATION & ENVIRONMENT SETUP
# =====================================================
echo -e "${YELLOW}Step 1: Setting up authentication and environment...${RESET}"

# Check current authentication
gcloud auth list

# Set up environment variables
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

# Configure gcloud defaults
gcloud config set compute/zone "$ZONE"
gcloud config set compute/region "$REGION"

echo -e "${GREEN}✅ Environment configured: $PROJECT_ID | $REGION | $ZONE${RESET}"

# =====================================================
# 2. CONNECT TO GKE CLUSTER
# =====================================================
echo -e "${YELLOW}Step 2: Connecting to GKE cluster...${RESET}"

# Get credentials for the day2-ops cluster
gcloud container clusters get-credentials day2-ops --region $REGION

echo -e "${GREEN}✅ Connected to day2-ops cluster${RESET}"

# =====================================================
# 3. CLONE MICROSERVICES DEMO
# =====================================================
echo -e "${YELLOW}Step 3: Cloning microservices demo repository...${RESET}"

# Clone the microservices demo repository
git clone https://github.com/GoogleCloudPlatform/microservices-demo.git

echo -e "${GREEN}✅ Repository cloned successfully${RESET}"

# =====================================================
# 4. DEPLOY MICROSERVICES
# =====================================================
echo -e "${YELLOW}Step 4: Deploying microservices to Kubernetes...${RESET}"

# Change to demo directory
cd microservices-demo

# Deploy the microservices
echo -e "${CYAN}Applying Kubernetes manifests...${RESET}"
kubectl apply -f release/kubernetes-manifests.yaml

# Wait for deployment to stabilize
echo -e "${CYAN}Waiting for pods to be ready (45 seconds)...${RESET}"
sleep 45

# Check pod status
echo -e "${CYAN}Current pod status:${RESET}"
kubectl get pods

echo -e "${GREEN}✅ Microservices deployed${RESET}"

# =====================================================
# 5. VERIFY DEPLOYMENT
# =====================================================
echo -e "${YELLOW}Step 5: Verifying deployment...${RESET}"

# Get external IP of frontend service
echo -e "${CYAN}Getting frontend service external IP...${RESET}"
export EXTERNAL_IP=$(kubectl get service frontend-external -o jsonpath="{.status.loadBalancer.ingress[0].ip}")

if [ -z "$EXTERNAL_IP" ]; then
    echo -e "${RED}❌ Warning: External IP not yet available${RESET}"
    echo -e "${YELLOW}Waiting for load balancer to be ready...${RESET}"
else
    echo -e "${GREEN}✅ External IP: $EXTERNAL_IP${RESET}"
fi

# Test the service
if [ ! -z "$EXTERNAL_IP" ]; then
    echo -e "${CYAN}Testing service accessibility...${RESET}"
    HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}\n" http://${EXTERNAL_IP})
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✅ Service is accessible (HTTP $HTTP_CODE)${RESET}"
    else
        echo -e "${YELLOW}⚠️ Service returned HTTP $HTTP_CODE${RESET}"
    fi
fi

# =====================================================
# 6. CONFIGURE CLOUD LOGGING
# =====================================================
echo -e "${YELLOW}Step 6: Configuring Cloud Logging...${RESET}"

# Enable analytics on default logging bucket
echo -e "${CYAN}Enabling analytics on default logging bucket...${RESET}"
gcloud logging buckets update _Default \
    --project=$DEVSHELL_PROJECT_ID \
    --location=global \
    --enable-analytics

echo -e "${GREEN}✅ Analytics enabled on default bucket${RESET}"

# =====================================================
# 7. CREATE LOGGING SINK
# =====================================================
echo -e "${YELLOW}Step 7: Creating logging sink...${RESET}"

echo -e "${CYAN}Creating day2ops-sink for Kubernetes container logs...${RESET}"
gcloud logging sinks create day2ops-sink \
    logging.googleapis.com/projects/$DEVSHELL_PROJECT_ID/locations/global/buckets/day2ops-log \
    --log-filter='resource.type="k8s_container"' \
    --include-children \
    --format='json'

echo -e "${GREEN}✅ Logging sink created${RESET}"

# =====================================================
# 8. MANUAL SETUP INSTRUCTIONS
# =====================================================
echo -e "${YELLOW}Step 8: Manual setup required...${RESET}"

echo ""
echo -e "${CYAN}${BOLD}📋 MANUAL ACTION REQUIRED:${RESET}"
echo ""
echo -e "${YELLOW}${BOLD}Create a new Log bucket:${RESET}"
echo -e "${BLUE}   ${BOLD}→ Open: https://console.cloud.google.com/logs/storage/bucket?inv=1&invt=Ab2LhA&project=$DEVSHELL_PROJECT_ID${RESET}"
echo -e "${CYAN}   • Navigate to Cloud Logging Storage${RESET}"
echo -e "${CYAN}   • Create a new bucket named 'day2ops-log'${RESET}"
echo -e "${CYAN}   • Configure retention and location as needed${RESET}"
echo ""

echo -e "${GREEN}${BOLD}🎉 Day 2 Operations setup complete!${RESET}"
echo -e "${CYAN}Microservices demo is deployed and logging is configured.${RESET}"
if [ ! -z "$EXTERNAL_IP" ]; then
    echo -e "${CYAN}Access your application at: http://$EXTERNAL_IP${RESET}"
fi