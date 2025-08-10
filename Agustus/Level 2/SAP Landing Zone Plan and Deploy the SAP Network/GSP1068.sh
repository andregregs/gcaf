#!/bin/bash

# SAP VPC Network Infrastructure Setup - Complete Script
# This script automates the setup of VPC network infrastructure for SAP workloads

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
# TASK 1: CREATE VPC NETWORK
# =============================================================================
print_task "1. Create VPC Network"

print_step "Step 1.1: Create Custom VPC Network"
print_status "Creating VPC network 'xall-vpc--vpc-01'..."

gcloud compute networks create xall-vpc--vpc-01 \
    --description="XYZ-all VPC network = Standard VPC network - 01" \
    --subnet-mode=custom \
    --bgp-routing-mode=global \
    --mtu=1460

print_success "VPC network created successfully!"

echo -e "\n${GREEN}✓ TASK 1 COMPLETED: VPC network created!${NC}"

# =============================================================================
# TASK 2: CREATE VPC SUBNET
# =============================================================================
print_task "2. Create VPC Subnet"

print_step "Step 2.1: Create VPC Subnet"
print_status "Creating subnet 'xgl-subnet--cerps-bau-nonprd--be1-01'..."

gcloud compute networks subnets create xgl-subnet--cerps-bau-nonprd--be1-01 \
    --description="XYZ-Global subnet = CERPS-BaU-NonProd - Belgium 1 (GCP) - 01" \
    --network=xall-vpc--vpc-01 \
    --region=$REGION \
    --range=10.1.1.0/24 \
    --enable-private-ip-google-access \
    --enable-flow-logs

print_success "VPC subnet created successfully!"

echo -e "\n${GREEN}✓ TASK 2 COMPLETED: VPC subnet created!${NC}"

# =============================================================================
# TASK 3: CREATE VPC FIREWALL RULES - USER ACCESS
# =============================================================================
print_task "3. Create VPC Firewall Rules - User Access"

print_step "Step 3.1: Create Linux Access Firewall Rule"
print_status "Creating firewall rule for Linux access..."

gcloud compute firewall-rules create xall-vpc--vpc-01--xall-fw--user--a--linux--v01 \
    --description="xall-vpc--vpc-01 - XYZ-all firewall rule = User access - ALLOW standard linux access - version 01" \
    --network=xall-vpc--vpc-01 \
    --priority=1000 \
    --direction=ingress \
    --action=allow \
    --target-tags=xall-vpc--vpc-01--xall-fw--user--a--linux--v01 \
    --source-ranges=0.0.0.0/0 \
    --rules=tcp:22,icmp

print_success "Linux access firewall rule created!"

print_step "Step 3.2: Create Windows Access Firewall Rule"
print_status "Creating firewall rule for Windows access..."

gcloud compute firewall-rules create xall-vpc--vpc-01--xall-fw--user--a--windows--v01 \
    --description="xall-vpc--vpc-01 - XYZ-all firewall rule = User access - ALLOW standard windows access - version 01" \
    --network=xall-vpc--vpc-01 \
    --priority=1000 \
    --direction=ingress \
    --action=allow \
    --target-tags=xall-vpc--vpc-01--xall-fw--user--a--windows--v01 \
    --source-ranges=0.0.0.0/0 \
    --rules=tcp:3389,icmp

print_success "Windows access firewall rule created!"

print_step "Step 3.3: Create SAPGUI Access Firewall Rule"
print_status "Creating firewall rule for SAPGUI access..."

gcloud compute firewall-rules create xall-vpc--vpc-01--xall-fw--user--a--sapgui--v01 \
    --description="xall-vpc--vpc-01 - XYZ-all firewall rule = User access - ALLOW SAPGUI access - version 01" \
    --network=xall-vpc--vpc-01 \
    --priority=1000 \
    --direction=ingress \
    --action=allow \
    --target-tags=xall-vpc--vpc-01--xall-fw--user--a--sapgui--v01 \
    --source-ranges=0.0.0.0/0 \
    --rules=tcp:3200-3299,tcp:3600-3699

print_success "SAPGUI access firewall rule created!"

print_step "Step 3.4: Create SAP Fiori Access Firewall Rule"
print_status "Creating firewall rule for SAP Fiori access..."

gcloud compute firewall-rules create xall-vpc--vpc-01--xall-fw--user--a--sap-fiori--v01 \
    --description="xall-vpc--vpc-01 - XYZ-all firewall rule = User access - ALLOW SAP Fiori access - version 01" \
    --network=xall-vpc--vpc-01 \
    --priority=1000 \
    --direction=ingress \
    --action=allow \
    --target-tags=xall-vpc--vpc-01--xall-fw--user--a--sap-fiori--v01 \
    --source-ranges=0.0.0.0/0 \
    --rules=tcp:80,tcp:8000-8099,tcp:443,tcp:4300-44300

print_success "SAP Fiori access firewall rule created!"

echo -e "\n${GREEN}✓ TASK 3 COMPLETED: User access firewall rules created!${NC}"

# =============================================================================
# TASK 4: CREATE VPC FIREWALL RULES - ENVIRONMENT ACCESS
# =============================================================================
print_task "4. Create VPC Firewall Rules - Environment Access"

print_step "Step 4.1: Create Environment Wide Access Firewall Rule"
print_status "Creating firewall rule for environment wide access..."

gcloud compute firewall-rules create xall-vpc--vpc-01--xgl-fw--cerps-bau-dev--a-env--v01 \
    --description="xall-vpc--vpc-01 - XYZ-Global firewall rule = CERPS-BaU-Dev - ALLOW environment wide access - version 01" \
    --network=xall-vpc--vpc-01 \
    --priority=1000 \
    --direction=ingress \
    --action=allow \
    --target-tags=xall-vpc--vpc-01--xgl-fw--cerps-bau-dev--a-env--v01 \
    --source-tags=xall-vpc--vpc-01--xgl-fw--cerps-bau-dev--a-env--v01 \
    --rules=tcp:3200-3299,tcp:3300-3399,tcp:4800-4899,tcp:80,tcp:8000-8099,tcp:443,tcp:44300-44399,tcp:3600-3699,tcp:8100-8199,tcp:44400-44499,tcp:50000-59999,tcp:30000-39999,tcp:4300-4399,tcp:40000-49999,tcp:1128-1129,tcp:5050,tcp:8000-8499,tcp:515,icmp

print_success "Environment wide access firewall rule created!"

echo -e "\n${GREEN}✓ TASK 4 COMPLETED: Environment access firewall rule created!${NC}"

# =============================================================================
# TASK 5: CREATE VPC FIREWALL RULES - SYSTEM ACCESS
# =============================================================================
print_task "5. Create VPC Firewall Rules - System Access"

print_step "Step 5.1: Create System Wide Access Firewall Rule"
print_status "Creating firewall rule for SAP S4 system wide access..."

gcloud compute firewall-rules create xall-vpc--vpc-01--xgl-fw--cerps-bau-dev--a-ds4--v01 \
    --description="xall-vpc--vpc-01 - XYZ-Global firewall rule = CERPS-BaU-Dev - ALLOW SAP S4 (DS4) system wide access - version 01" \
    --network=xall-vpc--vpc-01 \
    --priority=1000 \
    --direction=ingress \
    --action=allow \
    --target-tags=xall-vpc--vpc-01--xgl-fw--cerps-bau-dev--a-ds4--v01 \
    --source-tags=xall-vpc--vpc-01--xgl-fw--cerps-bau-dev--a-ds4--v01 \
    --rules=tcp,udp,icmp

print_success "System wide access firewall rule created!"

echo -e "\n${GREEN}✓ TASK 5 COMPLETED: System access firewall rule created!${NC}"

# =============================================================================
# TASK 6: RESERVE STATIC INTERNAL IP ADDRESSES
# =============================================================================
print_task "6. Reserve Static Internal IP Addresses"

print_step "Step 6.1: Reserve IP for SAP HANA 1 (DH1)"
print_status "Reserving IP address for d-cerpshana1..."

gcloud compute addresses create xgl-ip-address--cerps-bau-dev--dh1--d-cerpshana1 \
    --description="XYZ-Global reserved IP address = CERPS-BaU-Dev - SAP HANA 1 (DH1) - d-cerpshana1" \
    --region=$REGION \
    --subnet=xgl-subnet--cerps-bau-nonprd--be1-01 \
    --addresses=10.1.1.100

print_success "IP address reserved for SAP HANA 1!"

print_step "Step 6.2: Reserve IP for SAP S4 Database (DS4)"
print_status "Reserving IP address for d-cerpss4db..."

gcloud compute addresses create xgl-ip-address--cerps-bau-dev--ds4--d-cerpss4db \
    --description="XYZ-Global reserved IP address = CERPS-BaU-Dev - SAP S4 (DS4) - d-cerpss4db" \
    --region=$REGION \
    --subnet=xgl-subnet--cerps-bau-nonprd--be1-01 \
    --addresses=10.1.1.101

print_success "IP address reserved for SAP S4 Database!"

print_step "Step 6.3: Reserve IP for SAP S4 SCS (DS4)"
print_status "Reserving IP address for d-cerpss4scs..."

gcloud compute addresses create xgl-ip-address--cerps-bau-dev--ds4--d-cerpss4scs \
    --description="XYZ-Global reserved IP address = CERPS-BaU-Dev - SAP S4 (DS4) - d-cerpss4scs" \
    --region=$REGION \
    --subnet=xgl-subnet--cerps-bau-nonprd--be1-01 \
    --addresses=10.1.1.102

print_success "IP address reserved for SAP S4 SCS!"

print_step "Step 6.4: Reserve IP for SAP S4 App Server 1 (DS4)"
print_status "Reserving IP address for d-cerpss4app1..."

gcloud compute addresses create xgl-ip-address--cerps-bau-dev--ds4--d-cerpss4app1 \
    --description="XYZ-Global reserved IP address = CERPS-BaU-Dev - SAP S4 (DS4) - d-cerpss4app1" \
    --region=$REGION \
    --subnet=xgl-subnet--cerps-bau-nonprd--be1-01 \
    --addresses=10.1.1.103

print_success "IP address reserved for SAP S4 App Server 1!"

echo -e "\n${GREEN}✓ TASK 6 COMPLETED: Static internal IP addresses reserved!${NC}"

# =============================================================================
# TASK 7: CREATE CLOUD NAT SERVICES
# =============================================================================
print_task "7. Create Cloud NAT Services"

print_step "Step 7.1: Create Cloud Router"
print_status "Creating Cloud Router for NAT gateway..."

gcloud compute routers create xall-vpc--vpc-01--xall-router--shared-nat--de1-01 \
    --description="xall-vpc--vpc-01 - XYZ-Global router = Shared NAT - Germany 1 (GCP) - 01" \
    --region=$REGION \
    --network=xall-vpc--vpc-01

print_success "Cloud Router created successfully!"

print_step "Step 7.2: Create Cloud NAT Gateway"
print_status "Creating Cloud NAT gateway..."

gcloud compute routers nats create xall-vpc--vpc-01--xall-nat-gw--shared-nat--de1-01 \
    --region=$REGION \
    --router=xall-vpc--vpc-01--xall-router--shared-nat--de1-01 \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges \
    --enable-logging

print_success "Cloud NAT gateway created successfully!"

echo -e "\n${GREEN}✓ TASK 7 COMPLETED: Cloud NAT services created!${NC}"

# =============================================================================
# FINAL VERIFICATION
# =============================================================================
print_step "Final Infrastructure Verification"

print_status "Verifying deployed resources..."

echo -e "\n${YELLOW}VPC Networks:${NC}"
gcloud compute networks list --filter="name:xall-vpc--vpc-01"

echo -e "\n${YELLOW}Subnets:${NC}"
gcloud compute networks subnets list --filter="name:xgl-subnet--cerps-bau-nonprd--be1-01"

echo -e "\n${YELLOW}Firewall Rules:${NC}"
gcloud compute firewall-rules list --filter="network:xall-vpc--vpc-01" --format="table(name,direction,priority,sourceRanges:label=SRC_RANGES,allowed[].map().firewall_rule().list():label=ALLOW,targetTags.list():label=TARGET_TAGS)"

echo -e "\n${YELLOW}Reserved IP Addresses:${NC}"
gcloud compute addresses list --filter="region:$REGION" --format="table(name,address,addressType,purpose,status)"

echo -e "\n${YELLOW}Cloud Routers:${NC}"
gcloud compute routers list --filter="region:$REGION"

echo -e "\n${YELLOW}Cloud NAT Gateways:${NC}"
gcloud compute routers nats list --router=xall-vpc--vpc-01--xall-router--shared-nat--de1-01 --region=$REGION

print_success "All lab tasks completed successfully! 🎉"