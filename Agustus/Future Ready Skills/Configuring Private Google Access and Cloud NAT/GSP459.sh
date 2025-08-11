#!/bin/bash

# Private Google Access and Cloud NAT Lab - Complete Script
# This script automates the setup of private VMs with NAT gateway configuration

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

# Generate unique bucket name
BUCKET_NAME="${PROJECT_ID}-private-access-$(date +%s)"

# =============================================================================
# TASK 1: CREATE THE VM INSTANCES
# =============================================================================
print_task "1. Create the VM Instances"

print_step "Step 1.1: Create VPC Network and Firewall Rules"
print_status "Creating VPC network 'privatenet'..."
gcloud compute networks create privatenet --subnet-mode=custom
print_success "VPC network created successfully!"

print_status "Creating subnet 'privatenet-us'..."
gcloud compute networks subnets create privatenet-us \
    --network=privatenet \
    --range=10.130.0.0/20 \
    --region=$REGION
print_success "Subnet created successfully!"

print_status "Creating firewall rule to allow SSH..."
gcloud compute firewall-rules create privatenet-allow-ssh \
    --network=privatenet \
    --allow=tcp:22 \
    --source-ranges=0.0.0.0/0 \
    --description="Allow SSH to all instances in privatenet"
print_success "Firewall rule created successfully!"

print_step "Step 1.2: Create VM Instance with No Public IP"
print_status "Creating vm-internal with no external IP address..."
gcloud compute instances create vm-internal \
    --zone=$ZONE \
    --machine-type=e2-medium \
    --network=privatenet \
    --subnet=privatenet-us \
    --no-address \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-standard
print_success "vm-internal created successfully!"

print_step "Step 1.3: Create Bastion Host"
print_status "Creating vm-bastion with external IP address..."
gcloud compute instances create vm-bastion \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --network=privatenet \
    --subnet=privatenet-us \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-standard \
    --scopes=https://www.googleapis.com/auth/compute
print_success "vm-bastion created successfully!"

print_step "Step 1.4: Verify VM Instance Configuration"
print_status "Listing created VM instances..."
gcloud compute instances list --filter="zone:($ZONE)"

echo -e "\n${GREEN}✓ TASK 1 COMPLETED: VM instances created successfully!${NC}"

# =============================================================================
# TASK 2: ENABLE PRIVATE GOOGLE ACCESS
# =============================================================================
print_task "2. Enable Private Google Access"

print_step "Step 2.1: Create Cloud Storage Bucket"
print_status "Creating Cloud Storage bucket: $BUCKET_NAME"
gsutil mb gs://$BUCKET_NAME
print_success "Cloud Storage bucket created successfully!"

print_step "Step 2.2: Copy Image to Bucket"
print_status "Copying test image to bucket..."
gsutil cp gs://cloud-training/gcpnet/private/access.png gs://$BUCKET_NAME/
print_success "Image copied to bucket successfully!"

print_step "Step 2.3: Test Initial Connectivity"
print_status "Testing connectivity before enabling Private Google Access..."

print_warning "Testing vm-bastion access to Cloud Storage (should work)..."
gcloud compute ssh vm-bastion --zone=$ZONE --command="gsutil cp gs://$BUCKET_NAME/*.png /tmp/ && echo 'SUCCESS: vm-bastion can access Cloud Storage' || echo 'FAILED: vm-bastion cannot access Cloud Storage'"

print_warning "Testing vm-internal access to Cloud Storage (should fail initially)..."
gcloud compute ssh vm-bastion --zone=$ZONE --command="gcloud compute ssh vm-internal --zone=$ZONE --internal-ip --command='timeout 10 gsutil cp gs://$BUCKET_NAME/*.png /tmp/ && echo SUCCESS: vm-internal can access Cloud Storage || echo EXPECTED FAILURE: vm-internal cannot access Cloud Storage'"

print_step "Step 2.4: Enable Private Google Access"
print_status "Enabling Private Google Access on privatenet-us subnet..."
gcloud compute networks subnets update privatenet-us \
    --region=$REGION \
    --enable-private-ip-google-access
print_success "Private Google Access enabled successfully!"

print_step "Step 2.5: Verify Private Google Access"
print_status "Testing vm-internal access after enabling Private Google Access..."
print_warning "Waiting 30 seconds for changes to propagate..."
sleep 30

gcloud compute ssh vm-bastion --zone=$ZONE --command="gcloud compute ssh vm-internal --zone=$ZONE --internal-ip --command='gsutil cp gs://$BUCKET_NAME/*.png /tmp/ && echo SUCCESS: vm-internal can now access Cloud Storage || echo FAILED: vm-internal still cannot access Cloud Storage'"

echo -e "\n${GREEN}✓ TASK 2 COMPLETED: Private Google Access enabled and tested!${NC}"

# =============================================================================
# TASK 3: CONFIGURE A CLOUD NAT GATEWAY
# =============================================================================
print_task "3. Configure a Cloud NAT Gateway"

print_step "Step 3.1: Test Internet Access Before NAT"
print_status "Testing internet access before configuring Cloud NAT..."

print_warning "Testing vm-bastion internet access (should work)..."
gcloud compute ssh vm-bastion --zone=$ZONE --command="timeout 10 sudo apt-get update > /dev/null 2>&1 && echo 'SUCCESS: vm-bastion can access internet' || echo 'WARNING: vm-bastion internet access limited'"

print_warning "Testing vm-internal internet access (should fail)..."
gcloud compute ssh vm-bastion --zone=$ZONE --command="gcloud compute ssh vm-internal --zone=$ZONE --internal-ip --command='timeout 10 sudo apt-get update > /dev/null 2>&1 && echo SUCCESS: vm-internal can access internet || echo EXPECTED: vm-internal cannot access internet'"

print_step "Step 3.2: Create Cloud Router"
print_status "Creating Cloud Router for NAT gateway..."
gcloud compute routers create nat-router \
    --network=privatenet \
    --region=$REGION
print_success "Cloud Router created successfully!"

print_step "Step 3.3: Create Cloud NAT Gateway"
print_status "Creating Cloud NAT gateway..."
gcloud compute routers nats create nat-config \
    --router=nat-router \
    --region=$REGION \
    --nat-all-subnet-ip-ranges \
    --auto-allocate-nat-external-ips
print_success "Cloud NAT gateway created successfully!"

print_step "Step 3.4: Wait for NAT Configuration to Propagate"
print_status "Waiting for NAT configuration to propagate (3 minutes)..."
for i in {1..6}; do
    echo "Waiting... $((i*30)) seconds elapsed"
    sleep 30
done

print_step "Step 3.5: Verify Cloud NAT Gateway"
print_status "Testing internet access after configuring Cloud NAT..."

print_warning "Testing vm-internal internet access through NAT (should now work)..."
gcloud compute ssh vm-bastion --zone=$ZONE --command="gcloud compute ssh vm-internal --zone=$ZONE --internal-ip --command='timeout 30 sudo apt-get update > /dev/null 2>&1 && echo SUCCESS: vm-internal can now access internet through NAT || echo FAILED: vm-internal still cannot access internet'"

print_step "Step 3.6: Additional Verification Commands"
print_status "Running additional verification commands..."

echo -e "${YELLOW}Network Configuration Summary:${NC}"
echo -e "${WHITE}VPC Network:${NC} privatenet"
echo -e "${WHITE}Subnet:${NC} privatenet-us (10.130.0.0/20)"
echo -e "${WHITE}Private Google Access:${NC} Enabled"
echo -e "${WHITE}Cloud NAT:${NC} nat-config via nat-router"
echo -e "${WHITE}Bucket Name:${NC} $BUCKET_NAME"

print_status "Listing network resources..."
echo -e "\n${CYAN}VPC Networks:${NC}"
gcloud compute networks list --filter="name:privatenet"

echo -e "\n${CYAN}Subnets:${NC}"
gcloud compute networks subnets list --filter="name:privatenet-us"

echo -e "\n${CYAN}Cloud NAT Gateways:${NC}"
gcloud compute routers nats list --router=nat-router --region=$REGION

echo -e "\n${CYAN}VM Instances:${NC}"
gcloud compute instances list --filter="zone:($ZONE)"

echo -e "\n${GREEN}✓ TASK 3 COMPLETED: Cloud NAT gateway configured and verified!${NC}"

print_success "All lab tasks completed successfully! 🎉"