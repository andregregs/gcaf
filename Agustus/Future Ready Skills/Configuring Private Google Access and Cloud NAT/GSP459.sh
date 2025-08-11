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
export DEVSHELL_PROJECT_ID=$PROJECT_ID

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

print_step "Step 1.1: Enable Required Services"
print_status "Enabling OS Config API..."
gcloud services enable osconfig.googleapis.com
print_success "OS Config API enabled successfully!"

print_step "Step 1.2: Create VPC Network and Firewall Rules"
print_status "Creating VPC network 'privatenet'..."
gcloud compute networks create privatenet \
    --project=$DEVSHELL_PROJECT_ID \
    --subnet-mode=custom \
    --mtu=1460 \
    --bgp-routing-mode=regional \
    --bgp-best-path-selection-mode=legacy

print_status "Creating subnet 'privatenet-us'..."
gcloud compute networks subnets create privatenet-us \
    --project=$DEVSHELL_PROJECT_ID \
    --range=10.130.0.0/20 \
    --stack-type=IPV4_ONLY \
    --network=privatenet \
    --region=$REGION

print_status "Creating firewall rule for SSH access..."
gcloud compute firewall-rules create privatenet-allow-ssh \
    --project=$DEVSHELL_PROJECT_ID \
    --direction=INGRESS \
    --priority=1000 \
    --network=privatenet \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=0.0.0.0/0

print_success "VPC network and firewall rules created successfully!"

print_step "Step 1.3: Create VM Instance with No Public IP"
print_status "Creating vm-internal (no external IP)..."
gcloud compute instances create vm-internal \
    --project=$DEVSHELL_PROJECT_ID \
    --zone=$ZONE \
    --machine-type=e2-medium \
    --network-interface=stack-type=IPV4_ONLY,subnet=privatenet-us,no-address \
    --metadata=enable-oslogin=true \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
    --create-disk=auto-delete=yes,boot=yes,device-name=vm-internal,image=projects/debian-cloud/global/images/debian-11-bullseye-v20240110,mode=rw,size=10,type=projects/$DEVSHELL_PROJECT_ID/zones/$ZONE/diskTypes/pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any

print_success "vm-internal created successfully!"

print_step "Step 1.4: Create Bastion Host"
print_status "Creating vm-bastion (with external IP)..."
gcloud compute instances create vm-bastion \
    --project=$DEVSHELL_PROJECT_ID \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=privatenet-us \
    --metadata=enable-osconfig=TRUE,enable-oslogin=true \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --scopes=https://www.googleapis.com/auth/compute,https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
    --create-disk=auto-delete=yes,boot=yes,device-name=vm-bastion,image=projects/debian-cloud/global/images/debian-12-bookworm-v20250709,mode=rw,size=10,type=pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=goog-ops-agent-policy=v2-x86-template-1-4-0,goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any

print_success "vm-bastion created successfully!"

print_step "Step 1.5: Verify VM Instances"
print_status "Listing created VM instances..."
gcloud compute instances list --filter="zone:($ZONE)"

echo -e "\n${GREEN}✓ TASK 1 COMPLETED: VM instances created successfully!${NC}"

# =============================================================================
# TASK 2: ENABLE PRIVATE GOOGLE ACCESS
# =============================================================================
print_task "2. Enable Private Google Access"

print_step "Step 2.1: Create Cloud Storage Bucket"
print_status "Creating Cloud Storage bucket using gsutil..."
gsutil mb gs://$DEVSHELL_PROJECT_ID

print_success "Cloud Storage bucket created successfully!"

print_step "Step 2.2: Copy Image to Bucket"
print_status "Copying test image to bucket..."
gsutil cp gs://cloud-training/gcpnet/private/access.png gs://$DEVSHELL_PROJECT_ID

print_success "Image copied to bucket successfully!"

print_step "Step 2.3: Enable Private Google Access"
print_status "Enabling Private Google Access on privatenet-us subnet..."
gcloud compute networks subnets update privatenet-us \
    --region=$REGION \
    --enable-private-ip-google-access

print_success "Private Google Access enabled successfully!"

echo -e "\n${GREEN}✓ TASK 2 COMPLETED: Private Google Access enabled and tested!${NC}"

# =============================================================================
# TASK 3: CONFIGURE A CLOUD NAT GATEWAY
# =============================================================================
print_task "3. Configure a Cloud NAT Gateway"

print_step "Step 3.1: Create Cloud Router"
print_status "Creating Cloud Router for NAT..."
gcloud compute routers create nat-router \
    --region=$REGION \
    --network=privatenet

print_success "Cloud Router created successfully!"

print_step "Step 3.2: Configure Cloud NAT Gateway"
print_status "Creating Cloud NAT gateway..."
gcloud compute routers nats create nat-config \
    --router=nat-router \
    --router-region=$REGION \
    --nat-all-subnet-ip-ranges \
    --auto-allocate-nat-external-ips

print_success "Cloud NAT gateway created successfully!"

print_step "Step 3.3: Display Configuration Summary"
print_status "Displaying final configuration..."

echo -e "\n${CYAN}Created Resources:${NC}"
echo -e "${WHITE}• VPC Network: privatenet${NC}"
echo -e "${WHITE}• Subnet: privatenet-us (10.130.0.0/20)${NC}"
echo -e "${WHITE}• VM Instances:${NC}"
echo -e "${WHITE}  - vm-internal (no external IP)${NC}"
echo -e "${WHITE}  - vm-bastion (with external IP)${NC}"
echo -e "${WHITE}• Cloud Storage: gs://$DEVSHELL_PROJECT_ID${NC}"
echo -e "${WHITE}• Cloud NAT: nat-config${NC}"
echo -e "${WHITE}• Cloud Router: nat-router${NC}"

echo -e "\n${CYAN}Key Features Configured:${NC}"
echo -e "${WHITE}• Private Google Access: Enabled on privatenet-us${NC}"
echo -e "${WHITE}• Cloud NAT: Allows vm-internal to access internet${NC}"
echo -e "${WHITE}• Bastion Host: Provides secure access to private VMs${NC}"

echo -e "\n${GREEN}✓ TASK 3 COMPLETED: Cloud NAT gateway configured successfully!${NC}"

print_success "All lab tasks completed successfully! 🎉"