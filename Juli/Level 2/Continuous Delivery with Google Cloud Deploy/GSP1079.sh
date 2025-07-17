#!/bin/bash

# =====================================================
# Google Cloud Deploy Pipeline Setup Script
# =====================================================

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
RESET=$'\033[0m'
BOLD=$'\033[1m'

clear

echo "${BLUE}${BOLD}"
echo "=================================================="
echo "     Google Cloud Deploy Pipeline Setup"
echo "=================================================="
echo "${RESET}"

# =====================================================
# 1. ENVIRONMENT SETUP
# =====================================================
echo "${BLUE}${BOLD}🔧 Setting up environment...${RESET}"

# Get Zone
ZONE=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null)

if [ -z "$ZONE" ]; then
    read -p "Enter ZONE: " ZONE
fi
export ZONE
echo "${GREEN}Zone: $ZONE${RESET}"

# Get Region
REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)

if [ -z "$REGION" ]; then
    if [ -n "$ZONE" ]; then
        REGION="${ZONE%-*}"
    fi
    if [ -z "$REGION" ]; then
        read -p "Enter REGION: " REGION
    fi
fi
export REGION
echo "${GREEN}Region: $REGION${RESET}"

# Get Project ID
export PROJECT_ID=$(gcloud config get-value project)
echo "${GREEN}Project: $PROJECT_ID${RESET}"

# Configure defaults
gcloud config set compute/region $REGION

# =====================================================
# 2. ENABLE SERVICES
# =====================================================
echo "${BLUE}${BOLD}🔧 Enabling services...${RESET}"
gcloud services enable \
    container.googleapis.com \
    clouddeploy.googleapis.com \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    --quiet

echo "${YELLOW}Waiting for services to propagate...${RESET}"
sleep 30

# =====================================================
# 3. CREATE GKE CLUSTERS
# =====================================================
echo "${BLUE}${BOLD}🏗️ Creating GKE clusters...${RESET}"
gcloud container clusters create test --node-locations=$ZONE --num-nodes=1 --async --quiet
gcloud container clusters create staging --node-locations=$ZONE --num-nodes=1 --async --quiet
gcloud container clusters create prod --node-locations=$ZONE --num-nodes=1 --async --quiet

echo "${GREEN}Clusters creation started (async)${RESET}"

# =====================================================
# 4. SETUP ARTIFACT REGISTRY
# =====================================================
echo "${BLUE}${BOLD}📦 Creating Artifact Registry...${RESET}"
gcloud artifacts repositories create web-app \
    --description="Image registry for tutorial web app" \
    --repository-format=docker \
    --location=$REGION \
    --quiet

# =====================================================
# 5. PREPARE APPLICATION
# =====================================================
echo "${BLUE}${BOLD}📁 Preparing application...${RESET}"
cd ~/
git clone https://github.com/GoogleCloudPlatform/cloud-deploy-tutorials.git --quiet
cd cloud-deploy-tutorials
git checkout c3cae80 --quiet
cd tutorials/base

# Generate skaffold config
envsubst < clouddeploy-config/skaffold.yaml.template > web/skaffold.yaml

# Fix project-id placeholder if exists
if grep -q "{{project-id}}" web/skaffold.yaml; then
    sed -i "s/{{project-id}}/$PROJECT_ID/g" web/skaffold.yaml
fi

# =====================================================
# 6. BUILD APPLICATION
# =====================================================
echo "${BLUE}${BOLD}🔨 Building application...${RESET}"

# Create Cloud Build bucket if needed
if ! gsutil ls "gs://${PROJECT_ID}_cloudbuild/" &>/dev/null; then
    gsutil mb -p "${PROJECT_ID}" -l "${REGION}" "gs://${PROJECT_ID}_cloudbuild/" --quiet
fi

# Build with Skaffold
cd web
skaffold build --interactive=false \
    --default-repo $REGION-docker.pkg.dev/$PROJECT_ID/web-app \
    --file-output artifacts.json \
    --quiet
cd ..

if [ ! -f web/artifacts.json ]; then
    echo "${RED}❌ Build failed - artifacts.json not found${RESET}"
    exit 1
fi

echo "${GREEN}✅ Build completed${RESET}"

# =====================================================
# 7. SETUP DELIVERY PIPELINE
# =====================================================
echo "${BLUE}${BOLD}🚀 Setting up delivery pipeline...${RESET}"
gcloud config set deploy/region $REGION

cp clouddeploy-config/delivery-pipeline.yaml.template clouddeploy-config/delivery-pipeline.yaml
gcloud beta deploy apply --file=clouddeploy-config/delivery-pipeline.yaml --quiet

# =====================================================
# 8. WAIT FOR CLUSTERS
# =====================================================
echo "${BLUE}${BOLD}⏳ Waiting for clusters to be ready...${RESET}"
while true; do
    RUNNING_COUNT=$(gcloud container clusters list --format="value(status)" | grep -c "RUNNING")
    if [ "$RUNNING_COUNT" -eq 3 ]; then
        echo "${GREEN}✅ All clusters are running${RESET}"
        break
    fi
    echo "${YELLOW}Waiting... ($RUNNING_COUNT/3 running)${RESET}"
    sleep 15
done

# =====================================================
# 9. CONFIGURE KUBERNETES
# =====================================================
echo "${BLUE}${BOLD}⚙️ Configuring Kubernetes...${RESET}"
CONTEXTS=("test" "staging" "prod")

# Get credentials and setup contexts
for CONTEXT in ${CONTEXTS[@]}; do
    gcloud container clusters get-credentials ${CONTEXT} --region ${REGION} --quiet
    kubectl config rename-context gke_${PROJECT_ID}_${REGION}_${CONTEXT} ${CONTEXT}
done

# Create namespaces
for CONTEXT in ${CONTEXTS[@]}; do
    kubectl --context ${CONTEXT} apply -f kubernetes-config/web-app-namespace.yaml
done

# =====================================================
# 10. SETUP DEPLOYMENT TARGETS
# =====================================================
echo "${BLUE}${BOLD}🎯 Setting up deployment targets...${RESET}"
for CONTEXT in ${CONTEXTS[@]}; do
    envsubst < clouddeploy-config/target-$CONTEXT.yaml.template > clouddeploy-config/target-$CONTEXT.yaml
    gcloud beta deploy apply --file=clouddeploy-config/target-$CONTEXT.yaml --quiet
done

sleep 10

# =====================================================
# 11. CREATE RELEASE AND DEPLOY
# =====================================================
echo "${BLUE}${BOLD}🚀 Creating release...${RESET}"
gcloud beta deploy releases create web-app-001 \
    --delivery-pipeline web-app \
    --build-artifacts web/artifacts.json \
    --source web/ \
    --quiet

# Wait for test deployment
echo "${YELLOW}Deploying to test...${RESET}"
while true; do
    STATUS=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --filter="targetId=test" --format="value(state)" | head -n 1)
    if [ "$STATUS" == "SUCCEEDED" ]; then
        echo "${GREEN}✅ Test deployment succeeded${RESET}"
        break
    elif [[ "$STATUS" == "FAILED" || "$STATUS" == "CANCELLED" ]]; then
        echo "${RED}❌ Test deployment failed${RESET}"
        exit 1
    fi
    sleep 10
done

# Promote to staging
echo "${YELLOW}Promoting to staging...${RESET}"
gcloud beta deploy releases promote --delivery-pipeline web-app --release web-app-001 --quiet

while true; do
    STATUS=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --filter="targetId=staging" --format="value(state)" | head -n 1)
    if [ "$STATUS" == "SUCCEEDED" ]; then
        echo "${GREEN}✅ Staging deployment succeeded${RESET}"
        break
    elif [[ "$STATUS" == "FAILED" || "$STATUS" == "CANCELLED" ]]; then
        echo "${RED}❌ Staging deployment failed${RESET}"
        exit 1
    fi
    sleep 10
done

# Promote to production
echo "${YELLOW}Promoting to production...${RESET}"
gcloud beta deploy releases promote --delivery-pipeline web-app --release web-app-001 --quiet

# Wait for approval state
sleep 5
ROLLOUT_NAME=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --filter="targetId=prod" --format="value(name)" | head -n 1)

if [ -n "$ROLLOUT_NAME" ]; then
    ROLLOUT_ID=$(basename "$ROLLOUT_NAME")
    echo "${YELLOW}Approving production deployment...${RESET}"
    gcloud beta deploy rollouts approve $ROLLOUT_ID --delivery-pipeline web-app --release web-app-001 --quiet
    
    while true; do
        STATUS=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --filter="targetId=prod" --format="value(state)" | head -n 1)
        if [ "$STATUS" == "SUCCEEDED" ]; then
            echo "${GREEN}✅ Production deployment succeeded${RESET}"
            break
        elif [[ "$STATUS" == "FAILED" || "$STATUS" == "CANCELLED" ]]; then
            echo "${RED}❌ Production deployment failed${RESET}"
            exit 1
        fi
        sleep 10
    done
fi

# =====================================================
# 12. VERIFY DEPLOYMENTS
# =====================================================
echo "${BLUE}${BOLD}🔍 Verifying deployments...${RESET}"

for CONTEXT in ${CONTEXTS[@]}; do
    echo "${CYAN}--- $CONTEXT environment ---${RESET}"
    kubectx $CONTEXT
    kubectl get pods -n web-app
    echo
done

# =====================================================
# COMPLETION
# =====================================================
echo "${GREEN}${BOLD}"
echo "=================================================="
echo "🎉 DEPLOYMENT COMPLETE!"
echo "=================================================="
echo "${RESET}"
echo "${GREEN}✅ All environments deployed successfully:${RESET}"
echo "${CYAN}   - Test environment${RESET}"
echo "${CYAN}   - Staging environment${RESET}"
echo "${CYAN}   - Production environment${RESET}"
echo
echo "${BLUE}📊 Check deployments:${RESET}"
echo "   gcloud beta deploy releases list --delivery-pipeline web-app"
echo "   gcloud beta deploy rollouts list --delivery-pipeline web-app"
echo