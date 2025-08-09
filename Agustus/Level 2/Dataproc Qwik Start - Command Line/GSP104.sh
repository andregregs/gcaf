#!/bin/bash

# Google Cloud Dataproc Cluster and Job Submission - Complete Script
# This script automates the creation of a Dataproc cluster and job submission

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
# TASK 1: CREATE A CLUSTER
# =============================================================================
print_task "1. Create a Cluster"

print_step "Step 1.1: Enable Required APIs"
print_status "Enabling Dataproc and Compute Engine APIs..."
gcloud services enable dataproc.googleapis.com
gcloud services enable compute.googleapis.com
print_success "Required APIs enabled!"

print_step "Step 1.2: Grant Required IAM Roles"
print_status "Adding necessary IAM roles for the current user..."
CURRENT_USER=$(gcloud config get-value account)
echo -e "${CYAN}Current User: ${WHITE}$CURRENT_USER${NC}"

# Add Dataproc Editor role
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="user:$CURRENT_USER" \
    --role="roles/dataproc.editor"

# Add Compute Admin role  
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="user:$CURRENT_USER" \
    --role="roles/compute.admin"

# Add Service Account User role
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="user:$CURRENT_USER" \
    --role="roles/iam.serviceAccountUser"

print_success "IAM roles configured!"

print_step "Step 1.3: Set Dataproc Region"
print_status "Setting Dataproc region to: $REGION"
gcloud config set dataproc/region $REGION
print_success "Dataproc region configured!"

print_step "Step 1.4: Get Project Information"
print_status "Retrieving project ID and project number..."
PROJECT_ID=$(gcloud config get-value project) && \
gcloud config set project $PROJECT_ID

PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')

echo -e "${CYAN}Project ID: ${WHITE}$PROJECT_ID${NC}"
echo -e "${CYAN}Project Number: ${WHITE}$PROJECT_NUMBER${NC}"
print_success "Project information retrieved!"

print_step "Step 1.5: Configure Service Account Permissions"
print_status "Adding Storage Admin role to Compute Engine default service account..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --role=roles/storage.admin
print_success "Service account permissions configured!"

print_step "Step 1.6: Enable Private Google Access"
print_status "Enabling Private Google Access on default subnetwork..."
gcloud compute networks subnets update default \
  --region=$REGION \
  --enable-private-ip-google-access
print_success "Private Google Access enabled!"

print_step "Step 1.7: Create Dataproc Cluster"
print_status "Creating Dataproc cluster 'example-cluster'..."
print_warning "This may take several minutes to complete..."

if gcloud dataproc clusters create example-cluster \
  --worker-boot-disk-size 500 \
  --worker-machine-type=e2-standard-4 \
  --master-machine-type=e2-standard-4 \
  --zone=$ZONE; then
    print_success "Dataproc cluster created successfully!"
else
    print_error "Failed to create Dataproc cluster"
    exit 1
fi

print_step "Step 1.8: Verify Cluster Status"
print_status "Checking cluster status..."
if CLUSTER_STATE=$(gcloud dataproc clusters describe example-cluster --region=$REGION --format="value(status.state)" 2>/dev/null); then
    echo -e "${CYAN}Cluster State: ${WHITE}$CLUSTER_STATE${NC}"
    print_success "Cluster verification completed!"
else
    print_warning "Could not verify cluster status, but continuing..."
fi

echo -e "\n${GREEN}✓ TASK 1 COMPLETED: Dataproc cluster 'example-cluster' is ready!${NC}"

# =============================================================================
# TASK 2: SUBMIT A JOB
# =============================================================================
print_task "2. Submit a Job"

print_step "Step 2.1: Submit Spark Pi Calculation Job"
print_status "Submitting Spark job to calculate pi value..."
print_status "Job parameters: 1000 tasks for pi calculation"

if gcloud dataproc jobs submit spark \
  --cluster example-cluster \
  --region=$REGION \
  --class org.apache.spark.examples.SparkPi \
  --jars file:///usr/lib/spark/examples/jars/spark-examples.jar \
  -- 1000; then
    print_success "Spark job submitted and completed successfully!"
else
    print_error "Failed to submit Spark job"
    exit 1
fi

print_step "Step 2.2: Job Execution Summary"
echo -e "${CYAN}Job Details:${NC}"
echo -e "${WHITE}• Cluster: example-cluster${NC}"
echo -e "${WHITE}• Job Type: Spark${NC}"
echo -e "${WHITE}• Application: SparkPi (pi calculation)${NC}"
echo -e "${WHITE}• Tasks: 1000${NC}"
echo -e "${WHITE}• Expected Output: Pi is roughly 3.14...${NC}"

print_step "Step 2.3: List Recent Jobs"
print_status "Displaying recent Dataproc jobs..."
if gcloud dataproc jobs list --region=$REGION --limit=5 2>/dev/null; then
    print_success "Job listing completed!"
else
    print_warning "Could not list jobs, but job submission was successful"
fi

echo -e "\n${GREEN}✓ TASK 2 COMPLETED: Spark job executed successfully!${NC}"

print_success "All lab tasks completed successfully! 🎉"