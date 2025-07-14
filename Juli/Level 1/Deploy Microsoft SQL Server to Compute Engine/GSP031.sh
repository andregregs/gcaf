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

# Reset Windows password
echo -e "\n${GREEN}Resetting Windows password for remote access...${NC}"
gcloud compute reset-windows-password sqlserver-lab \
  --zone=$ZONE \
  --quiet

echo -e "\n${GREEN}All operations completed successfully!${NC}"
echo -e "${BLUE}======================================${NC}"
echo -e "${CYAN}Your SQL Server 2022 instance 'sqlserver-lab' is ready!${NC}"
echo -e "${CYAN}Use the credentials above to connect via RDP.${NC}"
echo -e "${BLUE}======================================${NC}"