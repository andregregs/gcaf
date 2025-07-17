#!/bin/bash

# =====================================================
# Caddy Static Website on Google Cloud Run
# Complete Deployment Script
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting Caddy static website deployment to Cloud Run...${RESET}"

# =====================================================
# 1. AUTHENTICATION & ENVIRONMENT SETUP
# =====================================================
echo -e "${YELLOW}Step 1: Setting up authentication and environment...${RESET}"

# Check current authentication
gcloud auth list

# Set up environment variables
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

# Configure gcloud defaults
gcloud config set compute/region "$REGION"
gcloud config set project "$PROJECT_ID"

echo -e "${GREEN}✅ Environment configured: $PROJECT_ID | $REGION${RESET}"

# =====================================================
# 2. ENABLE REQUIRED SERVICES
# =====================================================
echo -e "${YELLOW}Step 2: Enabling required Google Cloud services...${RESET}"

gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com

echo -e "${GREEN}✅ Services enabled successfully${RESET}"

# =====================================================
# 3. CREATE ARTIFACT REGISTRY REPOSITORY
# =====================================================
echo -e "${YELLOW}Step 3: Creating Artifact Registry repository...${RESET}"

gcloud artifacts repositories create caddy-repo \
  --repository-format=docker \
  --location="$REGION" \
  --description="Docker repository for Caddy images"

echo -e "${GREEN}✅ Artifact Registry repository created${RESET}"

# =====================================================
# 4. CREATE WEBSITE FILES
# =====================================================
echo -e "${YELLOW}Step 4: Creating website files...${RESET}"

# Create HTML file
echo -e "${CYAN}Creating index.html...${RESET}"
cat > index.html <<EOF_CP
<html>
<head>
  <title>My Static Website</title>
</head>
<body>
  <div>Hello from Caddy on Cloud Run!</div>
  <p>This website is served by Caddy running in a Docker container on Google Cloud Run.</p>
</body>
</html>
EOF_CP

# Create Caddy configuration
echo -e "${CYAN}Creating Caddyfile...${RESET}"
cat > Caddyfile <<EOF_CP
:8080
root * /usr/share/caddy
file_server
EOF_CP

# Create Dockerfile
echo -e "${CYAN}Creating Dockerfile...${RESET}"
cat > Dockerfile <<EOF_CP
FROM caddy:2-alpine
WORKDIR /usr/share/caddy
COPY index.html .
COPY Caddyfile /etc/caddy/Caddyfile
EOF_CP

echo -e "${GREEN}✅ Website files created${RESET}"

# =====================================================
# 5. BUILD AND PUSH DOCKER IMAGE
# =====================================================
echo -e "${YELLOW}Step 5: Building and pushing Docker image...${RESET}"

# Define image name
IMAGE_NAME="$REGION-docker.pkg.dev/$PROJECT_ID/caddy-repo/caddy-static:latest"

echo -e "${CYAN}Building Docker image...${RESET}"
docker build -t "$IMAGE_NAME" .

echo -e "${CYAN}Pushing image to Artifact Registry...${RESET}"
docker push "$IMAGE_NAME"

echo -e "${GREEN}✅ Docker image built and pushed${RESET}"

# =====================================================
# 6. DEPLOY TO CLOUD RUN
# =====================================================
echo -e "${YELLOW}Step 6: Deploying to Google Cloud Run...${RESET}"

gcloud run deploy caddy-static \
  --region="$REGION" \
  --image="$IMAGE_NAME" \
  --platform=managed \
  --allow-unauthenticated

echo -e "${GREEN}${BOLD}🎉 Deployment Complete! Caddy static website is now live on Cloud Run.${RESET}"