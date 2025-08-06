#!/bin/bash

# =========================================================
# Google Cloud VPC Network Peering Setup
# =========================================================
# Deskripsi: Script untuk membuat dan mengkonfigurasi
# VPC network peering antara workspace-vpc dan private-vpc
# =========================================================

set -e  # Keluar jika ada error

echo "=== Starting Google Cloud VPC Peering Setup ==="

# 1. Autentikasi dan validasi akun Google Cloud
echo "Step 1: Authenticating Google Cloud account..."
gcloud auth list
echo ""

# 2. Mengatur variabel environment untuk zone dan project
echo "Step 2: Setting up environment variables..."
export ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export PROJECT_ID=$(gcloud config get-value project)

# Validasi zone default
if [ -z "$ZONE" ]; then
  echo "Warning: No default zone found, using us-central1-a"
  export ZONE="us-central1-a"
fi

echo "Using Zone: $ZONE"
echo "Using Project ID: $PROJECT_ID"
gcloud config set compute/zone "$ZONE"
echo ""

# 3. Membuat VPC Networks dengan mode custom
echo "Step 3: Creating VPC Networks..."

echo "Creating workspace-vpc network..."
if gcloud compute networks describe workspace-vpc &>/dev/null; then
  echo "workspace-vpc already exists, skipping creation."
else
  gcloud compute networks create workspace-vpc \
    --subnet-mode=custom \
    --description="Workspace VPC for development environment"
  echo "workspace-vpc created successfully."
fi

echo "Creating private-vpc network..."
if gcloud compute networks describe private-vpc &>/dev/null; then
  echo "private-vpc already exists, skipping creation."
else
  gcloud compute networks create private-vpc \
    --subnet-mode=custom \
    --description="Private VPC for secure resources"
  echo "private-vpc created successfully."
fi
echo ""

# 4. Membuat VPC Network Peering
echo "Step 4: Setting up VPC Network Peering..."

echo "Creating peering: workspace-to-private..."
if gcloud compute networks peerings describe workspace-to-private \
   --network=workspace-vpc &>/dev/null; then
  echo "workspace-to-private peering already exists."
else
  gcloud compute networks peerings create workspace-to-private \
    --network=workspace-vpc \
    --peer-network=private-vpc \
    --auto-create-routes \
    --project="$PROJECT_ID"
  echo "workspace-to-private peering created successfully."
fi

echo "Creating peering: private-to-workspace..."
if gcloud compute networks peerings describe private-to-workspace \
   --network=private-vpc &>/dev/null; then
  echo "private-to-workspace peering already exists."
else
  gcloud compute networks peerings create private-to-workspace \
    --network=private-vpc \
    --peer-network=workspace-vpc \
    --auto-create-routes \
    --project="$PROJECT_ID"
  echo "private-to-workspace peering created successfully."
fi
echo ""

# 5. Verifikasi peering status
echo "Step 5: Verifying peering status..."
echo "Workspace VPC peering status:"
gcloud compute networks peerings list --network=workspace-vpc --format="table(name,state,peerNetwork)"

echo ""
echo "Private VPC peering status:"
gcloud compute networks peerings list --network=private-vpc --format="table(name,state,peerNetwork)"
echo ""

# 6. Informasi sebelum SSH ke VM
echo "Step 6: Preparing to connect to workspace-vm..."
echo "Checking if workspace-vm exists..."

if gcloud compute instances describe workspace-vm --zone="$ZONE" &>/dev/null; then
  echo "workspace-vm found in zone $ZONE"
  echo "Initiating SSH connection..."
  echo ""
  echo "=== Connecting to workspace-vm ==="
  echo "Note: You will be connected to the VM. Type 'exit' to return to this shell."
  echo ""
  
  # SSH ke workspace-vm
  gcloud compute ssh workspace-vm \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --ssh-flag="-o StrictHostKeyChecking=no"
    
else
  echo "ERROR: workspace-vm not found in zone $ZONE"
  echo "Available instances in project $PROJECT_ID:"
  gcloud compute instances list --format="table(name,zone,status)"
  echo ""
  echo "Please create the workspace-vm first or check the correct zone."
  exit 1
fi

echo ""
echo "=== VPC Peering Setup Complete ==="
echo "Network Configuration Summary:"
echo "- workspace-vpc: Created with custom subnet mode"
echo "- private-vpc: Created with custom subnet mode" 
echo "- Bidirectional peering: Established between both VPCs"
echo "- Auto-create routes: Enabled for automatic routing"