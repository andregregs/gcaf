#!/bin/bash

# Colors for better output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Google Cloud NFS Setup ===${NC}\n"

# Check authentication
echo -e "${CYAN}Checking authentication...${NC}"
gcloud auth list

# Setup environment variables
echo -e "\n${CYAN}Setting up environment variables...${NC}"
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

echo "Zone: $ZONE"
echo "Region: $REGION"

# Enable Filestore API
echo -e "\n${GREEN}Enabling Filestore API...${NC}"
gcloud services enable file.googleapis.com

# Create NFS client instance
echo -e "\n${GREEN}Creating NFS client instance...${NC}"
gcloud compute instances create nfs-client \
  --project=$DEVSHELL_PROJECT_ID \
  --zone=$ZONE \
  --machine-type=e2-medium \
  --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
  --metadata=enable-oslogin=true \
  --maintenance-policy=MIGRATE \
  --provisioning-model=STANDARD \
  --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
  --tags=http-server \
  --create-disk=auto-delete=yes,boot=yes,device-name=nfs-client,image=projects/debian-cloud/global/images/debian-11-bullseye-v20231010,mode=rw,size=10,type=projects/$DEVSHELL_PROJECT_ID/zones/$ZONE/diskTypes/pd-balanced \
  --no-shielded-secure-boot \
  --shielded-vtpm \
  --shielded-integrity-monitoring \
  --labels=goog-ec-src=vm_add-gcloud \
  --reservation-affinity=any

# Create Filestore NFS server
echo -e "\n${GREEN}Creating Filestore NFS server...${NC}"
echo -e "${YELLOW}This may take several minutes...${NC}"
gcloud filestore instances create nfs-server \
  --zone=$ZONE \
  --tier=BASIC_HDD \
  --file-share=name="vol1",capacity=1TB \
  --network=name="default"

echo -e "\n${GREEN}All operations completed successfully!${NC}"
echo -e "${BLUE}======================================${NC}"
echo -e "${CYAN}NFS setup completed:${NC}"
echo -e "${CYAN}• NFS Client: nfs-client instance${NC}"
echo -e "${CYAN}• NFS Server: nfs-server (Filestore)${NC}"
echo -e "${CYAN}• File Share: vol1 (1TB capacity)${NC}"
echo -e "${BLUE}======================================${NC}"