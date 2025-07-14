#!/bin/bash

# Colors for better output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Google Cloud SQL Server Setup ===${NC}\n"

# Check authentication
echo -e "${CYAN}Checking authentication...${NC}"
gcloud auth list

# Setup environment variables
echo -e "\n${CYAN}Setting up environment variables...${NC}"
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export PROJECT_ID=$(gcloud config get-value project)

echo "Zone: $ZONE"
echo "Project ID: $PROJECT_ID"

# Create SQL Server instance
echo -e "\n${GREEN}Creating SQL Server 2022 Windows instance...${NC}"
echo -e "${YELLOW}This may take several minutes...${NC}"

gcloud compute instances create sqlserver-lab \
  --zone=$ZONE \
  --project=$DEVSHELL_PROJECT_ID \
  --image-family=sql-2022-web-windows-2022 \
  --image-project=windows-sql-cloud \
  --machine-type=e2-medium \
  --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
  --create-disk=auto-delete=yes,boot=yes,device-name=sqlserver-lab,image=projects/windows-sql-cloud/global/images/sql-2022-web-windows-2022-dc-v20240711,mode=rw,size=50,type=pd-balanced

# Wait for instance to be fully ready
echo -e "\n${YELLOW}Waiting for Windows instance to be fully ready...${NC}"
echo -e "${YELLOW}This may take 3-5 minutes for Windows to complete startup...${NC}"
sleep 180  # Wait 3 minutes for Windows to boot

# Check instance status
echo -e "\n${CYAN}Checking instance status...${NC}"
gcloud compute instances describe sqlserver-lab --zone=$ZONE --format="value(status)"

# Reset Windows password with retry logic
echo -e "\n${GREEN}Resetting Windows password for remote access...${NC}"
echo -e "${YELLOW}Note: If this fails, wait a few more minutes and try manually:${NC}"
echo -e "${YELLOW}gcloud compute reset-windows-password sqlserver-lab --zone=$ZONE${NC}"

# Try password reset
if gcloud compute reset-windows-password sqlserver-lab --zone=$ZONE --quiet; then
    echo -e "\n${GREEN}Password reset successful!${NC}"
else
    echo -e "\n${YELLOW}Password reset failed. This is common with new Windows instances.${NC}"
    echo -e "${YELLOW}Please wait 2-3 more minutes and run this command manually:${NC}"
    echo -e "${CYAN}gcloud compute reset-windows-password sqlserver-lab --zone=$ZONE${NC}"
fi

echo -e "\n${GREEN}Instance creation completed successfully!${NC}"
echo -e "${BLUE}===============================================${NC}"
echo -e "${CYAN}Your SQL Server 2022 instance 'sqlserver-lab' is created!${NC}"
echo -e "${CYAN}If password reset failed, wait a few minutes and try again.${NC}"
echo -e "${CYAN}Windows instances need extra time to fully initialize.${NC}"
echo -e "${BLUE}===============================================${NC}"