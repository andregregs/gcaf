#!/bin/bash

# Colors for better output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Google Cloud App Engine Deployment ===${NC}\n"

# Check authentication
echo -e "${CYAN}Checking authentication...${NC}"
gcloud auth list

# Setup environment variables
echo -e "\n${CYAN}Setting up environment variables...${NC}"
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

echo "Zone: $ZONE"
echo "Region: $REGION"

# Download sample application
echo -e "\n${GREEN}Downloading Python sample application...${NC}"
gsutil -m cp -r gs://spls/gsp067/python-docs-samples .

# Navigate to hello world app
echo -e "\n${GREEN}Navigating to hello world application...${NC}"
cd python-docs-samples/appengine/standard_python3/hello_world

# Update app.yaml to use Python 3.9
echo -e "\n${GREEN}Updating Python version to 3.9...${NC}"
sed -i "s/python37/python39/g" app.yaml

# Create requirements.txt with Flask dependencies
echo -e "\n${GREEN}Creating requirements.txt...${NC}"
cat > requirements.txt <<EOF_CP
Flask==1.1.2
itsdangerous==2.0.1
Jinja2==3.0.3
werkzeug==2.0.1
EOF_CP

# Create updated app.yaml
echo -e "\n${GREEN}Creating app.yaml configuration...${NC}"
cat > app.yaml <<EOF_CP
runtime: python39
EOF_CP

# Create App Engine application
echo -e "\n${GREEN}Creating App Engine application...${NC}"
echo -e "${YELLOW}This may take a few minutes...${NC}"
gcloud app create --region=$REGION

# Deploy application
echo -e "\n${GREEN}Deploying application to App Engine...${NC}"
echo -e "${YELLOW}This may take several minutes...${NC}"
gcloud app deploy --quiet

echo -e "\n${GREEN}All operations completed successfully!${NC}"
echo -e "${BLUE}===========================================${NC}"
echo -e "${CYAN}App Engine deployment completed:${NC}"
echo -e "${CYAN}• Application: Hello World Python app${NC}"
echo -e "${CYAN}• Runtime: Python 3.9${NC}"
echo -e "${CYAN}• Region: $REGION${NC}"
echo -e "${CYAN}• Status: Deployed and ready${NC}"
echo -e "\n${YELLOW}You can view your app at:${NC}"
echo -e "${CYAN}https://$DEVSHELL_PROJECT_ID.appspot.com${NC}"
echo -e "${BLUE}===========================================${NC}"