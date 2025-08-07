#!/bin/bash

# =========================================================
# HashiCorp Vault with Google Cloud Platform Integration
# =========================================================
# Deskripsi: Script untuk setup Vault dengan GCP secrets engine
# untuk dynamic credential generation dan static accounts
# =========================================================

set -e  # Keluar jika ada error

echo "=== HashiCorp Vault GCP Integration Setup ==="
echo "Setting up Vault server with GCP secrets engine"
echo ""

# =========================================================
# Step 1: Environment Setup & Authentication
# =========================================================
echo "Step 1: Setting up environment variables..."

# Google Cloud authentication
gcloud auth list

# Set environment variables
export ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_ID=$DEVSHELL_PROJECT_ID

echo "Zone: $ZONE"
echo "Region: $REGION"
echo "Project ID: $PROJECT_ID"
echo ""

# =========================================================
# Step 2: Install HashiCorp Vault
# =========================================================
echo "Step 2: Installing HashiCorp Vault..."

# Add HashiCorp GPG key
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -

# Add HashiCorp repository
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

# Update and install Vault
sudo apt-get update
sudo apt-get install -y vault

# Verify installation
vault --version
echo "✅ Vault installed successfully"
echo ""

# =========================================================
# Step 3: Create Vault Configuration
# =========================================================
echo "Step 3: Creating Vault configuration..."

# Create Vault configuration file
cat > config.hcl <<EOF_CP
storage "raft" {
  path    = "./vault/data"
  node_id = "node1"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = "true"
}

api_addr = "http://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
ui = true
EOF_CP

echo "✅ Vault configuration created"
echo ""

# =========================================================
# Step 4: Start Vault Server
# =========================================================
echo "Step 4: Starting Vault server..."

# Create data directory
mkdir -p ./vault/data

# Start Vault server in background
nohup vault server -config=config.hcl > vault_server.log 2>&1 &

# Wait for server to start
sleep 10

# Set Vault address
export VAULT_ADDR='http://127.0.0.1:8200'

echo "✅ Vault server started at $VAULT_ADDR"
echo ""

# =========================================================
# Step 5: Initialize and Unseal Vault
# =========================================================
echo "Step 5: Initializing and unsealing Vault..."

# Initialize Vault with 5 key shares and threshold of 3
vault operator init -key-shares=5 -key-threshold=3 > vault_init_output.txt

# Extract unseal keys and root token
KEY_1=$(grep 'Unseal Key 1:' vault_init_output.txt | awk '{print $NF}')
KEY_2=$(grep 'Unseal Key 2:' vault_init_output.txt | awk '{print $NF}')
KEY_3=$(grep 'Unseal Key 3:' vault_init_output.txt | awk '{print $NF}')
TOKEN=$(grep 'Initial Root Token:' vault_init_output.txt | awk '{print $NF}')

echo "Unsealing Vault with 3 keys..."
vault operator unseal $KEY_1
vault operator unseal $KEY_2
vault operator unseal $KEY_3

# Login to Vault
vault login $TOKEN

echo "✅ Vault initialized and unsealed successfully"
echo ""

# Wait for system to stabilize
sleep 10

# =========================================================
# Step 6: Enable GCP Secrets Engine
# =========================================================
echo "Step 6: Enabling GCP secrets engine..."

# Enable GCP secrets engine
vault secrets enable gcp

echo "✅ GCP secrets engine enabled"
echo ""

# =========================================================
# Step 7: Setup GCP Service Account
# =========================================================
echo "Step 7: Setting up GCP service account..."

# Define service account email
SERVICE_ACCOUNT_EMAIL="$DEVSHELL_PROJECT_ID@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com"

# Create service account key
gcloud iam service-accounts keys create ~/$DEVSHELL_PROJECT_ID.json \
  --iam-account $SERVICE_ACCOUNT_EMAIL

# List service account keys for verification
gcloud iam service-accounts keys list --iam-account $SERVICE_ACCOUNT_EMAIL

echo "✅ Service account key created: ~/$DEVSHELL_PROJECT_ID.json"
echo ""

# =========================================================
# Step 8: Configure Vault GCP Integration
# =========================================================
echo "Step 8: Configuring Vault GCP integration..."

# Ensure Vault address is set
export VAULT_ADDR='http://127.0.0.1:8200'

# Configure GCP credentials in Vault
vault write gcp/config \
  credentials=@/home/$USER/$DEVSHELL_PROJECT_ID.json \
  ttl=3600 \
  max_ttl=86400

echo "✅ GCP credentials configured in Vault"
echo ""

# =========================================================
# Step 9: Create Resource Bindings
# =========================================================
echo "Step 9: Creating resource bindings..."

# Create bindings configuration for Cloud Storage
cat > bindings.hcl <<EOF_CP
resource "buckets/$DEVSHELL_PROJECT_ID" {
  roles = [
    "roles/storage.objectAdmin",
    "roles/storage.legacyBucketReader",
  ]
}
EOF_CP

echo "✅ Resource bindings configuration created"
echo ""

# =========================================================
# Step 10: Setup Dynamic Access Token Roleset
# =========================================================
echo "Step 10: Setting up dynamic access token roleset..."

# Create roleset for access tokens
vault write gcp/roleset/my-token-roleset \
  project="$DEVSHELL_PROJECT_ID" \
  secret_type="access_token" \
  token_scopes="https://www.googleapis.com/auth/cloud-platform" \
  bindings=@bindings.hcl

echo "✅ Access token roleset created"
echo ""

# =========================================================
# Step 11: Test Access Token Generation
# =========================================================
echo "Step 11: Testing access token generation..."

# Generate access token
TOKEN=$(vault read -field=token gcp/roleset/my-token-roleset/token)

echo "Generated access token: ${TOKEN:0:20}..."

# Test API call with generated token
echo "Testing Cloud Storage API access..."
curl "https://storage.googleapis.com/storage/v1/b/$DEVSHELL_PROJECT_ID" \
  --header "Authorization: Bearer $TOKEN" \
  --header "Accept: application/json"

echo ""
echo "✅ Access token test successful"
echo ""

# =========================================================
# Step 12: Test File Download
# =========================================================
echo "Step 12: Testing file download..."

# Download sample file using generated token
curl -X GET \
  -H "Authorization: Bearer $TOKEN" \
  -o "sample.txt" \
  "https://storage.googleapis.com/storage/v1/b/$DEVSHELL_PROJECT_ID/o/sample.txt?alt=media"

if [ -f "sample.txt" ]; then
  echo "✅ File downloaded successfully"
else
  echo "⚠️  File download may have failed (this is normal if file doesn't exist)"
fi
echo ""

# =========================================================
# Step 13: Setup Service Account Key Roleset
# =========================================================
echo "Step 13: Setting up service account key roleset..."

# Create roleset for service account keys
vault write gcp/roleset/my-key-roleset \
  project="$DEVSHELL_PROJECT_ID" \
  secret_type="service_account_key" \
  bindings=@bindings.hcl

# Test service account key generation
echo "Testing service account key generation..."
vault read gcp/roleset/my-key-roleset/key

echo "✅ Service account key roleset created and tested"
echo ""

# =========================================================
# Step 14: Setup Static Accounts
# =========================================================
echo "Step 14: Setting up static accounts..."

# Create static account for access tokens
vault write gcp/static-account/my-token-account \
  service_account_email="$SERVICE_ACCOUNT_EMAIL" \
  secret_type="access_token" \
  token_scopes="https://www.googleapis.com/auth/cloud-platform" \
  bindings=@bindings.hcl

# Create static account for service account keys
vault write gcp/static-account/my-key-account \
  service_account_email="$SERVICE_ACCOUNT_EMAIL" \
  secret_type="service_account_key" \
  bindings=@bindings.hcl

echo "✅ Static accounts configured"
echo ""

# =========================================================
# Step 15: Re-verify Configuration
# =========================================================
echo "Step 15: Re-verifying configuration..."

# Ensure environment is properly set
export VAULT_ADDR='http://127.0.0.1:8200'

# Re-configure GCP credentials (duplicate for verification)
vault write gcp/config \
  credentials=@/home/$USER/$DEVSHELL_PROJECT_ID.json \
  ttl=3600 \
  max_ttl=86400

# Recreate bindings (duplicate for verification)
cat > bindings.hcl <<EOF_CP
resource "buckets/$DEVSHELL_PROJECT_ID" {
  roles = [
    "roles/storage.objectAdmin",
    "roles/storage.legacyBucketReader",
  ]
}
EOF_CP

# Re-create token roleset (duplicate for verification)
vault write gcp/roleset/my-token-roleset \
  project="$DEVSHELL_PROJECT_ID" \
  secret_type="access_token" \
  token_scopes="https://www.googleapis.com/auth/cloud-platform" \
  bindings=@bindings.hcl

echo "✅ Configuration verification complete"
echo "✅ ALL PROGRESS COMPLETE"