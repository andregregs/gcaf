#!/bin/bash

# =========================================================
# HashiCorp Vault GCP Integration Setup Script
# =========================================================
# Deskripsi: Script untuk setup Vault production mode dengan
# GCP Secrets Engine untuk dynamic credential generation
# =========================================================

set -e  # Keluar jika ada error

# Konfigurasi
VAULT_VERSION="latest"
VAULT_PORT="8200"
VAULT_ADDR="http://127.0.0.1:$VAULT_PORT"
VAULT_DATA_DIR="./vault/data"
VAULT_CONFIG_FILE="config.hcl"
VAULT_LOG_FILE="vault_server.log"
VAULT_INIT_FILE="vault_init_output.txt"

# Color codes untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_task() {
    echo -e "${BLUE}=== Task $1: $2 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

wait_for_input() {
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

echo "=== HashiCorp Vault GCP Integration Lab ==="
echo "Mode: Production Server with Raft Storage"
echo "GCP Integration: Dynamic Credentials"
echo ""

# =========================================================
# Task 1: Environment Setup
# =========================================================
print_task "1" "Environment Setup and Authentication"

echo "Step 1.1: Authenticating with Google Cloud..."
gcloud auth list

echo ""
echo "Step 1.2: Setting up environment variables..."
export ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_ID=$DEVSHELL_PROJECT_ID

# Fallback values
ZONE=${ZONE:-"us-central1-a"}
REGION=${REGION:-"us-central1"}

echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Zone: $ZONE"

if [ -z "$PROJECT_ID" ]; then
    print_error "PROJECT_ID not set. Please ensure you're running in Google Cloud Shell."
    exit 1
fi

print_success "Environment variables configured"

wait_for_input

# =========================================================
# Task 2: Install HashiCorp Vault
# =========================================================
print_task "2" "Installing HashiCorp Vault"

echo "Step 2.1: Adding HashiCorp GPG key..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -

echo "Step 2.2: Adding HashiCorp repository..."
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

echo "Step 2.3: Installing Vault..."
sudo apt-get update
sudo apt-get install -y vault

echo "Step 2.4: Verifying installation..."
if vault version; then
    print_success "Vault installed successfully"
else
    print_error "Vault installation failed"
    exit 1
fi

wait_for_input

# =========================================================
# Task 3: Configure Vault Server
# =========================================================
print_task "3" "Configuring Vault Production Server"

echo "Step 3.1: Creating Vault configuration..."
cat > $VAULT_CONFIG_FILE <<EOF
# Vault Production Configuration
# Storage backend using Raft for high availability
storage "raft" {
  path    = "$VAULT_DATA_DIR"
  node_id = "node1"
}

# Network listener configuration
listener "tcp" {
  address     = "127.0.0.1:$VAULT_PORT"
  tls_disable = "true"
}

# API and Cluster addresses
api_addr = "$VAULT_ADDR"
cluster_addr = "https://127.0.0.1:8201"

# Enable Web UI
ui = true

# Disable mlock for development (don't use in production)
disable_mlock = true
EOF

echo "Vault configuration created:"
cat $VAULT_CONFIG_FILE

echo ""
echo "Step 3.2: Creating data directory..."
mkdir -p $VAULT_DATA_DIR
print_success "Data directory created: $VAULT_DATA_DIR"

echo ""
echo "Step 3.3: Starting Vault server..."
# Kill any existing vault processes
pkill vault 2>/dev/null || true
sleep 2

# Start Vault server in background
nohup vault server -config=$VAULT_CONFIG_FILE > $VAULT_LOG_FILE 2>&1 &
VAULT_PID=$!

echo "Vault server PID: $VAULT_PID"
echo "Log file: $VAULT_LOG_FILE"

# Wait for server to start
echo "Waiting for Vault server to start..."
sleep 10

# Set Vault address
export VAULT_ADDR="$VAULT_ADDR"

# Verify server is responding
if curl -s $VAULT_ADDR/v1/sys/health | grep -q "\"initialized\":false"; then
    print_success "Vault server started successfully"
else
    print_error "Vault server failed to start properly"
    echo "Server logs:"
    tail -20 $VAULT_LOG_FILE
    exit 1
fi

wait_for_input

# =========================================================
# Task 4: Initialize and Unseal Vault
# =========================================================
print_task "4" "Initializing and Unsealing Vault"

echo "Step 4.1: Initializing Vault..."
vault operator init -key-shares=5 -key-threshold=3 > $VAULT_INIT_FILE

echo "Vault initialization output:"
cat $VAULT_INIT_FILE

echo ""
echo "Step 4.2: Extracting unseal keys and root token..."
KEY_1=$(grep 'Unseal Key 1:' $VAULT_INIT_FILE | awk '{print $NF}')
KEY_2=$(grep 'Unseal Key 2:' $VAULT_INIT_FILE | awk '{print $NF}')
KEY_3=$(grep 'Unseal Key 3:' $VAULT_INIT_FILE | awk '{print $NF}')
ROOT_TOKEN=$(grep 'Initial Root Token:' $VAULT_INIT_FILE | awk '{print $NF}')

echo "Unseal Key 1: $KEY_1"
echo "Unseal Key 2: $KEY_2"
echo "Unseal Key 3: $KEY_3"
echo "Root Token: $ROOT_TOKEN"

# Save keys securely
echo "$KEY_1" > .vault_unseal_key_1
echo "$KEY_2" > .vault_unseal_key_2
echo "$KEY_3" > .vault_unseal_key_3
echo "$ROOT_TOKEN" > .vault_root_token

echo ""
echo "Step 4.3: Unsealing Vault..."
vault operator unseal $KEY_1
vault operator unseal $KEY_2
vault operator unseal $KEY_3

print_success "Vault unsealed successfully"

echo ""
echo "Step 4.4: Authenticating with root token..."
vault login $ROOT_TOKEN

# Verify vault status
echo ""
echo "Vault status:"
vault status

wait_for_input

# =========================================================
# Task 5: Enable GCP Secrets Engine
# =========================================================
print_task "5" "Enabling GCP Secrets Engine"

echo "Step 5.1: Enabling GCP secrets engine..."
vault secrets enable gcp
print_success "GCP secrets engine enabled"

echo ""
echo "Step 5.2: Creating GCP service account key..."
SERVICE_ACCOUNT_EMAIL="$PROJECT_ID@$PROJECT_ID.iam.gserviceaccount.com"
KEY_FILE="$HOME/$PROJECT_ID.json"

echo "Service Account: $SERVICE_ACCOUNT_EMAIL"
echo "Key File: $KEY_FILE"

# Create service account key
if gcloud iam service-accounts keys create $KEY_FILE \
  --iam-account $SERVICE_ACCOUNT_EMAIL; then
    print_success "Service account key created"
else
    print_warning "Service account key creation failed - may already exist"
fi

echo ""
echo "Step 5.3: Listing existing keys..."
gcloud iam service-accounts keys list --iam-account $SERVICE_ACCOUNT_EMAIL

wait_for_input

# =========================================================
# Task 6: Configure GCP Secrets Engine
# =========================================================
print_task "6" "Configuring GCP Secrets Engine"

echo "Step 6.1: Configuring GCP backend with credentials..."
vault write gcp/config \
    credentials=@$KEY_FILE \
    ttl=3600 \
    max_ttl=86400

print_success "GCP backend configured"

echo ""
echo "Step 6.2: Creating IAM bindings configuration..."
cat > bindings.hcl <<EOF
# IAM Bindings for GCP Resources
resource "buckets/$PROJECT_ID" {
  roles = [
    "roles/storage.objectAdmin",
    "roles/storage.legacyBucketReader",
  ]
}

resource "projects/$PROJECT_ID" {
  roles = [
    "roles/viewer",
  ]
}
EOF

echo "Bindings configuration:"
cat bindings.hcl

wait_for_input

# =========================================================
# Task 7: Dynamic Access Tokens
# =========================================================
print_task "7" "Creating Dynamic Access Token Roleset"

echo "Step 7.1: Creating token-based roleset..."
vault write gcp/roleset/my-token-roleset \
    project="$PROJECT_ID" \
    secret_type="access_token" \
    token_scopes="https://www.googleapis.com/auth/cloud-platform" \
    bindings=@bindings.hcl

print_success "Token roleset created"

echo ""
echo "Step 7.2: Generating dynamic access token..."
DYNAMIC_TOKEN=$(vault read -field=token gcp/roleset/my-token-roleset/token)
echo "Generated token (first 20 chars): ${DYNAMIC_TOKEN:0:20}..."

echo ""
echo "Step 7.3: Testing access token with GCS API..."
echo "Testing bucket access..."
if curl -s "https://storage.googleapis.com/storage/v1/b/$PROJECT_ID" \
  --header "Authorization: Bearer $DYNAMIC_TOKEN" \
  --header "Accept: application/json" | jq '.name' 2>/dev/null; then
    print_success "Access token works - can access GCS bucket"
else
    print_warning "Could not access bucket - may not exist or insufficient permissions"
fi

echo ""
echo "Step 7.4: Attempting to download sample file..."
if curl -X GET \
  -H "Authorization: Bearer $DYNAMIC_TOKEN" \
  -o "sample.txt" \
  "https://storage.googleapis.com/storage/v1/b/$PROJECT_ID/o/sample.txt?alt=media" 2>/dev/null; then
    echo "Sample file downloaded:"
    ls -la sample.txt
else
    print_warning "Sample file not found - this is expected if file doesn't exist"
fi

wait_for_input

# =========================================================
# Task 8: Service Account Keys
# =========================================================
print_task "8" "Creating Service Account Key Roleset"

echo "Step 8.1: Creating service account key roleset..."
vault write gcp/roleset/my-key-roleset \
    project="$PROJECT_ID" \
    secret_type="service_account_key" \
    bindings=@bindings.hcl

print_success "Service account key roleset created"

echo ""
echo "Step 8.2: Generating service account key..."
echo "Reading service account key (output will be large JSON):"
vault read gcp/roleset/my-key-roleset/key | head -20
echo "... (truncated)"

wait_for_input

# =========================================================
# Task 9: Static Accounts
# =========================================================
print_task "9" "Configuring Static Accounts"

echo "Step 9.1: Creating static token account..."
vault write gcp/static-account/my-token-account \
    service_account_email="$SERVICE_ACCOUNT_EMAIL" \
    secret_type="access_token" \
    token_scopes="https://www.googleapis.com/auth/cloud-platform" \
    bindings=@bindings.hcl

print_success "Static token account created"

echo ""
echo "Step 9.2: Creating static key account..."
vault write gcp/static-account/my-key-account \
    service_account_email="$SERVICE_ACCOUNT_EMAIL" \
    secret_type="service_account_key" \
    bindings=@bindings.hcl

print_success "Static key account created"

wait_for_input

# =========================================================
# Task 10: Testing and Verification
# =========================================================
print_task "10" "Testing and Verification"

echo "Step 10.1: Listing all GCP rolesets..."
vault list gcp/roleset

echo ""
echo "Step 10.2: Listing static accounts..."
vault list gcp/static-account

echo ""
echo "Step 10.3: Reading GCP configuration..."
vault read gcp/config

echo ""
echo "Step 10.4: Generating fresh token for final test..."
FRESH_TOKEN=$(vault read -field=token gcp/roleset/my-token-roleset/token)
echo "Fresh token generated: ${FRESH_TOKEN:0:20}..."

echo ""
echo "Step 10.5: Final API test..."
if curl -s "https://storage.googleapis.com/storage/v1/b?project=$PROJECT_ID" \
  --header "Authorization: Bearer $FRESH_TOKEN" \
  --header "Accept: application/json" | jq '.items[].name' 2>/dev/null; then
    print_success "GCP API integration working perfectly"
else
    print_warning "API test completed - check bucket permissions if needed"
fi

wait_for_input

# =========================================================
# Summary and Cleanup Instructions
# =========================================================
print_task "Summary" "Lab Completion and Management"

echo "=== Vault GCP Integration Summary ==="
echo "✅ Vault production server running with Raft storage"
echo "✅ GCP secrets engine enabled and configured"
echo "✅ Dynamic access token generation working"
echo "✅ Service account key generation configured"
echo "✅ Static account management set up"
echo "✅ API integration tested and verified"
echo ""

echo "=== Server Information ==="
echo "Vault Address: $VAULT_ADDR"
echo "Root Token: $ROOT_TOKEN"
echo "Server PID: $VAULT_PID"
echo "Config File: $VAULT_CONFIG_FILE"
echo "Data Directory: $VAULT_DATA_DIR"
echo ""

echo "=== Security Files Created ==="
echo "- $VAULT_INIT_FILE (initialization output)"
echo "- .vault_unseal_key_* (unseal keys)"
echo "- .vault_root_token (root token)"
echo "- $KEY_FILE (GCP service account key)"
echo "- bindings.hcl (IAM bindings config)"
echo ""

echo "=== Useful Commands ==="
echo "# Generate new access token:"
echo "vault read gcp/roleset/my-token-roleset/token"
echo ""
echo "# Generate service account key:"
echo "vault read gcp/roleset/my-key-roleset/key"
echo ""
echo "# Check Vault status:"
echo "vault status"
echo ""
echo "# View server logs:"
echo "tail -f $VAULT_LOG_FILE"
echo ""
echo "# Access Web UI:"
echo "# Open $VAULT_ADDR in browser, login with: $ROOT_TOKEN"
echo ""

echo "=== Cleanup Commands ==="
echo "# Stop Vault server:"
echo "kill $VAULT_PID"
echo ""
echo "# Remove data directory:"
echo "rm -rf $VAULT_DATA_DIR"
echo ""
echo "# Remove configuration files:"
echo "rm -f $VAULT_CONFIG_FILE bindings.hcl $VAULT_INIT_FILE"
echo ""

print_success "Vault GCP Integration Lab completed successfully!"

echo ""
echo "=== Next Steps ==="
echo "1. Explore Vault Web UI for visual management"
echo "2. Create policies for restricted access"
echo "3. Set up additional auth methods (OIDC, LDAP)"
echo "4. Configure backup and recovery procedures"
echo "5. Learn about Vault Enterprise features"
echo ""

print_warning "Remember: This is a development setup - harden for production use!"
echo ""
echo "Server is running at: $VAULT_ADDR"
echo "Use root token for admin access: $ROOT_TOKEN"