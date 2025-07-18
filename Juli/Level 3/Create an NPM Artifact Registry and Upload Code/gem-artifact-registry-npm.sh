#!/bin/bash

# =====================================================
# NPM Package Upload to Artifact Registry
# Complete NPM Package Build and Upload Script
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting NPM package upload to Artifact Registry...${RESET}"

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
# 3. CREATE NPM REPOSITORY
# =====================================================
echo -e "${YELLOW}Step 3: Creating NPM repository in Artifact Registry...${RESET}"

gcloud artifacts repositories create my-npm-repo \
    --repository-format=npm \
    --location="$REGION" \
    --description="NPM repository"

echo -e "${GREEN}✅ NPM repository created${RESET}"

# =====================================================
# 4. CREATE NPM PACKAGE
# =====================================================
echo -e "${YELLOW}Step 4: Creating NPM package...${RESET}"

# Create package directory
mkdir my-npm-package
cd my-npm-package

# Initialize npm package with scoped name
echo -e "${CYAN}Initializing NPM package...${RESET}"
npm init --scope=@"$PROJECT_ID" -y

# Create main JavaScript file
echo -e "${CYAN}Creating index.js...${RESET}"
echo 'console.log(`Hello from my-npm-package!`);' > index.js

echo -e "${GREEN}✅ NPM package created${RESET}"

# =====================================================
# 5. CONFIGURE NPM AUTHENTICATION
# =====================================================
echo -e "${YELLOW}Step 5: Configuring NPM authentication...${RESET}"

# Generate NPM configuration
echo -e "${CYAN}Generating .npmrc configuration...${RESET}"
gcloud artifacts print-settings npm \
    --project="$PROJECT_ID" \
    --repository=my-npm-repo \
    --location="$REGION" \
    --scope=@"$PROJECT_ID" > ./.npmrc

# Configure Docker authentication for npm
gcloud auth configure-docker "$REGION"-npm.pkg.dev

echo -e "${GREEN}✅ NPM authentication configured${RESET}"

# =====================================================
# 6. UPDATE PACKAGE.JSON
# =====================================================
echo -e "${YELLOW}Step 6: Updating package.json with repository settings...${RESET}"

echo -e "${CYAN}Creating package.json with Artifact Registry settings...${RESET}"
cat > package.json <<EOF
{
  "name": "@$PROJECT_ID/my-npm-package",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "artifactregistry-login": "npx google-artifactregistry-auth --repo-config=./.npmrc --credential-config=./.npmrc",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "keywords": [],
  "author": "",
  "license": "ISC",
  "type": "commonjs"
}
EOF

echo -e "${GREEN}✅ Package.json updated${RESET}"

# =====================================================
# 7. AUTHENTICATE NPM
# =====================================================
echo -e "${YELLOW}Step 7: Authenticating NPM with Artifact Registry...${RESET}"

npm run artifactregistry-login

echo -e "${CYAN}Current .npmrc configuration:${RESET}"
cat .npmrc

echo -e "${GREEN}✅ NPM authentication completed${RESET}"

# =====================================================
# 8. PUBLISH PACKAGE
# =====================================================
echo -e "${YELLOW}Step 8: Publishing package to Artifact Registry...${RESET}"

npm publish --registry=https://"$REGION"-npm.pkg.dev/"$PROJECT_ID"/my-npm-repo/

echo -e "${GREEN}✅ Package published successfully${RESET}"

# =====================================================
# 9. VERIFY PACKAGE
# =====================================================
echo -e "${YELLOW}Step 9: Verifying published package...${RESET}"

echo -e "${CYAN}Listing packages in repository:${RESET}"
gcloud artifacts packages list --repository=my-npm-repo --location="$REGION"

echo -e "${GREEN}${BOLD}🎉 Complete! NPM package is now available in Artifact Registry.${RESET}"
echo -e "${CYAN}Package: @$PROJECT_ID/my-npm-package@1.0.0${RESET}"
echo -e "${CYAN}Registry: https://$REGION-npm.pkg.dev/$PROJECT_ID/my-npm-repo/${RESET}"