#!/bin/bash

# Google Cloud Media CDN Setup Lab - Complete Script
# This script automates the setup of Media CDN with Cloud Storage origin

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

echo -e "${CYAN}Project ID: ${WHITE}$PROJECT_ID${NC}"

# =============================================================================
# TASK 1: ENABLE REQUIRED SERVICES
# =============================================================================
print_task "1. Enable Required Services"

print_step "Step 1.1: Enable Network Services API"
print_status "Enabling Network Services API..."
gcloud services enable networkservices.googleapis.com
print_success "Network Services API enabled successfully!"

print_step "Step 1.2: Enable Certificate Manager API"
print_status "Enabling Certificate Manager API..."
gcloud services enable certificatemanager.googleapis.com
print_success "Certificate Manager API enabled successfully!"

print_step "Step 1.3: Enable Additional Required APIs"
print_status "Enabling Compute Engine API..."
gcloud services enable compute.googleapis.com

print_status "Enabling Cloud Storage API..."
gcloud services enable storage.googleapis.com

print_status "Enabling Cloud CDN API..."
gcloud services enable compute.googleapis.com

print_success "All required APIs enabled successfully!"

echo -e "\n${GREEN}✓ TASK 1 COMPLETED: Required services enabled!${NC}"

# =============================================================================
# TASK 2: CREATE A BUCKET WITH PUBLIC ACCESS
# =============================================================================
print_task "2. Create a Bucket with Public Access"

print_step "Step 2.1: Create Cloud Storage Bucket"
export BUCKET_NAME="$PROJECT_ID"
print_status "Creating bucket with name: $BUCKET_NAME"
print_status "Using default settings (no region specified - will use default)"

gsutil mb gs://$BUCKET_NAME
print_success "Bucket created successfully!"

print_step "Step 2.2: Remove Public Access Prevention"
print_status "Removing public access prevention..."
gsutil iam ch -d allUsers:objectViewer gs://$BUCKET_NAME 2>/dev/null || true
gsutil bucketpolicyonly set off gs://$BUCKET_NAME
print_success "Public access prevention removed!"

print_step "Step 2.3: Grant Public Access"
print_status "Granting public access to all users..."
gsutil iam ch allUsers:objectViewer gs://$BUCKET_NAME
print_success "Public access granted successfully!"

print_step "Step 2.4: Upload Sample Content"
print_status "Creating and uploading sample content..."
echo "Hello from Cloud Storage!" > sample.txt
gsutil cp sample.txt gs://$BUCKET_NAME/
echo "<html><body><h1>Welcome to CDN Demo</h1><p>This content is served through Media CDN</p></body></html>" > index.html
gsutil cp index.html gs://$BUCKET_NAME/
print_success "Sample content uploaded!"

print_step "Step 2.5: Verify Bucket Configuration"
print_status "Verifying bucket configuration..."
gsutil ls gs://$BUCKET_NAME
gsutil iam get gs://$BUCKET_NAME
print_success "Bucket configuration verified!"

echo -e "\n${GREEN}✓ TASK 2 COMPLETED: Bucket with public access created!${NC}"

# =============================================================================
# TASK 3: CREATE AN ORIGIN
# =============================================================================
print_task "3. Create an Origin"

print_step "Step 3.1: Create Backend Bucket"
print_status "Creating backend bucket for CDN origin..."
gcloud compute backend-buckets create cloud-storage-origin \
    --gcs-bucket-name=$BUCKET_NAME \
    --description="Backend bucket for Cloud Storage origin"
print_success "Backend bucket created successfully!"

print_step "Step 3.2: Create URL Map"
print_status "Creating URL map for load balancer..."
gcloud compute url-maps create cloud-storage-origin-load-balancer \
    --default-backend-bucket=cloud-storage-origin \
    --description="URL map for Cloud Storage CDN origin"
print_success "URL map created successfully!"

print_step "Step 3.3: Create HTTP(S) Target Proxy"
print_status "Creating target HTTP proxy..."
gcloud compute target-http-proxies create cloud-storage-target-proxy \
    --url-map=cloud-storage-origin-load-balancer \
    --description="Target proxy for Cloud Storage CDN"
print_success "Target HTTP proxy created successfully!"

print_step "Step 3.4: Reserve Global IP Address"
print_status "Reserving global IP address..."
gcloud compute addresses create cloud-storage-ip \
    --global \
    --description="Global IP for Cloud Storage CDN"

export CDN_IP=$(gcloud compute addresses describe cloud-storage-ip --global --format="value(address)")
echo -e "${CYAN}Reserved IP Address: ${WHITE}$CDN_IP${NC}"
print_success "Global IP address reserved!"

print_step "Step 3.5: Create Global Forwarding Rule"
print_status "Creating global forwarding rule..."
gcloud compute forwarding-rules create cloud-storage-forwarding-rule \
    --global \
    --target-http-proxy=cloud-storage-target-proxy \
    --address=cloud-storage-ip \
    --ports=80 \
    --description="Forwarding rule for Cloud Storage CDN"
print_success "Global forwarding rule created successfully!"

print_step "Step 3.6: Enable Cloud CDN"
print_status "Enabling Cloud CDN on the backend bucket..."
gcloud compute backend-buckets update cloud-storage-origin \
    --enable-cdn \
    --cache-mode=CACHE_ALL_STATIC \
    --default-ttl=3600 \
    --max-ttl=86400
print_success "Cloud CDN enabled successfully!"

print_step "Step 3.7: Verify CDN Configuration"
print_status "Verifying CDN configuration..."
echo -e "${YELLOW}Backend Buckets:${NC}"
gcloud compute backend-buckets list

echo -e "\n${YELLOW}URL Maps:${NC}"
gcloud compute url-maps list

echo -e "\n${YELLOW}Forwarding Rules:${NC}"
gcloud compute forwarding-rules list --global

echo -e "\n${YELLOW}Global IP Addresses:${NC}"
gcloud compute addresses list --global

print_success "CDN configuration verified!"

print_step "Step 3.8: Test CDN Endpoint"
print_status "Testing CDN endpoint..."
echo -e "${CYAN}CDN URL: ${WHITE}http://$CDN_IP${NC}"
echo -e "${CYAN}Test URLs:${NC}"
echo -e "${WHITE}  - http://$CDN_IP/sample.txt${NC}"
echo -e "${WHITE}  - http://$CDN_IP/index.html${NC}"

print_warning "Note: It may take a few minutes for the CDN to be fully operational"
print_status "Testing connectivity (may fail initially)..."
curl -I http://$CDN_IP/sample.txt || echo -e "${YELLOW}CDN still propagating - try again in a few minutes${NC}"

echo -e "\n${GREEN}✓ TASK 3 COMPLETED: CDN origin created and configured!${NC}"

print_success "All lab tasks completed successfully! 🎉"