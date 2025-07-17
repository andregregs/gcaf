#!/bin/bash

# =====================================================
# Nginx Static Website on Google Cloud Run
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

echo -e "${BLUE}${BOLD}Starting Nginx static website deployment to Cloud Run...${RESET}"

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
gcloud config set compute/region $REGION
gcloud config set project $PROJECT_ID

echo -e "${GREEN}✅ Environment configured: $PROJECT_ID | $REGION${RESET}"

# =====================================================
# 2. ENABLE REQUIRED SERVICES
# =====================================================
echo -e "${YELLOW}Step 2: Enabling required Google Cloud services...${RESET}"

gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com

echo -e "${GREEN}✅ Services enabled successfully${RESET}"

# =====================================================
# 3. CREATE ARTIFACT REGISTRY REPOSITORY
# =====================================================
echo -e "${YELLOW}Step 3: Creating Artifact Registry repository...${RESET}"

gcloud artifacts repositories create nginx-static-site \
  --repository-format=docker \
  --location="$REGION" \
  --description="Docker repository for static website"

echo -e "${GREEN}✅ Artifact Registry repository created${RESET}"

# =====================================================
# 4. CREATE WEBSITE FILES
# =====================================================
echo -e "${YELLOW}Step 4: Creating website files...${RESET}"

# Create HTML file
echo -e "${CYAN}Creating index.html...${RESET}"
cat > index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>My Static Website</title>
</head>
<body>
    <div>Welcome to My Static Website!</div>
    <p>This website is served from Google Cloud Run using Nginx and Artifact Registry.</p>
</body>
</html>
EOF

# Create Nginx configuration
echo -e "${CYAN}Creating nginx.conf...${RESET}"
cat > nginx.conf <<EOF
events {}
http {
    server {
        listen 8080;
        root /usr/share/nginx/html;
        index index.html index.htm;
        location / {
            try_files \$uri \$uri/ =404;
        }
    }
}
EOF

# Create Dockerfile
echo -e "${CYAN}Creating Dockerfile...${RESET}"
cat > Dockerfile <<EOF
FROM nginx:latest
COPY index.html /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
EOF

echo -e "${GREEN}✅ Website files created${RESET}"

# =====================================================
# 5. BUILD AND PUSH DOCKER IMAGE
# =====================================================
echo -e "${YELLOW}Step 5: Building and pushing Docker image...${RESET}"

# Define image name
IMAGE_NAME="$REGION-docker.pkg.dev/$PROJECT_ID/nginx-static-site/nginx-static-site"

echo -e "${CYAN}Building Docker image...${RESET}"
docker build -t nginx-static-site .

echo -e "${CYAN}Tagging image...${RESET}"
docker tag nginx-static-site "$IMAGE_NAME"

echo -e "${CYAN}Pushing image to Artifact Registry...${RESET}"
docker push "$IMAGE_NAME"

echo -e "${GREEN}✅ Docker image built and pushed${RESET}"

# =====================================================
# 6. DEPLOY TO CLOUD RUN
# =====================================================
echo -e "${YELLOW}Step 6: Deploying to Google Cloud Run...${RESET}"

gcloud run deploy nginx-static-site \
  --image "$IMAGE_NAME" \
  --platform managed \
  --region "$REGION" \
  --allow-unauthenticated

echo -e "${GREEN}✅ Service deployed successfully${RESET}"

# =====================================================
# 7. GET SERVICE URL
# =====================================================
echo -e "${YELLOW}Step 7: Getting service URL...${RESET}"

SERVICE_URL=$(gcloud run services describe nginx-static-site \
  --platform managed \
  --region "$REGION" \
  --format='value(status.url)')

echo -e "${GREEN}✅ Service URL: ${CYAN}$SERVICE_URL${RESET}"

echo -e "${GREEN}${BOLD}🎉 Deployment Complete! Nginx static website is now live on Cloud Run.${RESET}"