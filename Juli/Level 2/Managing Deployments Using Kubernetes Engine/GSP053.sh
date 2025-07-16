#!/bin/bash

# Colors for better output formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== GCP Kubernetes Deployment Management Tutorial ===${NC}\n"

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

# Set compute zone and region
gcloud config set compute/zone "$ZONE"
gcloud config set compute/region "$REGION"

echo -e "${CYAN}Zone: $ZONE${NC}"
echo -e "${CYAN}Region: $REGION${NC}"
echo -e "${CYAN}Project ID: $PROJECT_ID${NC}"

# ===============================
# 2. DOWNLOAD SAMPLE FILES
# ===============================
echo -e "\n${GREEN}2. Downloading Kubernetes orchestration files...${NC}"

# Download orchestration samples from Cloud Storage
gsutil -m cp -r gs://spls/gsp053/orchestrate-with-kubernetes .
cd orchestrate-with-kubernetes/kubernetes

echo -e "${CYAN}Sample files downloaded and ready${NC}"

# ===============================
# 3. CREATE KUBERNETES CLUSTER
# ===============================
echo -e "\n${GREEN}3. Creating Kubernetes cluster with specific configuration...${NC}"

# Create GKE cluster with custom settings
gcloud container clusters create bootcamp \
  --machine-type e2-small \
  --num-nodes 3 \
  --scopes "https://www.googleapis.com/auth/projecthosting,storage-rw"

echo -e "${CYAN}Cluster 'bootcamp' created with 3 e2-small nodes${NC}"

# ===============================
# 4. DEPLOY INITIAL SERVICES
# ===============================
echo -e "\n${GREEN}4. Deploying initial microservices...${NC}"

# Modify auth deployment to use version 1.0.0
echo -e "${PURPLE}Setting auth service to version 1.0.0...${NC}"
sed -i 's/image: "kelseyhightower\/auth:2.0.0"/image: "kelseyhightower\/auth:1.0.0"/' deployments/auth.yaml

# Deploy Auth service
echo -e "${PURPLE}Deploying Auth service...${NC}"
kubectl create -f deployments/auth.yaml

# Check deployment status
echo -e "${CYAN}Checking deployments:${NC}"
kubectl get deployments

echo -e "${CYAN}Checking pods:${NC}"
kubectl get pods

# Create auth service
kubectl create -f services/auth.yaml

# Deploy Hello service
echo -e "${PURPLE}Deploying Hello service...${NC}"
kubectl create -f deployments/hello.yaml
kubectl create -f services/hello.yaml

# Deploy Frontend service with secrets and configmaps
echo -e "${PURPLE}Deploying Frontend service with TLS and configuration...${NC}"
kubectl create secret generic tls-certs --from-file tls/
kubectl create configmap nginx-frontend-conf --from-file=nginx/frontend.conf
kubectl create -f deployments/frontend.yaml
kubectl create -f services/frontend.yaml

# Check frontend service
echo -e "${CYAN}Frontend service status:${NC}"
kubectl get services frontend

# ===============================
# 5. SCALING OPERATIONS
# ===============================
echo -e "\n${GREEN}5. Demonstrating scaling operations...${NC}"

# Wait for services to be ready
sleep 17

# Scale hello deployment up to 5 replicas
echo -e "${PURPLE}Scaling hello deployment to 5 replicas...${NC}"
kubectl scale deployment hello --replicas=5

# Count hello pods
echo -e "${CYAN}Number of hello pods after scaling up:${NC}"
kubectl get pods | grep hello- | wc -l

# Scale hello deployment down to 3 replicas
echo -e "${PURPLE}Scaling hello deployment back to 3 replicas...${NC}"
kubectl scale deployment hello --replicas=3

# Count hello pods again
echo -e "${CYAN}Number of hello pods after scaling down:${NC}"
kubectl get pods | grep hello- | wc -l

# ===============================
# 6. ROLLING UPDATES
# ===============================
echo -e "\n${GREEN}6. Performing rolling updates...${NC}"

# Modify hello deployment to use version 2.0.0
echo -e "${PURPLE}Updating hello service to version 2.0.0...${NC}"
sed -i 's/image: "kelseyhightower\/auth:1.0.0"/image: "kelseyhightower\/auth:2.0.0"/' deployments/hello.yaml

# Check replica sets
echo -e "${CYAN}Current replica sets:${NC}"
kubectl get replicaset

# Check rollout history
echo -e "${CYAN}Rollout history:${NC}"
kubectl rollout history deployment/hello

# Show current pod images
echo -e "${CYAN}Current pod images:${NC}"
kubectl get pods -o jsonpath --template='{range .items[*]}{.metadata.name}{"\t"}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

# Resume rollout (if paused)
kubectl rollout resume deployment/hello

# Check rollout status
echo -e "${CYAN}Checking rollout status:${NC}"
kubectl rollout status deployment/hello

# ===============================
# 7. ROLLBACK OPERATIONS
# ===============================
echo -e "\n${GREEN}7. Demonstrating rollback operations...${NC}"

# Rollback to previous version
echo -e "${PURPLE}Rolling back to previous version...${NC}"
kubectl rollout undo deployment/hello

# Check rollout history after rollback
echo -e "${CYAN}Rollout history after rollback:${NC}"
kubectl rollout history deployment/hello

# Show pod images after rollback
echo -e "${CYAN}Pod images after rollback:${NC}"
kubectl get pods -o jsonpath --template='{range .items[*]}{.metadata.name}{"\t"}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

# ===============================
# 8. CANARY DEPLOYMENT
# ===============================
echo -e "\n${GREEN}8. Setting up canary deployment...${NC}"

# Create canary deployment
echo -e "${PURPLE}Creating canary deployment...${NC}"
kubectl create -f deployments/hello-canary.yaml

# Check all deployments
echo -e "${CYAN}All deployments (including canary):${NC}"
kubectl get deployments

# Test canary deployment
echo -e "${PURPLE}Testing canary deployment...${NC}"
echo -e "${CYAN}Calling frontend service to test version distribution:${NC}"
curl -ks https://`kubectl get svc frontend -o=jsonpath="{.status.loadBalancer.ingress[0].ip}"`/version

echo -e "\n${GREEN}=== Kubernetes Deployment Management Tutorial Completed! ===${NC}"
echo -e "${CYAN}You have successfully learned:${NC}"
echo -e "${CYAN}- Cluster creation with custom configurations${NC}"
echo -e "${CYAN}- Microservices deployment (auth, hello, frontend)${NC}"
echo -e "${CYAN}- Horizontal scaling (scale up/down)${NC}"
echo -e "${CYAN}- Rolling updates and version management${NC}"
echo -e "${CYAN}- Rollback operations${NC}"
echo -e "${CYAN}- Canary deployments for safe releases${NC}"
echo
echo -e "${YELLOW}Advanced Commands:${NC}"
echo -e "${YELLOW}- kubectl rollout history deployment/[name] - Check rollout history${NC}"
echo -e "${YELLOW}- kubectl rollout status deployment/[name] - Monitor rollout progress${NC}"
echo -e "${YELLOW}- kubectl rollout undo deployment/[name] - Rollback deployment${NC}"
echo -e "${YELLOW}- kubectl scale deployment [name] --replicas=[number] - Scale deployment${NC}"
echo -e "${YELLOW}- kubectl get rs - Check replica sets${NC}"