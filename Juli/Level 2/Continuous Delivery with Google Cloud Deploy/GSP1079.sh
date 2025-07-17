#!/bin/bash

# =====================================================
# Google Cloud Deploy Pipeline Setup Script
# Simplified but Complete CI/CD Pipeline
# =====================================================

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

clear

echo "${BLUE}${BOLD}"
echo "╔════════════════════════════════════════╗"
echo "║     Google Cloud Deploy Pipeline       ║"
echo "║         Setup & Deployment             ║"
echo "╚════════════════════════════════════════╝"
echo "${RESET}"

# =====================================================
# 1. ENVIRONMENT SETUP
# =====================================================
echo "${BLUE}${BOLD}🔧 Setting up environment...${RESET}"

ZONE=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null)

if [ -z "$ZONE" ]; then
    echo "${YELLOW}Zone not detected.${RESET}"
    while [ -z "$ZONE" ]; do
        read -p "Enter ZONE: " ZONE
        if [ -z "$ZONE" ]; then
            echo "${RED}Zone cannot be empty.${RESET}"
        fi
    done
fi
export ZONE
echo "${GREEN}✅ Zone: $ZONE${RESET}"

REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)

if [ -z "$REGION" ]; then
    if [ -n "$ZONE" ]; then
        REGION="${ZONE%-*}"
        if [ -z "$REGION" ] || [ "$REGION" == "$ZONE" ]; then
            REGION=""
        fi
    fi
fi

if [ -z "$REGION" ]; then
    while [ -z "$REGION" ]; do
        read -p "Enter REGION: " REGION
        if [ -z "$REGION" ]; then
            echo "${RED}Region cannot be empty.${RESET}"
        fi
    done
fi

export REGION
echo "${GREEN}✅ Region: $REGION${RESET}"

export PROJECT_ID=$(gcloud config get-value project)
echo "${GREEN}✅ Project ID: $PROJECT_ID${RESET}"

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
clouddeploy.googleapis.com

echo "${YELLOW}Waiting for service propagation...${RESET}"
for i in $(seq 30 -1 1); do
    echo -ne "\r⏳ $i seconds remaining..."
    sleep 1
done
echo -e "\r${GREEN}✅ Services enabled${RESET}"

# =====================================================
# 3. CREATE GKE CLUSTERS
# =====================================================
echo "${BLUE}${BOLD}🏗️ Creating GKE clusters...${RESET}"
gcloud container clusters create test --node-locations=$ZONE --num-nodes=1 --async
gcloud container clusters create staging --node-locations=$ZONE --num-nodes=1 --async
gcloud container clusters create prod --node-locations=$ZONE --num-nodes=1 --async

gcloud container clusters list --format="csv(name,status)"

# =====================================================
# 4. CREATE ARTIFACT REGISTRY
# =====================================================
echo "${BLUE}${BOLD}📦 Creating Artifact Registry...${RESET}"
gcloud artifacts repositories create web-app \
--description="Image registry for tutorial web app" \
--repository-format=docker \
--location=$REGION
echo "${GREEN}✅ Repository created${RESET}"

# =====================================================
# 5. PREPARE APPLICATION
# =====================================================
echo "${BLUE}${BOLD}📁 Preparing application...${RESET}"
cd ~/
git clone https://github.com/GoogleCloudPlatform/cloud-deploy-tutorials.git
cd cloud-deploy-tutorials
git checkout c3cae80 --quiet
cd tutorials/base

envsubst < clouddeploy-config/skaffold.yaml.template > web/skaffold.yaml

if grep -q "{{project-id}}" web/skaffold.yaml; then
    cp web/skaffold.yaml web/skaffold.yaml.bak
    sed -i "s/{{project-id}}/$PROJECT_ID/g" web/skaffold.yaml
fi

echo "${GREEN}✅ Application prepared${RESET}"

# =====================================================
# 6. CREATE CLOUD BUILD BUCKET
# =====================================================
echo "${BLUE}${BOLD}🪣 Setting up Cloud Build bucket...${RESET}"
if ! gsutil ls "gs://${PROJECT_ID}_cloudbuild/" &>/dev/null; then
    if gsutil mb -p "${PROJECT_ID}" -l "${REGION}" -b on "gs://${PROJECT_ID}_cloudbuild/"; then
        echo "${GREEN}✅ Bucket created${RESET}"
        sleep 5
    else
        echo "${RED}❌ Failed to create bucket${RESET}"
    fi
else
    echo "${GREEN}✅ Bucket exists${RESET}"
fi

# =====================================================
# 7. BUILD APPLICATION
# =====================================================
echo "${BLUE}${BOLD}🔨 Building application...${RESET}"
cd web
skaffold build --interactive=false \
--default-repo $REGION-docker.pkg.dev/$PROJECT_ID/web-app \
--file-output artifacts.json
cd ..

if [ ! -f web/artifacts.json ]; then
    echo "${RED}❌ Build failed - artifacts.json not found${RESET}"
    exit 1
fi
echo "${GREEN}✅ Build complete${RESET}"

# =====================================================
# 8. CONFIGURE CLOUD DEPLOY
# =====================================================
echo "${BLUE}${BOLD}⚙️ Configuring Cloud Deploy...${RESET}"
gcloud config set deploy/region $REGION

cp clouddeploy-config/delivery-pipeline.yaml.template clouddeploy-config/delivery-pipeline.yaml
gcloud beta deploy apply --file=clouddeploy-config/delivery-pipeline.yaml

# =====================================================
# 9. WAIT FOR CLUSTERS
# =====================================================
echo "${BLUE}${BOLD}⏳ Waiting for clusters...${RESET}"
while true; do
    cluster_statuses=$(gcloud container clusters list --format="csv(name,status)" | tail -n +2)
    all_running=true

    if [ -z "$cluster_statuses" ]; then
        all_running=false
    else
        echo "$cluster_statuses" | while IFS=, read -r cluster_name cluster_status; do
            cluster_name_trimmed=$(echo "$cluster_name" | tr -d '[:space:]')
            cluster_status_trimmed=$(echo "$cluster_status" | tr -d '[:space:]')

            if [ -z "$cluster_name_trimmed" ]; then
                continue
            fi

            echo "${CYAN}$cluster_name_trimmed: $cluster_status_trimmed${RESET}"
            if [[ "$cluster_status_trimmed" != "RUNNING" ]]; then
                all_running=false
            fi
        done
    fi

    if [ "$all_running" = true ] && [ -n "$cluster_statuses" ]; then
        echo "${GREEN}✅ All clusters running${RESET}"
        break 
    fi
    
    echo "${YELLOW}⏳ Waiting for clusters...${RESET}"
    for i in $(seq 10 -1 1); do
        echo -ne "\r⏳ $i seconds remaining..."
        sleep 1
    done
    echo -ne "\r⏳ Re-checking...                               " 
done 

# =====================================================
# 10. SETUP KUBECTL CONTEXTS
# =====================================================
echo "${BLUE}${BOLD}🔑 Setting up kubectl contexts...${RESET}"
CONTEXTS=("test" "staging" "prod")
for CONTEXT in ${CONTEXTS[@]}; do
    gcloud container clusters get-credentials ${CONTEXT} --region ${REGION}
    kubectl config rename-context gke_${PROJECT_ID}_${REGION}_${CONTEXT} ${CONTEXT}
done
echo "${GREEN}✅ Contexts configured${RESET}"

# =====================================================
# 11. CREATE NAMESPACES
# =====================================================
echo "${BLUE}${BOLD}🏠 Creating namespaces...${RESET}"
for CONTEXT_NAME in ${CONTEXTS[@]}; do
    MAX_RETRIES=20
    RETRY_COUNT=0
    SUCCESS=false
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if kubectl --context ${CONTEXT_NAME} apply -f kubernetes-config/web-app-namespace.yaml; then
            echo "${GREEN}✅ Namespace applied to $CONTEXT_NAME${RESET}"
            SUCCESS=true
            break
        else
            RETRY_COUNT=$((RETRY_COUNT+1))
            echo "${YELLOW}⚠️ Retry $RETRY_COUNT/$MAX_RETRIES for $CONTEXT_NAME${RESET}"
            
            for i in $(seq 5 -1 1); do
                echo -ne "\r⏳ $i seconds remaining..."
                sleep 1
            done
            echo -e "\r⏳ Retrying...                               "
        fi
    done
    if [ "$SUCCESS" != true ]; then
        echo "${RED}❌ Failed to apply namespace to $CONTEXT_NAME${RESET}"
    fi
done

# =====================================================
# 12. CREATE DEPLOYMENT TARGETS
# =====================================================
echo "${BLUE}${BOLD}🎯 Creating deployment targets...${RESET}"
for CONTEXT in ${CONTEXTS[@]}; do
    envsubst < clouddeploy-config/target-$CONTEXT.yaml.template > clouddeploy-config/target-$CONTEXT.yaml
    gcloud beta deploy apply --file=clouddeploy-config/target-$CONTEXT.yaml --region=${REGION} --project=${PROJECT_ID}
done
echo "${GREEN}✅ Targets configured${RESET}"

sleep 10

# =====================================================
# 13. CREATE RELEASE
# =====================================================
echo "${BLUE}${BOLD}🚀 Creating release...${RESET}"
gcloud beta deploy releases create web-app-001 \
  --delivery-pipeline web-app \
  --build-artifacts web/artifacts.json \
  --source web/ \
  --project=${PROJECT_ID} \
  --region=${REGION}

RELEASE_CREATION_STATUS=$?

if [ $RELEASE_CREATION_STATUS -eq 0 ]; then
    echo "${GREEN}✅ Release created${RESET}"
else
    echo "${RED}❌ Release creation failed${RESET}"
    exit 1
fi

# =====================================================
# 14. DEPLOY TO TEST
# =====================================================
test_rollout_succeeded=false
echo "${BLUE}${BOLD}⏳ Deploying to test...${RESET}"
while true; do
    status=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --filter="targetId=test" --format="value(state)" | head -n 1)

    if [ "$status" == "SUCCEEDED" ]; then
        echo -e "\r${GREEN}🎉 Test deployment SUCCEEDED${RESET}"
        test_rollout_succeeded=true
        break
    elif [[ "$status" == "FAILED" || "$status" == "CANCELLED" || "$status" == "HALTED" ]]; then
        echo -e "\r${RED}❌ Test deployment $status${RESET}"
        test_rollout_succeeded=false
        break
    fi

    current_status_display=${status:-"UNKNOWN"}
    for i in $(seq 10 -1 1); do
        echo -ne "\r⏳ Test status: $current_status_display ($i sec)"
        sleep 1
    done
done

if [ "$test_rollout_succeeded" = true ]; then
    echo "${BLUE}🔬 Verifying test deployment...${RESET}"
    kubectx test
    kubectl get all -n web-app

    # =====================================================
    # 15. DEPLOY TO STAGING
    # =====================================================
    echo "${BLUE}${BOLD}➡️ Promoting to staging...${RESET}"
    gcloud beta deploy releases promote \
    --delivery-pipeline web-app \
    --release web-app-001 \
    --quiet

    staging_rollout_succeeded=false
    while true; do
        status=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --filter="targetId=staging" --format="value(state)" | head -n 1)

        if [ "$status" == "SUCCEEDED" ]; then
            echo -e "\r${GREEN}🎉 Staging deployment SUCCEEDED${RESET}"
            staging_rollout_succeeded=true
            break
        elif [[ "$status" == "FAILED" || "$status" == "CANCELLED" || "$status" == "HALTED" ]]; then
            echo -e "\r${RED}❌ Staging deployment $status${RESET}"
            staging_rollout_succeeded=false
            break
        fi

        current_status_display=${status:-"UNKNOWN"}
        for i in $(seq 10 -1 1); do
            echo -ne "\r⏳ Staging status: $current_status_display ($i sec)"
            sleep 1
        done
    done

    if [ "$staging_rollout_succeeded" = true ]; then
        # =====================================================
        # 16. DEPLOY TO PRODUCTION
        # =====================================================
        echo "${BLUE}${BOLD}➡️ Promoting to production...${RESET}"
        gcloud beta deploy releases promote \
        --delivery-pipeline web-app \
        --release web-app-001 \
        --quiet

        prod_rollout_pending_approval=false
        echo "${BLUE}⏳ Waiting for approval state...${RESET}"
        while true; do
            status=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --filter="targetId=prod" --format="value(state)" | head -n 1)

            if [ "$status" == "PENDING_APPROVAL" ]; then
                echo -e "\r${GREEN}👍 Production pending approval${RESET}"
                prod_rollout_pending_approval=true
                break
            elif [[ "$status" == "FAILED" || "$status" == "CANCELLED" || "$status" == "HALTED" || "$status" == "SUCCEEDED" ]]; then
                echo -e "\r${RED}❌ Production status: $status${RESET}"
                prod_rollout_pending_approval=false
                break
            fi

            current_status_display=${status:-"UNKNOWN"}
            for i in $(seq 10 -1 1); do
                echo -ne "\r⏳ Prod status: $current_status_display ($i sec)"
                sleep 1
            done
        done

        if [ "$prod_rollout_pending_approval" = true ]; then
            prod_rollout_name=$(gcloud beta deploy rollouts list \
                --delivery-pipeline web-app \
                --release web-app-001 \
                --filter="targetId=prod AND state=PENDING_APPROVAL" \
                --format="value(name)" | head -n 1)

            if [ -n "$prod_rollout_name" ]; then
                echo "${BLUE}✅ Approving production deployment...${RESET}"
                gcloud beta deploy rollouts approve "$prod_rollout_name" \
                --delivery-pipeline web-app \
                --release web-app-001 \
                --quiet

                prod_rollout_succeeded=false
                while true; do
                    status=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --filter="targetId=prod" --format="value(state)" | head -n 1)

                    if [ "$status" == "SUCCEEDED" ]; then
                        echo -e "\r${GREEN}🎉 Production deployment SUCCEEDED${RESET}"
                        prod_rollout_succeeded=true
                        break
                    elif [[ "$status" == "FAILED" || "$status" == "CANCELLED" || "$status" == "HALTED" ]]; then
                        echo -e "\r${RED}❌ Production deployment $status${RESET}"
                        prod_rollout_succeeded=false
                        break
                    fi

                    current_status_display=${status:-"UNKNOWN"}
                    for i in $(seq 10 -1 1); do
                        echo -ne "\r⏳ Prod status: $current_status_display ($i sec)"
                        sleep 1
                    done
                done

                if [ "$prod_rollout_succeeded" = true ]; then
                    echo "${BLUE}🔬 Verifying production deployment...${RESET}"
                    kubectx prod
                    kubectl get all -n web-app
                fi
            else
                echo "${RED}❌ Could not find rollout to approve${RESET}"
            fi
        fi
    else
        echo "${RED}❌ Staging failed - skipping production${RESET}"
    fi
else
    echo "${RED}❌ Test failed - skipping remaining deployments${RESET}"
fi

echo
echo "${GREEN}${BOLD}🎉 Deployment pipeline complete!${RESET}"
echo "${BLUE}Commands for monitoring:${RESET}"
echo "  gcloud beta deploy releases list --delivery-pipeline web-app"
echo "  gcloud beta deploy rollouts list --delivery-pipeline web-app"
echo