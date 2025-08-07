#!/bin/bash

# HashiCorp Vault Setup with GCP Integration
# This script sets up Vault server and configures GCP secrets engine

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Function to print colored status messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "\n${PURPLE}================================${NC}"
    echo -e "${WHITE}STEP: $1${NC}"
    echo -e "${PURPLE}================================${NC}"
}

# =============================================================================
# STEP 1: Initial Setup and Environment Configuration
# =============================================================================
print_step "1. Initial Setup and Environment Configuration"

print_status "Authenticating with Google Cloud..."
gcloud auth list

print_status "Setting up environment variables..."
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_ID=$DEVSHELL_PROJECT_ID

echo -e "${CYAN}Project ID: ${WHITE}$PROJECT_ID${NC}"
echo -e "${CYAN}Zone: ${WHITE}$ZONE${NC}"
echo -e "${CYAN}Region: ${WHITE}$REGION${NC}"

print_success "Environment configuration completed!"

# =============================================================================
# STEP 2: HashiCorp Vault Installation
# =============================================================================
print_step "2. HashiCorp Vault Installation"

print_status "Adding HashiCorp APT repository..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

print_status "Installing Vault..."
sudo apt-get update
sudo apt-get install vault -y

print_status "Verifying Vault installation..."
vault --version

print_success "Vault installation completed!"

# =============================================================================
# STEP 3: Vault Server Configuration
# =============================================================================
print_step "3. Vault Server Configuration"

print_status "Creating Vault configuration file..."
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
cluster_addr = "https://127.0.1:8201"
ui = true
EOF_CP

print_status "Creating data directory..."
mkdir -p ./vault/data

print_success "Vault configuration completed!"

# =============================================================================
# STEP 4: Vault Server Startup and Initialization
# =============================================================================
print_step "4. Vault Server Startup and Initialization"

print_status "Starting Vault server in background..."
nohup vault server -config=config.hcl > vault_server.log 2>&1 &

print_status "Waiting for server to start (10 seconds)..."
sleep 10

print_status "Setting Vault address..."
export VAULT_ADDR='http://127.0.0.1:8200'

print_status "Initializing Vault..."
vault operator init -key-shares=5 -key-threshold=3 > vault_init_output.txt

print_success "Vault server started and initialized!"

# =============================================================================
# STEP 5: Vault Unsealing Process
# =============================================================================
print_step "5. Vault Unsealing Process"

print_status "Extracting unseal keys and root token..."
KEY_1=$(grep 'Unseal Key 1:' vault_init_output.txt | awk '{print $NF}')
KEY_2=$(grep 'Unseal Key 2:' vault_init_output.txt | awk '{print $NF}')
KEY_3=$(grep 'Unseal Key 3:' vault_init_output.txt | awk '{print $NF}')
TOKEN=$(grep 'Initial Root Token:' vault_init_output.txt | awk '{print $NF}')

print_status "Unsealing Vault with 3 keys..."
vault operator unseal $KEY_1
vault operator unseal $KEY_2
vault operator unseal $KEY_3

print_status "Logging into Vault..."
vault login $TOKEN

print_success "Vault unsealing completed!"
print_warning "Important: Save the vault_init_output.txt file securely!"

# =============================================================================
# STEP 6: GCP Secrets Engine Configuration
# =============================================================================
print_step "6. GCP Secrets Engine Configuration"

print_status "Enabling GCP secrets engine..."
vault secrets enable gcp

print_status "Creating service account key..."
SERVICE_ACCOUNT_EMAIL="$DEVSHELL_PROJECT_ID@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com"

gcloud iam service-accounts keys create ~/$DEVSHELL_PROJECT_ID.json \
  --iam-account $SERVICE_ACCOUNT_EMAIL

print_status "Listing service account keys..."
gcloud iam service-accounts keys list --iam-account $SERVICE_ACCOUNT_EMAIL

print_status "Configuring GCP secrets engine in Vault..."
vault write gcp/config \
  credentials=@/home/$USER/$DEVSHELL_PROJECT_ID.json \
  ttl=3600 \
  max_ttl=86400

print_success "GCP secrets engine configuration completed!"

# =============================================================================
# STEP 7: Creating IAM Bindings and Rolesets
# =============================================================================
print_step "7. Creating IAM Bindings and Rolesets"

print_status "Creating IAM bindings configuration..."
cat > bindings.hcl <<EOF_CP
resource "buckets/$DEVSHELL_PROJECT_ID" {
  roles = [
    "roles/storage.objectAdmin",
    "roles/storage.legacyBucketReader",
  ]
}
EOF_CP

print_status "Creating token-based roleset..."
vault write gcp/roleset/my-token-roleset \
    project="$DEVSHELL_PROJECT_ID" \
    secret_type="access_token" \
    token_scopes="https://www.googleapis.com/auth/cloud-platform" \
    bindings=@bindings.hcl

print_status "Creating service account key roleset..."
vault write gcp/roleset/my-key-roleset \
    project="$DEVSHELL_PROJECT_ID" \
    secret_type="service_account_key" \
    bindings=@bindings.hcl

print_success "Rolesets creation completed!"

# =============================================================================
# STEP 8: Testing Token-based Access
# =============================================================================
print_step "8. Testing Token-based Access"

print_status "Generating access token..."
TOKEN=$(vault read -field=token gcp/roleset/my-token-roleset/token)

print_status "Testing bucket access with generated token..."
curl "https://storage.googleapis.com/storage/v1/b/$DEVSHELL_PROJECT_ID" \
  --header "Authorization: Bearer $TOKEN" \
  --header "Accept: application/json"

print_status "Testing file download with generated token..."
curl -X GET \
  -H "Authorization: Bearer $TOKEN" \
  -o "sample.txt" \
  "https://storage.googleapis.com/storage/v1/b/$DEVSHELL_PROJECT_ID/o/sample.txt?alt=media"

print_success "Token-based access testing completed!"

# =============================================================================
# STEP 9: Static Account Configuration
# =============================================================================
print_step "9. Static Account Configuration"

print_status "Creating static account for access tokens..."
vault write gcp/static-account/my-token-account \
    service_account_email="$SERVICE_ACCOUNT_EMAIL" \
    secret_type="access_token" \
    token_scopes="https://www.googleapis.com/auth/cloud-platform" \
    bindings=@bindings.hcl

print_status "Creating static account for service account keys..."
vault write gcp/static-account/my-key-account \
    service_account_email="$SERVICE_ACCOUNT_EMAIL" \
    secret_type="service_account_key" \
    bindings=@bindings.hcl

print_success "Static account configuration completed!"

# =============================================================================
# STEP 10: Final Verification and Summary
# =============================================================================
print_step "10. Final Verification and Summary"

print_status "Reading service account key from roleset..."
vault read gcp/roleset/my-key-roleset/key

print_success "Setup completed successfully!"

echo -e "\n${GREEN}================================================${NC}"
echo -e "${WHITE}           SETUP COMPLETION SUMMARY${NC}"
echo -e "${GREEN}================================================${NC}"
echo -e "${CYAN}✓ Vault Server Status:${NC} Running on http://127.0.0.1:8200"
echo -e "${CYAN}✓ GCP Integration:${NC} Configured and tested"
echo -e "${CYAN}✓ Rolesets Created:${NC} my-token-roleset, my-key-roleset"
echo -e "${CYAN}✓ Static Accounts:${NC} my-token-account, my-key-account"
echo -e "${CYAN}✓ Project ID:${NC} $PROJECT_ID"
echo -e "${GREEN}================================================${NC}"

print_warning "Remember to:"
echo -e "${YELLOW}  • Keep vault_init_output.txt secure${NC}"
echo -e "${YELLOW}  • Monitor vault_server.log for any issues${NC}"
echo -e "${YELLOW}  • Access Vault UI at http://127.0.0.1:8200${NC}"

print_success "All steps completed successfully! 🎉"