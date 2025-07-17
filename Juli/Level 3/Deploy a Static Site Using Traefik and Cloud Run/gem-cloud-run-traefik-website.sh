#!/bin/bash

# =====================================================
# Traefik Static Site on Google Cloud Run
# Complete Deployment Script with Traefik Proxy
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting Traefik static site deployment to Cloud Run...${RESET}"

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
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com

echo -e "${GREEN}✅ Services enabled successfully${RESET}"

# =====================================================
# 3. CREATE ARTIFACT REGISTRY REPOSITORY
# =====================================================
echo -e "${YELLOW}Step 3: Creating Artifact Registry repository...${RESET}"

gcloud artifacts repositories create traefik-repo \
  --repository-format=docker \
  --location="$REGION" \
  --description="Docker repository for static site images"

echo -e "${GREEN}✅ Repository 'traefik-repo' created${RESET}"

# =====================================================
# 4. CREATE PROJECT STRUCTURE
# =====================================================
echo -e "${YELLOW}Step 4: Creating project structure and static files...${RESET}"

# Create project directory
mkdir traefik-site && cd traefik-site && mkdir public

# Create static HTML file
echo -e "${CYAN}Creating index.html...${RESET}"
cat > public/index.html <<EOF
<html>
<head>
  <title>My Static Website</title>
</head>
<body>
  <p>Hello from my static website on Cloud Run!</p>
</body>
</html>
EOF

echo -e "${GREEN}✅ Project structure and static files created${RESET}"

# =====================================================
# 5. CONFIGURE DOCKER AUTHENTICATION
# =====================================================
echo -e "${YELLOW}Step 5: Configuring Docker authentication...${RESET}"

gcloud auth configure-docker "$REGION"-docker.pkg.dev

echo -e "${GREEN}✅ Docker authentication configured${RESET}"

# =====================================================
# 6. CREATE TRAEFIK CONFIGURATION
# =====================================================
echo -e "${YELLOW}Step 6: Creating Traefik configuration files...${RESET}"

# Create Traefik main configuration
echo -e "${CYAN}Creating traefik.yml...${RESET}"
cat > traefik.yml <<EOF
entryPoints:
  web:
    address: ":8080"
providers:
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true
log:
  level: INFO
EOF

# Create Traefik dynamic configuration
echo -e "${CYAN}Creating dynamic.yml...${RESET}"
cat > dynamic.yml <<EOF
http:
  routers:
    static-files:
      rule: "PathPrefix(\`/\`)"
      entryPoints:
        - web
      service: static-service
  services:
    static-service:
      loadBalancer:
        servers:
          - url: "http://localhost:8000"
EOF

echo -e "${GREEN}✅ Traefik configuration files created${RESET}"

# =====================================================
# 7. CREATE DOCKERFILE
# =====================================================
echo -e "${YELLOW}Step 7: Creating Dockerfile...${RESET}"

echo -e "${CYAN}Creating Dockerfile with multi-service setup...${RESET}"
cat > Dockerfile <<EOF
FROM alpine:3.20

# Install traefik and caddy
RUN apk add --no-cache traefik caddy

# Copy configs and static files
COPY traefik.yml /etc/traefik/traefik.yml
COPY dynamic.yml /etc/traefik/dynamic.yml
COPY public/ /public/

# Create startup script
RUN echo '#!/bin/sh' > /start.sh && \
    echo 'caddy file-server --listen :8000 --root /public &' >> /start.sh && \
    echo 'traefik --configfile=/etc/traefik/traefik.yml' >> /start.sh && \
    chmod +x /start.sh

# Cloud Run uses port 8080
EXPOSE 8080

# Start both services
CMD ["/start.sh"]
EOF

echo -e "${GREEN}✅ Dockerfile created${RESET}"

# =====================================================
# 8. BUILD AND PUSH DOCKER IMAGE
# =====================================================
echo -e "${YELLOW}Step 8: Building and pushing Docker image...${RESET}"

# Define image name
IMAGE_NAME="$REGION-docker.pkg.dev/$PROJECT_ID/traefik-repo/traefik-static-site:latest"

echo -e "${CYAN}Building Docker image...${RESET}"
docker build -t "$IMAGE_NAME" .

echo -e "${CYAN}Pushing image to Artifact Registry...${RESET}"
docker push "$IMAGE_NAME"

echo -e "${GREEN}✅ Docker image built and pushed${RESET}"

# =====================================================
# 9. DEPLOY TO CLOUD RUN
# =====================================================
echo -e "${YELLOW}Step 9: Deploying to Google Cloud Run...${RESET}"

gcloud run deploy traefik-static-site \
  --region "$REGION" \
  --image "$IMAGE_NAME" \
  --platform managed \
  --allow-unauthenticated \
  --port 8080

echo -e "${GREEN}✅ Service deployed successfully${RESET}"

# =====================================================
# 10. GET SERVICE URL
# =====================================================
echo -e "${YELLOW}Step 10: Getting service URL...${RESET}"

SERVICE_URL=$(gcloud run services describe traefik-static-site \
  --platform managed \
  --region "$REGION" \
  --format='value(status.url)')

echo -e "${GREEN}✅ Service URL: ${CYAN}$SERVICE_URL${RESET}"

echo -e "${GREEN}${BOLD}🎉 Deployment Complete! Traefik static site is now live on Cloud Run.${RESET}"
echo -e "${CYAN}Architecture: Static files (Caddy:8000) → Traefik proxy (8080) → Cloud Run${RESET}"