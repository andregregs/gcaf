#!/bin/bash

# =====================================================
# Maven Repository Setup with Artifact Registry
# Complete Maven Project Setup and Configuration Script
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting Maven repository setup with Artifact Registry...${RESET}"

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
# 3. CREATE MAVEN REPOSITORY
# =====================================================
echo -e "${YELLOW}Step 3: Creating Maven repository in Artifact Registry...${RESET}"

gcloud artifacts repositories create my-maven-repo \
    --repository-format=maven \
    --location="$REGION" \
    --description="Maven repository"

echo -e "${GREEN}✅ Maven repository created${RESET}"

# =====================================================
# 4. VERIFY REPOSITORY CREATION
# =====================================================
echo -e "${YELLOW}Step 4: Verifying repository creation...${RESET}"

echo -e "${CYAN}Listing repositories in region:${RESET}"
gcloud artifacts repositories list --location="$REGION"

echo -e "${GREEN}✅ Repository verified${RESET}"

# =====================================================
# 5. GET MAVEN SETTINGS
# =====================================================
echo -e "${YELLOW}Step 5: Getting Maven settings for Artifact Registry...${RESET}"

echo -e "${CYAN}Maven configuration for my-maven-repo:${RESET}"
gcloud artifacts print-settings mvn \
    --repository=my-maven-repo \
    --project="$PROJECT_ID" \
    --location="$REGION"

echo -e "${GREEN}✅ Maven settings retrieved${RESET}"

# =====================================================
# 6. CREATE MAVEN PROJECT
# =====================================================
echo -e "${YELLOW}Step 6: Creating Maven project...${RESET}"

echo -e "${CYAN}Generating Maven project with archetype...${RESET}"
mvn archetype:generate \
    -DgroupId=com.example \
    -DartifactId=my-app \
    -Dversion=1.0-SNAPSHOT \
    -DarchetypeArtifactId=maven-archetype-quickstart \
    -DinteractiveMode=false

echo -e "${GREEN}✅ Maven project 'my-app' created${RESET}"

# =====================================================
# 7. CONFIGURE PROJECT FOR ARTIFACT REGISTRY
# =====================================================
echo -e "${YELLOW}Step 7: Configuring project for Artifact Registry...${RESET}"

# Change to project directory
cd my-app

# Generate Maven settings for the project
echo -e "${CYAN}Generating Maven settings file...${RESET}"
gcloud artifacts print-settings mvn \
    --repository=my-maven-repo \
    --project="$PROJECT_ID" \
    --location="$REGION" > example.pom

echo -e "${CYAN}Maven settings saved to example.pom${RESET}"

# Display project structure
echo -e "${CYAN}Project structure:${RESET}"
ls -la

echo -e "${GREEN}✅ Project configured for Artifact Registry${RESET}"

echo -e "${GREEN}${BOLD}🎉 Complete! Maven project is ready for Artifact Registry.${RESET}"
echo -e "${CYAN}Project: my-app (com.example:my-app:1.0-SNAPSHOT)${RESET}"
echo -e "${CYAN}Repository: https://$REGION-maven.pkg.dev/$PROJECT_ID/my-maven-repo${RESET}"
echo -e "${YELLOW}Next steps:${RESET}"
echo -e "${CYAN}  1. Review example.pom for Maven configuration${RESET}"
echo -e "${CYAN}  2. Update your pom.xml with repository settings${RESET}"
echo -e "${CYAN}  3. Run 'mvn deploy' to publish artifacts${RESET}"