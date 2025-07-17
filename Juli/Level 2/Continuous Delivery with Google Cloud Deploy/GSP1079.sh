#!/bin/bash

# =====================================================
# Google Cloud Deploy Pipeline Setup Script
# Complete CI/CD Pipeline with GKE and Cloud Deploy
# =====================================================

echo "Starting Google Cloud Deploy pipeline setup..."

# =====================================================
# TASK 1: SET ENVIRONMENT VARIABLES
# =====================================================
echo "Task 1: Setting up environment variables..."

# Declare environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="Region"  # Replace with your actual region
gcloud config set compute/region $REGION

echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"

# =====================================================
# TASK 2: CREATE THREE GKE CLUSTERS
# =====================================================
echo "Task 2: Creating three GKE clusters (test, staging, prod)..."

# Enable required APIs
echo "Enabling Google Kubernetes Engine and Cloud Deploy APIs..."
gcloud services enable \
  container.googleapis.com \
  clouddeploy.googleapis.com

# Create the three GKE clusters for the delivery pipeline
echo "Creating GKE clusters..."
echo "  - Creating test cluster..."
gcloud container clusters create test \
  --node-locations="zone" \
  --num-nodes=1 \
  --async

echo "  - Creating staging cluster..."
gcloud container clusters create staging \
  --node-locations="zone" \
  --num-nodes=1 \
  --async

echo "  - Creating prod cluster..."
gcloud container clusters create prod \
  --node-locations="zone" \
  --num-nodes=1 \
  --async

# Check cluster status
echo "Checking cluster creation status..."
gcloud container clusters list --format="csv(name,status)"

echo "Note: Clusters are being created asynchronously. You can continue while they provision."

# =====================================================
# TASK 3: PREPARE WEB APPLICATION CONTAINER IMAGE
# =====================================================
echo "Task 3: Preparing web application container image repository..."

# Enable Artifact Registry API
echo "Enabling Artifact Registry API..."
gcloud services enable artifactregistry.googleapis.com

# Create repository for container images
echo "Creating web-app repository in Artifact Registry..."
gcloud artifacts repositories create web-app \
  --description="Image registry for tutorial web app" \
  --repository-format=docker \
  --location=$REGION

# =====================================================
# TASK 4: BUILD AND DEPLOY CONTAINER IMAGES
# =====================================================
echo "Task 4: Building and deploying container images to Artifact Registry..."

# Clone and prepare application configuration
echo "Cloning application repository..."
cd ~/
git clone https://github.com/GoogleCloudPlatform/cloud-deploy-tutorials.git
cd cloud-deploy-tutorials
git checkout c3cae80 --quiet
cd tutorials/base

# Create skaffold configuration
echo "Creating skaffold.yaml configuration..."
envsubst < clouddeploy-config/skaffold.yaml.template > web/skaffold.yaml

echo "Generated skaffold.yaml configuration:"
cat web/skaffold.yaml

# Build the web application
echo "Building web application..."

# Enable Cloud Build API
echo "Enabling Cloud Build API..."
gcloud services enable cloudbuild.googleapis.com

# Create Cloud Storage bucket for Cloud Build
echo "Creating Cloud Storage bucket for Cloud Build..."
gsutil mb -p $PROJECT_ID gs/${PROJECT_ID}_cloudbuild

# Build application and deploy to Artifact Registry
echo "Running skaffold build..."
cd web
skaffold build --interactive=false \
  --default-repo $REGION-docker.pkg.dev/$PROJECT_ID/web-app \
  --file-output artifacts.json
cd ..

# Verify container images in Artifact Registry
echo "Verifying container images in Artifact Registry..."
gcloud artifacts docker images list \
  $REGION-docker.pkg.dev/$PROJECT_ID/web-app \
  --include-tags \
  --format yaml

# Display build artifacts
echo "Build artifacts details:"
cat web/artifacts.json | jq

# =====================================================
# TASK 5: CREATE DELIVERY PIPELINE
# =====================================================
echo "Task 5: Creating delivery pipeline..."

# Ensure Cloud Deploy API is enabled
echo "Ensuring Cloud Deploy API is enabled..."
gcloud services enable clouddeploy.googleapis.com

# Create delivery pipeline
echo "Creating delivery pipeline resource..."
gcloud config set deploy/region $REGION
cp clouddeploy-config/delivery-pipeline.yaml.template clouddeploy-config/delivery-pipeline.yaml
gcloud beta deploy apply --file=clouddeploy-config/delivery-pipeline.yaml

# Verify delivery pipeline creation
echo "Verifying delivery pipeline..."
gcloud beta deploy delivery-pipelines describe web-app

# =====================================================
# TASK 6: CONFIGURE DEPLOYMENT TARGETS
# =====================================================
echo "Task 6: Configuring deployment targets..."

# Wait for clusters to be ready
echo "Waiting for GKE clusters to be ready..."
while true; do
    CLUSTER_STATUS=$(gcloud container clusters list --format="csv[no-heading](status)" | grep -v RUNNING | wc -l)
    if [ "$CLUSTER_STATUS" -eq 0 ]; then
        echo "All clusters are running!"
        break
    else
        echo "Waiting for clusters to finish provisioning..."
        sleep 30
    fi
done

# Final cluster status check
echo "Final cluster status:"
gcloud container clusters list --format="csv(name,status)"

# Create kubectl contexts for each cluster
echo "Creating kubectl contexts..."
CONTEXTS=("test" "staging" "prod")
for CONTEXT in ${CONTEXTS[@]}; do
    echo "  - Setting up context for $CONTEXT cluster..."
    gcloud container clusters get-credentials ${CONTEXT} --region ${REGION}
    kubectl config rename-context gke_${PROJECT_ID}_${REGION}_${CONTEXT} ${CONTEXT}
done

# Create namespaces in each cluster
echo "Creating web-app namespace in each cluster..."
for CONTEXT in ${CONTEXTS[@]}; do
    echo "  - Creating namespace in $CONTEXT cluster..."
    kubectl --context ${CONTEXT} apply -f kubernetes-config/web-app-namespace.yaml
done

# Create deployment targets
echo "Creating deployment targets..."
for CONTEXT in ${CONTEXTS[@]}; do
    echo "  - Creating target for $CONTEXT..."
    envsubst < clouddeploy-config/target-$CONTEXT.yaml.template > clouddeploy-config/target-$CONTEXT.yaml
    gcloud beta deploy apply --file clouddeploy-config/target-$CONTEXT.yaml
done

# Display target configurations
echo "Test target configuration:"
cat clouddeploy-config/target-test.yaml

echo "Production target configuration (note: requires approval):"
cat clouddeploy-config/target-prod.yaml

# Verify targets creation
echo "Verifying deployment targets..."
gcloud beta deploy targets list

# =====================================================
# TASK 7: CREATE A RELEASE
# =====================================================
echo "Task 7: Creating application release..."

# Create the first release
echo "Creating release web-app-001..."
gcloud beta deploy releases create web-app-001 \
  --delivery-pipeline web-app \
  --build-artifacts web/artifacts.json \
  --source web/

# Monitor first rollout to test environment
echo "Monitoring rollout to test environment..."
while true; do
    ROLLOUT_STATE=$(gcloud beta deploy rollouts list \
        --delivery-pipeline web-app \
        --release web-app-001 \
        --format="value(state)" \
        --filter="targetId:test" 2>/dev/null | head -1)
    
    if [ "$ROLLOUT_STATE" = "SUCCEEDED" ]; then
        echo "✅ Rollout to test environment succeeded!"
        break
    elif [ "$ROLLOUT_STATE" = "FAILED" ]; then
        echo "❌ Rollout to test environment failed!"
        exit 1
    else
        echo "⏳ Rollout status: $ROLLOUT_STATE (waiting...)"
        sleep 30
    fi
done

# Verify deployment in test cluster
echo "Verifying deployment in test cluster..."
kubectx test
kubectl get all -n web-app

# =====================================================
# TASK 8: PROMOTE TO STAGING
# =====================================================
echo "Task 8: Promoting application to staging..."

# Promote to staging
echo "Promoting release to staging environment..."
echo "Y" | gcloud beta deploy releases promote \
  --delivery-pipeline web-app \
  --release web-app-001

# Monitor staging rollout
echo "Monitoring rollout to staging environment..."
while true; do
    ROLLOUT_STATE=$(gcloud beta deploy rollouts list \
        --delivery-pipeline web-app \
        --release web-app-001 \
        --format="value(state)" \
        --filter="targetId:staging" 2>/dev/null | head -1)
    
    if [ "$ROLLOUT_STATE" = "SUCCEEDED" ]; then
        echo "✅ Rollout to staging environment succeeded!"
        break
    elif [ "$ROLLOUT_STATE" = "FAILED" ]; then
        echo "❌ Rollout to staging environment failed!"
        exit 1
    else
        echo "⏳ Rollout status: $ROLLOUT_STATE (waiting...)"
        sleep 30
    fi
done

# =====================================================
# TASK 9: PROMOTE TO PRODUCTION
# =====================================================
echo "Task 9: Promoting application to production..."

# Promote to production (requires approval)
echo "Promoting release to production environment..."
echo "Y" | gcloud beta deploy releases promote \
  --delivery-pipeline web-app \
  --release web-app-001

# Wait for approval state
echo "Waiting for approval requirement..."
sleep 10

# Check rollout status and approve if needed
ROLLOUT_NAME=$(gcloud beta deploy rollouts list \
    --delivery-pipeline web-app \
    --release web-app-001 \
    --format="value(name)" \
    --filter="targetId:prod" | head -1)

if [ ! -z "$ROLLOUT_NAME" ]; then
    ROLLOUT_ID=$(basename "$ROLLOUT_NAME")
    echo "Approving production rollout: $ROLLOUT_ID"
    
    # Approve the rollout
    echo "Y" | gcloud beta deploy rollouts approve $ROLLOUT_ID \
        --delivery-pipeline web-app \
        --release web-app-001
    
    # Monitor production rollout
    echo "Monitoring rollout to production environment..."
    while true; do
        ROLLOUT_STATE=$(gcloud beta deploy rollouts list \
            --delivery-pipeline web-app \
            --release web-app-001 \
            --format="value(state)" \
            --filter="targetId:prod" 2>/dev/null | head -1)
        
        if [ "$ROLLOUT_STATE" = "SUCCEEDED" ]; then
            echo "✅ Rollout to production environment succeeded!"
            break
        elif [ "$ROLLOUT_STATE" = "FAILED" ]; then
            echo "❌ Rollout to production environment failed!"
            exit 1
        else
            echo "⏳ Rollout status: $ROLLOUT_STATE (waiting...)"
            sleep 30
        fi
    done
    
    # Verify deployment in production cluster
    echo "Verifying deployment in production cluster..."
    kubectx prod
    kubectl get all -n web-app
fi

# =====================================================
# DEPLOYMENT COMPLETE
# =====================================================
echo ""
echo "🎉 Google Cloud Deploy pipeline setup complete!"
echo ""
echo "📋 Summary:"
echo "  ✅ Created 3 GKE clusters: test, staging, prod"
echo "  ✅ Set up Artifact Registry repository"
echo "  ✅ Built and pushed container images"
echo "  ✅ Created Cloud Deploy delivery pipeline"
echo "  ✅ Configured deployment targets"
echo "  ✅ Created and deployed release web-app-001"
echo "  ✅ Successfully promoted through: test → staging → prod"
echo ""
echo "🔗 Your application is now deployed across all environments!"
echo "   Test environment: $(kubectx test > /dev/null 2>&1 && kubectl get svc -n web-app 2>/dev/null | grep -v NAME || echo 'Check cluster')"
echo "   Staging environment: $(kubectx staging > /dev/null 2>&1 && kubectl get svc -n web-app 2>/dev/null | grep -v NAME || echo 'Check cluster')"
echo "   Production environment: $(kubectx prod > /dev/null 2>&1 && kubectl get svc -n web-app 2>/dev/null | grep -v NAME || echo 'Check cluster')"
echo ""
echo "📖 Next steps:"
echo "  - View releases: gcloud beta deploy releases list --delivery-pipeline web-app"
echo "  - View rollouts: gcloud beta deploy rollouts list --delivery-pipeline web-app"
echo "  - Access application: Use port-forwarding or configure ingress"