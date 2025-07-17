#!/bin/bash

# =====================================================
# Artifact Registry Docker Push Setup
# Complete Docker Image Build and Push Script
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting Artifact Registry Docker setup...${RESET}"

# =====================================================
# 1. AUTHENTICATION & SERVICES
# =====================================================
echo -e "${YELLOW}Step 1: Setting up authentication and services...${RESET}"

# Check current authentication
gcloud auth list

# Enable Artifact Registry API
gcloud services enable artifactregistry.googleapis.com

echo -e "${GREEN}✅ Authentication and services configured${RESET}"

# =====================================================
# 2. ENVIRONMENT SETUP
# =====================================================
echo -e "${YELLOW}Step 2: Setting up environment variables...${RESET}"

# Set up environment variables
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

# Configure gcloud defaults
gcloud config set compute/region $REGION
gcloud config set project $PROJECT_ID

echo -e "${GREEN}✅ Environment configured: $PROJECT_ID | $REGION${RESET}"

# =====================================================
# 3. CREATE ARTIFACT REGISTRY REPOSITORY
# =====================================================
echo -e "${YELLOW}Step 3: Creating Artifact Registry repository...${RESET}"

gcloud artifacts repositories create my-docker-repo \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository"

echo -e "${GREEN}✅ Repository 'my-docker-repo' created${RESET}"

# =====================================================
# 4. CONFIGURE DOCKER AUTHENTICATION
# =====================================================
echo -e "${YELLOW}Step 4: Configuring Docker authentication...${RESET}"

gcloud auth configure-docker "$REGION"-docker.pkg.dev

echo -e "${GREEN}✅ Docker authentication configured${RESET}"

# =====================================================
# 5. CREATE SAMPLE APPLICATION
# =====================================================
echo -e "${YELLOW}Step 5: Creating sample application...${RESET}"

# Create application directory
mkdir sample-app
cd sample-app

# Create Dockerfile
echo -e "${CYAN}Creating Dockerfile...${RESET}"
echo "FROM nginx:latest" > Dockerfile

echo -e "${GREEN}✅ Sample application created${RESET}"

# =====================================================
# 6. BUILD AND PUSH DOCKER IMAGE
# =====================================================
echo -e "${YELLOW}Step 6: Building and pushing Docker image...${RESET}"

# Define image name
IMAGE_NAME="$REGION-docker.pkg.dev/$PROJECT_ID/my-docker-repo/nginx-image:latest"

echo -e "${CYAN}Building Docker image...${RESET}"
docker build -t nginx-image .

echo -e "${CYAN}Tagging image...${RESET}"
docker tag nginx-image "$IMAGE_NAME"

echo -e "${CYAN}Pushing image to Artifact Registry...${RESET}"
docker push "$IMAGE_NAME"

echo -e "${GREEN}✅ Docker image pushed successfully${RESET}"

echo -e "${GREEN}${BOLD}🎉 Complete! Docker image is now available in Artifact Registry.${RESET}"
echo -e "${CYAN}Image: $IMAGE_NAME${RESET}"