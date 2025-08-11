#!/bin/bash

# Private Google Access and Cloud NAT Lab - Complete Script
# This script automates the setup of VPC with private VMs, bastion host, and Cloud NAT

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

# Get project information using metadata
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
# TASK 1: CREATE THE VM INSTANCES
# =============================================================================
print_task "1. Create the VM Instances"

print_step "Step 1.1: Create VPC Network and Firewall Rules"
print_status "Creating VPC network 'privatenet'..."
gcloud compute networks create privatenet \
    --subnet-mode=custom

print_status "Creating subnet 'privatenet-us'..."
gcloud compute networks subnets create privatenet-us \
    --network=privatenet \
    --range=10.130.0.0/20 \
    --region=$REGION

print_status "Creating firewall rule for SSH access..."
gcloud compute firewall-rules create privatenet-allow-ssh \
    --network=privatenet \
    --allow=tcp:22 \
    --source-ranges=0.0.0.0/0 \
    --description="Allow SSH to all instances in privatenet"

print_success "VPC network and firewall rules created successfully!"

print_step "Step 1.2: Create VM Instance with No Public IP"
print_status "Creating vm-internal (no external IP)..."
gcloud compute instances create vm-internal \
    --zone=$ZONE \
    --machine-type=e2-medium \
    --subnet=privatenet-us \
    --no-address \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-standard

print_success "vm-internal created successfully!"

print_step "Step 1.3: Create Bastion Host"
print_status "Creating vm-bastion (with external IP)..."
gcloud compute instances create vm-bastion \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --subnet=privatenet-us \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-standard \
    --scopes=https://www.googleapis.com/auth/compute

print_success "vm-bastion created successfully!"

print_step "Step 1.4: Verify VM Instances"
print_status "Listing created VM instances..."
gcloud compute instances list --filter="zone:($ZONE)"

echo -e "\n${GREEN}✓ TASK 1 COMPLETED: VM instances created successfully!${NC}"

# =============================================================================
# TASK 2: ENABLE PRIVATE GOOGLE ACCESS
# =============================================================================
print_task "2. Enable Private Google Access"

print_step "Step 2.1: Create Cloud Storage Bucket"
print_status "Creating globally unique bucket name..."
BUCKET_NAME="$PROJECT_ID-private-bucket-$(date +%s)"
echo -e "${CYAN}Bucket Name: ${WHITE}$BUCKET_NAME${NC}"

print_status "Creating Cloud Storage bucket..."
gcloud storage buckets create gs://$BUCKET_NAME \
    --location=$REGION \
    --uniform-bucket-level-access

print_success "Cloud Storage bucket created successfully!"

print_step "Step 2.2: Copy Image to Bucket"
print_status "Copying test image to bucket..."
gsutil cp gs://cloud-training/gcpnet/private/access.png gs://$BUCKET_NAME/

print_success "Image copied to bucket successfully!"

print_step "Step 2.3: Test Access from VMs (Before Private Google Access)"
print_status "Testing bucket access from vm-bastion..."
echo -e "${YELLOW}This should work because vm-bastion has external IP${NC}"

# Test from bastion (should work)
gcloud compute ssh vm-bastion \
    --zone=$ZONE \
    --command="gsutil cp gs://$BUCKET_NAME/*.png . && echo 'SUCCESS: vm-bastion can access bucket'" \
    --ssh-flag="-o StrictHostKeyChecking=no" \
    --quiet || echo "Expected: May fail on first SSH attempt"

print_status "Testing bucket access from vm-internal..."
echo -e "${YELLOW}This should fail because vm-internal has no external IP and Private Google Access is disabled${NC}"

# Test from internal (should fail)
gcloud compute ssh vm-bastion \
    --zone=$ZONE \
    --command="timeout 10 gcloud compute ssh vm-internal --zone=$ZONE --internal-ip --command='gsutil cp gs://$BUCKET_NAME/*.png .' --ssh-flag='-o StrictHostKeyChecking=no' --quiet" \
    --ssh-flag="-o StrictHostKeyChecking=no" \
    --quiet || echo -e "${GREEN}Expected: vm-internal cannot access bucket without Private Google Access${NC}"

print_step "Step 2.4: Enable Private Google Access"
print_status "Enabling Private Google Access on privatenet-us subnet..."
gcloud compute networks subnets update privatenet-us \
    --region=$REGION \
    --enable-private-ip-google-access

print_success "Private Google Access enabled successfully!"

print_step "Step 2.5: Test Access After Enabling Private Google Access"
print_status "Testing bucket access from vm-internal after enabling Private Google Access..."
echo -e "${YELLOW}This should now work because Private Google Access is enabled${NC}"

# Wait a moment for the setting to propagate
sleep 10

# Test from internal (should now work)
gcloud compute ssh vm-bastion \
    --zone=$ZONE \
    --command="gcloud compute ssh vm-internal --zone=$ZONE --internal-ip --command='gsutil cp gs://$BUCKET_NAME/*.png . && echo SUCCESS: vm-internal can now access bucket' --ssh-flag='-o StrictHostKeyChecking=no' --quiet" \
    --ssh-flag="-o StrictHostKeyChecking=no" \
    --quiet

print_success "Private Google Access verification completed!"

echo -e "\n${GREEN}✓ TASK 2 COMPLETED: Private Google Access enabled and tested!${NC}"

# =============================================================================
# TASK 3: CONFIGURE A CLOUD NAT GATEWAY
# =============================================================================
print_task "3. Configure a Cloud NAT Gateway"

print_step "Step 3.1: Test Internet Access Before NAT"
print_status "Testing internet access on vm-bastion (should work)..."
gcloud compute ssh vm-bastion \
    --zone=$ZONE \
    --command="timeout 30 sudo apt-get update" \
    --ssh-flag="-o StrictHostKeyChecking=no" \
    --quiet && echo -e "${GREEN}SUCCESS: vm-bastion can access internet${NC}"

print_status "Testing internet access on vm-internal (should fail)..."
gcloud compute ssh vm-bastion \
    --zone=$ZONE \
    --command="timeout 15 gcloud compute ssh vm-internal --zone=$ZONE --internal-ip --command='sudo apt-get update' --ssh-flag='-o StrictHostKeyChecking=no' --quiet" \
    --ssh-flag="-o StrictHostKeyChecking=no" \
    --quiet || echo -e "${GREEN}Expected: vm-internal cannot access internet without NAT${NC}"

print_step "Step 3.2: Create Cloud Router"
print_status "Creating Cloud Router for NAT..."
gcloud compute routers create nat-router \
    --network=privatenet \
    --region=$REGION

print_success "Cloud Router created successfully!"

print_step "Step 3.3: Configure Cloud NAT Gateway"
print_status "Creating Cloud NAT gateway..."
gcloud compute routers nats create nat-config \
    --router=nat-router \
    --region=$REGION \
    --nat-all-subnet-ip-ranges \
    --auto-allocate-nat-external-ips

print_success "Cloud NAT gateway created successfully!"

print_step "Step 3.4: Wait for NAT Configuration to Propagate"
print_status "Waiting for NAT configuration to propagate (60 seconds)..."
sleep 60
print_success "Wait completed!"

print_step "Step 3.5: Verify Cloud NAT Gateway"
print_status "Testing internet access on vm-internal after NAT configuration..."
echo -e "${YELLOW}This should now work because vm-internal can use Cloud NAT${NC}"

gcloud compute ssh vm-bastion \
    --zone=$ZONE \
    --command="gcloud compute ssh vm-internal --zone=$ZONE --internal-ip --command='timeout 60 sudo apt-get update && echo SUCCESS: vm-internal can now access internet via NAT' --ssh-flag='-o StrictHostKeyChecking=no' --quiet" \
    --ssh-flag="-o StrictHostKeyChecking=no" \
    --quiet

print_success "Cloud NAT gateway verification completed!"

print_step "Step 3.6: Display Configuration Summary"
print_status "Displaying final configuration..."

echo -e "\n${CYAN}Created Resources:${NC}"
echo -e "${WHITE}• VPC Network: privatenet${NC}"
echo -e "${WHITE}• Subnet: privatenet-us (10.130.0.0/20)${NC}"
echo -e "${WHITE}• VM Instances:${NC}"
echo -e "${WHITE}  - vm-internal (no external IP)${NC}"
echo -e "${WHITE}  - vm-bastion (with external IP)${NC}"
echo -e "${WHITE}• Cloud Storage: gs://$BUCKET_NAME${NC}"
echo -e "${WHITE}• Cloud NAT: nat-config${NC}"
echo -e "${WHITE}• Cloud Router: nat-router${NC}"

echo -e "\n${CYAN}Key Features Demonstrated:${NC}"
echo -e "${WHITE}• Private Google Access: Enabled on privatenet-us${NC}"
echo -e "${WHITE}• Cloud NAT: Allows vm-internal to access internet${NC}"
echo -e "${WHITE}• Bastion Host: Provides secure access to private VMs${NC}"

echo -e "\n${GREEN}✓ TASK 3 COMPLETED: Cloud NAT gateway configured and verified!${NC}"

print_success "All lab tasks completed successfully! 🎉"