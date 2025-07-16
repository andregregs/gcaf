#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== GCP Docker & Kubernetes Setup ===${NC}\n"

# ===============================
# 1. AUTHENTICATION & ENVIRONMENT
# ===============================
echo -e "${GREEN}1. Setting up authentication and environment...${NC}"
gcloud auth list

# Get default zone, region, and project ID
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

# Set default compute zone and region
gcloud config set compute/zone "$ZONE"
gcloud config set compute/region "$REGION"

echo "Zone: $ZONE"
echo "Region: $REGION"
echo "Project ID: $PROJECT_ID"

# ===============================
# 2. CREATE APPLICATION FILES
# ===============================
echo -e "\n${GREEN}2. Creating application files...${NC}"

# Create simple Node.js server
cat > server.js <<EOF
var http = require('http');
var handleRequest = function(request, response) {
  response.writeHead(200);
  response.end("Hello World!");
}
var www = http.createServer(handleRequest);
www.listen(8080);
EOF

# Create Dockerfile
cat > Dockerfile <<EOF
FROM node:6.9.2
EXPOSE 8080
COPY server.js .
CMD node server.js
EOF

echo "Created server.js and Dockerfile"

# ===============================
# 3. DOCKER BUILD & TEST
# ===============================
echo -e "\n${GREEN}3. Building and testing Docker image...${NC}"

# Build Docker image
docker build -t gcr.io/$PROJECT_ID/hello-node:v1 .

# Run container locally
docker run -d -p 8080:8080 gcr.io/$PROJECT_ID/hello-node:v1

# Test the application
echo "Testing local deployment..."
curl http://localhost:8080

# Stop the container
ID=$(docker ps --format '{{.ID}}')
docker stop $ID

# ===============================
# 4. PUSH TO CONTAINER REGISTRY
# ===============================
echo -e "\n${GREEN}4. Pushing to Google Container Registry...${NC}"

# Configure Docker for GCR
gcloud auth configure-docker --quiet

# Push image to GCR
docker push gcr.io/$PROJECT_ID/hello-node:v1

# ===============================
# 5. CREATE KUBERNETES CLUSTER
# ===============================
echo -e "\n${GREEN}5. Creating Kubernetes cluster...${NC}"

gcloud config set project $PROJECT_ID
gcloud container clusters create hello-world \
  --zone="$ZONE" \
  --num-nodes 2 \
  --machine-type n1-standard-1

# ===============================
# 6. DEPLOY TO KUBERNETES
# ===============================
echo -e "\n${GREEN}6. Deploying application to Kubernetes...${NC}"

# Create deployment
kubectl create deployment hello-node --image=gcr.io/$PROJECT_ID/hello-node:v1

# Wait and check deployment status
sleep 5
kubectl get deployments
sleep 5
kubectl get pods

# ===============================
# 7. CLUSTER INFORMATION
# ===============================
echo -e "\n${GREEN}7. Cluster information...${NC}"
kubectl cluster-info
kubectl config view
kubectl get events

# ===============================
# 8. EXPOSE SERVICE & SCALE
# ===============================
echo -e "\n${GREEN}8. Exposing service and scaling...${NC}"

# Expose deployment as LoadBalancer service
kubectl expose deployment hello-node --type="LoadBalancer" --port=8080

# Wait for service to be ready
sleep 7
kubectl get services

# Scale deployment to 4 replicas
kubectl scale deployment hello-node --replicas=4

# Check scaling results
sleep 5
kubectl get deployment
sleep 7
kubectl get pods

echo -e "\n${GREEN}=== Setup completed successfully! ===${NC}"