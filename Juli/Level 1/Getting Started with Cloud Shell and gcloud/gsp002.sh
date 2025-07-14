#!/bin/bash

# Simple colors for output
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=== Google Cloud Instance Setup ==="
echo

# Get zone from user
echo -e "${CYAN}Enter zone for instance:${NC}"
read -p "Zone: " ZONE

# Create compute instance
echo -e "\n${GREEN}Creating instance 'gcelab2'...${NC}"
gcloud compute instances create gcelab2 --machine-type e2-medium --zone $ZONE

# Add network tags
echo -e "\n${GREEN}Adding HTTP/HTTPS tags...${NC}"
gcloud compute instances add-tags gcelab2 --zone $ZONE --tags http-server,https-server

# Create firewall rule for HTTP
echo -e "\n${GREEN}Creating HTTP firewall rule...${NC}"
gcloud compute firewall-rules create default-allow-http \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=http-server

echo -e "\n${GREEN}Setup completed successfully!${NC}"
echo "==========================="