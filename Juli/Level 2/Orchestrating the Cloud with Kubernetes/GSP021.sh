#!/bin/bash

# Colors for better output formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${BLUE}=== GCP Kubernetes Orchestration Tutorial ===${NC}\n"

# ===============================
# 1. AUTHENTICATION & ENVIRONMENT SETUP
# ===============================
echo -e "${GREEN}1. Setting up authentication and environment...${NC}"

# Check current authentication
gcloud auth list

# Export environment variables
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

# Set compute zone
gcloud config set compute/zone "$ZONE"

echo -e "${CYAN}Zone: $ZONE${NC}"
echo -e "${CYAN}Region: $REGION${NC}"
echo -e "${CYAN}Project ID: $PROJECT_ID${NC}"

# ===============================
# 2. CREATE KUBERNETES CLUSTER
# ===============================
echo -e "\n${GREEN}2. Creating Kubernetes cluster...${NC}"

# Create GKE cluster named 'io'
gcloud container clusters create io --zone $ZONE

echo -e "${CYAN}Cluster 'io' created successfully${NC}"

# ===============================
# 3. DOWNLOAD SAMPLE FILES
# ===============================
echo -e "\n${GREEN}3. Downloading Kubernetes sample files...${NC}"

# Download orchestration samples from Cloud Storage
gsutil cp -r gs://spls/gsp021/* .

# Navigate to kubernetes directory
cd orchestrate-with-kubernetes/kubernetes

# List available files
echo -e "${CYAN}Available sample files:${NC}"
ls

# ===============================
# 4. BASIC DEPLOYMENT & SERVICE
# ===============================
echo -e "\n${GREEN}4. Creating basic nginx deployment...${NC}"

# Create nginx deployment
kubectl create deployment nginx --image=nginx:1.10.0

# Check pod status
echo -e "${CYAN}Checking nginx pods:${NC}"
kubectl get pods

# Expose nginx deployment as LoadBalancer service
kubectl expose deployment nginx --port 80 --type LoadBalancer

# Check service status
echo -e "${CYAN}Checking services:${NC}"
kubectl get services

# ===============================
# 5. WORKING WITH PODS
# ===============================
echo -e "\n${GREEN}5. Creating and managing pods...${NC}"

# Navigate to kubernetes directory
cd ~/orchestrate-with-kubernetes/kubernetes

# Create monolith pod
kubectl create -f pods/monolith.yaml

# Check pod status
echo -e "${CYAN}Checking monolith pod:${NC}"
kubectl get pods

# ===============================
# 6. SECURE MONOLITH WITH SECRETS & CONFIGMAPS
# ===============================
echo -e "\n${GREEN}6. Setting up secure monolith with secrets and configmaps...${NC}"

# Navigate to kubernetes directory
cd ~/orchestrate-with-kubernetes/kubernetes

# Show secure monolith configuration
echo -e "${CYAN}Secure monolith configuration:${NC}"
cat pods/secure-monolith.yaml

# Create TLS certificates secret
kubectl create secret generic tls-certs --from-file tls/

# Create nginx proxy configuration
kubectl create configmap nginx-proxy-conf --from-file nginx/proxy.conf

# Create secure monolith pod
kubectl create -f pods/secure-monolith.yaml

# ===============================
# 7. EXPOSE MONOLITH SERVICE
# ===============================
echo -e "\n${GREEN}7. Exposing monolith service...${NC}"

# Create monolith service
kubectl create -f services/monolith.yaml

# Create firewall rule for NodePort access
gcloud compute firewall-rules create allow-monolith-nodeport \
  --allow=tcp:31000

# List compute instances
echo -e "${CYAN}Compute instances:${NC}"
gcloud compute instances list

# ===============================
# 8. WORKING WITH LABELS & SELECTORS
# ===============================
echo -e "\n${GREEN}8. Working with labels and selectors...${NC}"

# Check pods with monolith label
echo -e "${CYAN}Pods with app=monolith label:${NC}"
kubectl get pods -l "app=monolith"

# Check pods with specific labels
echo -e "${CYAN}Pods with app=monolith,secure=enabled labels:${NC}"
kubectl get pods -l "app=monolith,secure=enabled"

# Add secure=enabled label to secure-monolith pod
kubectl label pods secure-monolith 'secure=enabled'

# Show pod labels
echo -e "${CYAN}Secure monolith pod labels:${NC}"
kubectl get pods secure-monolith --show-labels

# Check service endpoints
echo -e "${CYAN}Monolith service endpoints:${NC}"
kubectl describe services monolith | grep Endpoints

# List instances again
echo -e "${CYAN}Updated compute instances:${NC}"
gcloud compute instances list

# ===============================
# 9. MICROSERVICES DEPLOYMENT
# ===============================
echo -e "\n${GREEN}9. Deploying microservices architecture...${NC}"

# Deploy Auth service
echo -e "${PURPLE}Deploying Auth service...${NC}"
kubectl create -f deployments/auth.yaml
kubectl create -f services/auth.yaml

# Deploy Hello service  
echo -e "${PURPLE}Deploying Hello service...${NC}"
kubectl create -f deployments/hello.yaml
kubectl create -f services/hello.yaml

# Deploy Frontend service
echo -e "${PURPLE}Deploying Frontend service...${NC}"

# Create frontend nginx configuration
kubectl create configmap nginx-frontend-conf --from-file=nginx/frontend.conf

# Create frontend deployment and service
kubectl create -f deployments/frontend.yaml
kubectl create -f services/frontend.yaml

# ===============================
# 10. FINAL STATUS CHECK
# ===============================
echo -e "\n${GREEN}10. Final deployment status...${NC}"

# Get frontend service information
echo -e "${CYAN}Frontend service status:${NC}"
kubectl get services frontend

echo -e "\n${GREEN}=== Kubernetes Orchestration Tutorial Completed! ===${NC}"
echo -e "${CYAN}You have successfully:${NC}"
echo -e "${CYAN}- Created a GKE cluster${NC}"
echo -e "${CYAN}- Deployed basic nginx service${NC}"
echo -e "${CYAN}- Created monolith pods with secrets and configmaps${NC}"
echo -e "${CYAN}- Set up firewall rules for NodePort access${NC}"
echo -e "${CYAN}- Worked with labels and selectors${NC}"
echo -e "${CYAN}- Deployed microservices architecture (auth, hello, frontend)${NC}"
echo
echo -e "${YELLOW}Use 'kubectl get all' to see all deployed resources${NC}"
echo -e "${YELLOW}Use 'kubectl get svc' to get service external IPs${NC}"