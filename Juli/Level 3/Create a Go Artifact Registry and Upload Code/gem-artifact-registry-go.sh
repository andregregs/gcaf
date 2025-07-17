#!/bin/bash

# =====================================================
# Go Module Upload to Artifact Registry
# Complete Go Module Build and Upload Script
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting Go module upload to Artifact Registry...${RESET}"

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
# 3. CREATE GO REPOSITORY
# =====================================================
echo -e "${YELLOW}Step 3: Creating Go repository in Artifact Registry...${RESET}"

gcloud artifacts repositories create my-go-repo \
    --repository-format=go \
    --location="$REGION" \
    --description="Go repository"

echo -e "${CYAN}Repository details:${RESET}"
gcloud artifacts repositories describe my-go-repo \
    --location="$REGION"

echo -e "${GREEN}✅ Go repository created${RESET}"

# =====================================================
# 4. CONFIGURE GO ENVIRONMENT
# =====================================================
echo -e "${YELLOW}Step 4: Configuring Go environment for private modules...${RESET}"

# Set GOPRIVATE for the project
go env -w GOPRIVATE=cloud.google.com/"$PROJECT_ID"

# Configure Go proxy and authentication
export GONOPROXY=github.com/GoogleCloudPlatform/artifact-registry-go-tools
GOPROXY=proxy.golang.org go run github.com/GoogleCloudPlatform/artifact-registry-go-tools/cmd/auth@latest add-locations --locations="$REGION"

echo -e "${GREEN}✅ Go environment configured${RESET}"

# =====================================================
# 5. CREATE GO MODULE
# =====================================================
echo -e "${YELLOW}Step 5: Creating Go module...${RESET}"

# Create module directory
mkdir hello
cd hello

# Initialize Go module
echo -e "${CYAN}Initializing Go module...${RESET}"
go mod init labdemo.app/hello

# Create Go source file
echo -e "${CYAN}Creating hello.go...${RESET}"
cat > hello.go <<EOF
package main

import "fmt"

func main() {
	fmt.Println("Hello, Go module from Artifact Registry!")
}
EOF

# Build the module
echo -e "${CYAN}Building Go module...${RESET}"
go build

echo -e "${GREEN}✅ Go module created and built${RESET}"

# =====================================================
# 6. GIT SETUP AND COMMIT
# =====================================================
echo -e "${YELLOW}Step 6: Setting up Git and committing code...${RESET}"

# Configure Git (using environment variable for email if available)
EMAIL=${EMAIL:-"user@example.com"}
git config --global user.email "$EMAIL"
git config --global user.name "cls"
git config --global init.defaultBranch main

# Initialize Git repository
echo -e "${CYAN}Initializing Git repository...${RESET}"
git init

# Add files and commit
echo -e "${CYAN}Adding files and committing...${RESET}"
git add .
git commit -m "Initial commit"

# Tag the version
echo -e "${CYAN}Creating version tag...${RESET}"
git tag v1.0.0

echo -e "${GREEN}✅ Git setup and commit completed${RESET}"

# =====================================================
# 7. UPLOAD TO ARTIFACT REGISTRY
# =====================================================
echo -e "${YELLOW}Step 7: Uploading Go module to Artifact Registry...${RESET}"

gcloud artifacts go upload \
  --repository=my-go-repo \
  --location="$REGION" \
  --module-path=labdemo.app/hello \
  --version=v1.0.0 \
  --source=.

echo -e "${GREEN}✅ Module uploaded successfully${RESET}"

# =====================================================
# 8. VERIFY UPLOAD
# =====================================================
echo -e "${YELLOW}Step 8: Verifying uploaded packages...${RESET}"

echo -e "${CYAN}Listing packages in repository:${RESET}"
gcloud artifacts packages list --repository=my-go-repo --location="$REGION"

echo -e "${GREEN}${BOLD}🎉 Complete! Go module is now available in Artifact Registry.${RESET}"
echo -e "${CYAN}Module: labdemo.app/hello@v1.0.0${RESET}"