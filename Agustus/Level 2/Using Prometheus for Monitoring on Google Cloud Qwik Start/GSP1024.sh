#!/bin/bash

# GKE with Managed Prometheus Monitoring Lab - Complete Script
# This script automates the setup of GKE cluster with Prometheus monitoring

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
# TASK 1: CREATE A DOCKER REPOSITORY
# =============================================================================
print_task "1. Create a Docker Repository"

print_step "Step 1.1: Create Docker Repository in Artifact Registry"
print_status "Creating Docker repository named 'docker-repo'..."
print_status "Using region: $REGION and project: $PROJECT_ID"

gcloud artifacts repositories create docker-repo \
    --repository-format=docker \
    --location=$REGION \
    --description="Docker repository"

print_success "Docker repository created successfully!"

print_step "Step 1.2: Download and Load Flask Telemetry Image"
print_status "Downloading Flask telemetry application..."
wget https://storage.googleapis.com/spls/gsp1024/flask_telemetry.zip

print_status "Extracting and loading Docker image..."
unzip flask_telemetry.zip
docker load -i flask_telemetry.tar
print_success "Flask telemetry image loaded successfully!"

print_step "Step 1.3: Configure Docker Authentication"
print_status "Configuring Docker to authenticate with Artifact Registry..."
gcloud auth configure-docker $REGION-docker.pkg.dev
print_success "Docker authentication configured!"

print_step "Step 1.4: Tag and Push Image to Artifact Registry"
print_status "Tagging image for Artifact Registry..."
docker tag gcr.io/ops-demo-330920/flask_telemetry:61a2a7aabc7077ef474eb24f4b69faeab47deed9 \
    $REGION-docker.pkg.dev/$PROJECT_ID/docker-repo/flask-telemetry:v1

print_status "Pushing image to Artifact Registry..."
docker push $REGION-docker.pkg.dev/$PROJECT_ID/docker-repo/flask-telemetry:v1
print_success "Image pushed to Artifact Registry successfully!"

echo -e "\n${GREEN}✓ TASK 1 COMPLETED: Docker repository created and image pushed!${NC}"

# =============================================================================
# TASK 2: SETUP A GOOGLE KUBERNETES ENGINE CLUSTER
# =============================================================================
print_task "2. Setup a Google Kubernetes Engine Cluster"

print_step "Step 2.1: Create GKE Cluster with Managed Prometheus"
print_status "Creating GKE cluster with managed Prometheus enabled..."
print_warning "This may take several minutes to complete..."
gcloud beta container clusters create gmp-cluster \
    --num-nodes=1 \
    --zone $ZONE \
    --enable-managed-prometheus
print_success "GKE cluster created successfully!"

print_step "Step 2.2: Authenticate to the Cluster"
print_status "Getting cluster credentials..."
gcloud container clusters get-credentials gmp-cluster --zone $ZONE
print_success "Cluster authentication completed!"

echo -e "\n${GREEN}✓ TASK 2 COMPLETED: GKE cluster with managed Prometheus is ready!${NC}"

# =============================================================================
# TASK 3: DEPLOY THE PROMETHEUS SERVICE
# =============================================================================
print_task "3. Deploy the Prometheus Service"

print_step "Step 3.1: Create Namespace"
print_status "Creating gmp-test namespace..."
kubectl create ns gmp-test
print_success "Namespace created successfully!"

print_step "Step 3.2: Verify Prometheus Deployment"
print_status "Checking Prometheus components..."
kubectl get pods -n gmp-system
print_success "Prometheus service verification completed!"

echo -e "\n${GREEN}✓ TASK 3 COMPLETED: Prometheus service namespace created!${NC}"

# =============================================================================
# TASK 4: DEPLOY THE APPLICATION
# =============================================================================
print_task "4. Deploy the Application"

print_step "Step 4.1: Download Application Configuration"
print_status "Downloading GMP Prometheus setup files..."
wget https://storage.googleapis.com/spls/gsp1024/gmp_prom_setup.zip
unzip gmp_prom_setup.zip
cd gmp_prom_setup
print_success "Application configuration downloaded!"

print_step "Step 4.2: Update Flask Deployment Configuration"
print_status "Updating flask_deployment.yaml with correct image name..."

# Create a backup and update the deployment file
cp flask_deployment.yaml flask_deployment.yaml.backup

# Replace the placeholder with actual image name
sed -i "s|<ARTIFACT REGISTRY IMAGE NAME>|$REGION-docker.pkg.dev/$PROJECT_ID/docker-repo/flask-telemetry:v1|g" flask_deployment.yaml

echo -e "${CYAN}Updated image name to: ${WHITE}$REGION-docker.pkg.dev/$PROJECT_ID/docker-repo/flask-telemetry:v1${NC}"
print_success "Deployment configuration updated!"

print_step "Step 4.3: Deploy Flask Application"
print_status "Deploying Flask application..."
kubectl -n gmp-test apply -f flask_deployment.yaml

print_status "Deploying Flask service..."
kubectl -n gmp-test apply -f flask_service.yaml
print_success "Flask application deployed successfully!"

print_step "Step 4.4: Wait for Service to be Ready"
print_status "Waiting for LoadBalancer to get external IP..."
kubectl -n gmp-test get services --watch &
WATCH_PID=$!

# Wait for external IP
while true; do
    EXTERNAL_IP=$(kubectl get services -n gmp-test -o jsonpath='{.items[*].status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ ! -z "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
        kill $WATCH_PID 2>/dev/null
        break
    fi
    echo "Waiting for external IP..."
    sleep 10
done

echo -e "${CYAN}External IP: ${WHITE}$EXTERNAL_IP${NC}"

print_step "Step 4.5: Verify Application Metrics"
print_status "Testing metrics endpoint..."
url=$(kubectl get services -n gmp-test -o jsonpath='{.items[*].status.loadBalancer.ingress[0].ip}')

# Wait for the service to be fully ready
print_status "Waiting for service to be fully deployed..."
for i in {1..30}; do
    if curl -s $url/metrics >/dev/null; then
        break
    fi
    echo "Attempt $i: Service not ready yet, waiting..."
    sleep 10
done

print_status "Displaying metrics output..."
curl $url/metrics
print_success "Metrics endpoint verified!"

print_step "Step 4.6: Deploy Prometheus Monitoring Configuration"
print_status "Applying PodMonitoring configuration..."
kubectl -n gmp-test apply -f prom_deploy.yaml
print_success "Prometheus monitoring configured!"

print_step "Step 4.7: Generate Application Load"
print_status "Generating load on the application for 2 minutes..."
timeout 120 bash -c -- 'while true; do curl $(kubectl get services -n gmp-test -o jsonpath="{.items[*].status.loadBalancer.ingress[0].ip}"); sleep $((RANDOM % 4)) ; done'
print_success "Load generation completed!"

echo -e "\n${GREEN}✓ TASK 4 COMPLETED: Flask application deployed and monitored!${NC}"

# =============================================================================
# TASK 5: OBSERVE THE APP VIA METRICS
# =============================================================================
print_task "5. Observe the App via Metrics"

print_step "Step 5.1: Create Custom Monitoring Dashboard"
print_status "Creating Prometheus dashboard..."

gcloud monitoring dashboards create --config='''
{
  "category": "CUSTOM",
  "displayName": "Prometheus Dashboard Example",
  "mosaicLayout": {
    "columns": 12,
    "tiles": [
      {
        "height": 4,
        "widget": {
          "title": "prometheus/flask_http_request_total/counter [MEAN]",
          "xyChart": {
            "chartOptions": {
              "mode": "COLOR"
            },
            "dataSets": [
              {
                "minAlignmentPeriod": "60s",
                "plotType": "LINE",
                "targetAxis": "Y1",
                "timeSeriesQuery": {
                  "apiSource": "DEFAULT_CLOUD",
                  "timeSeriesFilter": {
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "crossSeriesReducer": "REDUCE_NONE",
                      "perSeriesAligner": "ALIGN_RATE"
                    },
                    "filter": "metric.type=\"prometheus.googleapis.com/flask_http_request_total/counter\" resource.type=\"prometheus_target\"",
                    "secondaryAggregation": {
                      "alignmentPeriod": "60s",
                      "crossSeriesReducer": "REDUCE_MEAN",
                      "groupByFields": [
                        "metric.label.\"status\""
                      ],
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                }
              }
            ],
            "thresholds": [],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "y1Axis",
              "scale": "LINEAR"
            }
          }
        },
        "width": 6,
        "xPos": 0,
        "yPos": 0
      }
    ]
  }
}
'''

print_success "Dashboard created successfully!"

print_step "Step 5.2: Dashboard Access Information"
echo -e "${CYAN}Dashboard Access:${NC}"
echo -e "${WHITE}1. Go to Google Cloud Console${NC}"
echo -e "${WHITE}2. Search for 'Monitoring Dashboard' in the search bar${NC}"
echo -e "${WHITE}3. Click on 'Dashboards' from the search results${NC}"
echo -e "${WHITE}4. Look for 'Prometheus Dashboard Example' in the dashboard list${NC}"
echo -e "${WHITE}5. Click on the dashboard to view the metrics${NC}"

print_step "Step 5.3: Verify Resources"
print_status "Listing deployed resources for verification..."
echo -e "${YELLOW}Namespace pods:${NC}"
kubectl get pods -n gmp-test

echo -e "\n${YELLOW}Services:${NC}"
kubectl get services -n gmp-test

echo -e "\n${YELLOW}PodMonitoring:${NC}"
kubectl get podmonitoring -n gmp-test

echo -e "\n${GREEN}✓ TASK 5 COMPLETED: Monitoring dashboard created and configured!${NC}"

print_success "All lab tasks completed successfully! 🎉"