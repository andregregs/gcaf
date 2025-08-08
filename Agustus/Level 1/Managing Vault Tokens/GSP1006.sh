#!/bin/bash

# HashiCorp Vault Service Tokens Lab - Complete Script
# This script automates the Vault service tokens learning lab

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
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
    echo -e "\n${PURPLE}════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════════════════════════════${NC}"
}

print_task() {
    echo -e "\n${CYAN}▶ TASK: $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# TASK 1: INSTALL VAULT
# =============================================================================
print_task "1. Install Vault"

print_step "Step 1.1: Add HashiCorp GPG Key"
print_status "Adding the HashiCorp GPG key..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
print_success "HashiCorp GPG key added successfully!"

print_step "Step 1.2: Add HashiCorp Repository"
print_status "Adding the official HashiCorp Linux repository..."
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
print_success "HashiCorp repository added successfully!"

print_step "Step 1.3: Update and Install Vault"
print_status "Updating package list..."
sudo apt-get update

print_status "Installing Vault..."
sudo apt-get install vault -y
print_success "Vault installation completed!"

print_step "Step 1.4: Verify Installation"
print_status "Verifying Vault installation..."
vault --version
print_success "Vault installation verified!"

echo -e "\n${GREEN}✓ TASK 1 COMPLETED: Vault has been successfully installed!${NC}"

# =============================================================================
# TASK 2: START THE VAULT SERVER
# =============================================================================
print_task "2. Start the Vault Server"

print_step "Step 2.1: Start Vault Development Server"
print_status "Starting Vault development server in background..."
print_warning "This will run in background mode. The server output will be saved to vault_dev_server.log"

# Start Vault dev server in background and capture output
vault server -dev > vault_dev_server.log 2>&1 &
VAULT_PID=$!

print_status "Waiting for server to start (5 seconds)..."
sleep 5

print_step "Step 2.2: Extract Server Information"
print_status "Extracting Unseal Key and Root Token from server output..."

# Wait a bit more and extract info from log
sleep 3

# Extract the vault address, unseal key, and root token from the log
export VAULT_ADDR='http://127.0.0.1:8200'
UNSEAL_KEY=$(grep "Unseal Key:" vault_dev_server.log | awk -F': ' '{print $2}')
ROOT_TOKEN=$(grep "Root Token:" vault_dev_server.log | awk -F': ' '{print $2}')

echo -e "${CYAN}Vault Address: ${WHITE}$VAULT_ADDR${NC}"
echo -e "${CYAN}Unseal Key: ${WHITE}$UNSEAL_KEY${NC}"
echo -e "${CYAN}Root Token: ${WHITE}$ROOT_TOKEN${NC}"

export VAULT_TOKEN="$ROOT_TOKEN"

print_step "Step 2.3: Verify Server Status"
print_status "Checking Vault server status..."
vault status
print_success "Vault server is running successfully!"

echo -e "\n${GREEN}✓ TASK 2 COMPLETED: Vault server started and configured!${NC}"

# =============================================================================
# TASK 3: SERVICE TOKENS
# =============================================================================
print_task "3. Service Tokens"

print_step "Step 3.1: Tokens with Use Limit"
print_status "Creating token with TTL of 1 hour and use limit of 2..."

TOKEN_OUTPUT=$(vault token create -ttl=1h -use-limit=2 -policy=default -format=json)
USE_LIMIT_TOKEN=$(echo $TOKEN_OUTPUT | jq -r '.auth.client_token')

echo -e "${CYAN}Use Limit Token: ${WHITE}$USE_LIMIT_TOKEN${NC}"

print_status "Testing token usage (1st use - lookup)..."
VAULT_TOKEN=$USE_LIMIT_TOKEN vault token lookup

print_status "Testing token usage (2nd use - write to cubbyhole)..."
VAULT_TOKEN=$USE_LIMIT_TOKEN vault write cubbyhole/token value=1234567890

print_status "Testing token usage (3rd use - should fail)..."
echo -e "${YELLOW}This should fail due to use limit exhaustion:${NC}"
VAULT_TOKEN=$USE_LIMIT_TOKEN vault read cubbyhole/token || echo -e "${RED}Expected failure: Token use limit exhausted${NC}"

print_step "Step 3.2: Periodic Service Tokens"
print_status "Creating periodic token with 24 hours period..."

PERIODIC_TOKEN_OUTPUT=$(vault token create -policy="default" -period=24h -format=json)
PERIODIC_TOKEN=$(echo $PERIODIC_TOKEN_OUTPUT | jq -r '.auth.client_token')

echo -e "${CYAN}Periodic Token: ${WHITE}$PERIODIC_TOKEN${NC}"

print_status "Looking up periodic token details..."
vault token lookup $PERIODIC_TOKEN

print_step "Step 3.3: Renew Service Tokens"
print_status "Creating token with TTL of 45 seconds and max TTL of 120 seconds..."

RENEWABLE_TOKEN_OUTPUT=$(vault token create -ttl=45 -explicit-max-ttl=120 -format=json)
RENEWABLE_TOKEN=$(echo $RENEWABLE_TOKEN_OUTPUT | jq -r '.auth.client_token')

echo -e "${CYAN}Renewable Token: ${WHITE}$RENEWABLE_TOKEN${NC}"

print_status "Renewing token TTL..."
vault token renew $RENEWABLE_TOKEN

print_status "Renewing token with 60 seconds increment..."
vault token renew -increment=60 $RENEWABLE_TOKEN

print_status "Attempting another renewal (may be capped)..."
vault token renew -increment=60 $RENEWABLE_TOKEN

print_step "Step 3.4: Short-lived Tokens"
print_status "Creating token with TTL of 60 seconds..."

SHORT_TOKEN_OUTPUT=$(vault token create -ttl=60s -format=json)
SHORT_TOKEN=$(echo $SHORT_TOKEN_OUTPUT | jq -r '.auth.client_token')

echo -e "${CYAN}Short-lived Token: ${WHITE}$SHORT_TOKEN${NC}"

print_status "Looking up short-lived token details..."
vault token lookup $SHORT_TOKEN

print_step "Step 3.5: Orphan Tokens"
print_status "Creating orphan token..."

ORPHAN_TOKEN_OUTPUT=$(vault token create -orphan -format=json)
ORPHAN_TOKEN=$(echo $ORPHAN_TOKEN_OUTPUT | jq -r '.auth.client_token')

echo -e "${CYAN}Orphan Token: ${WHITE}$ORPHAN_TOKEN${NC}"

print_status "Looking up orphan token details..."
vault token lookup $ORPHAN_TOKEN

print_step "Step 3.6: Token Roles"
print_status "Creating token role named 'zabbix'..."

vault write auth/token/roles/zabbix \
    allowed_policies="policy1, policy2, policy3" \
    orphan=true \
    period=8h

print_status "Creating token using the zabbix role..."
ROLE_TOKEN_OUTPUT=$(vault token create -role=zabbix -format=json)
ROLE_TOKEN=$(echo $ROLE_TOKEN_OUTPUT | jq -r '.auth.client_token')

echo -e "${CYAN}Role Token: ${WHITE}$ROLE_TOKEN${NC}"

print_step "Step 3.7: Revoke Service Tokens"
print_status "Creating test policy..."

vault policy write test -<<EOF
path "auth/token/create" {
   capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

print_status "Creating parent token with 1 minute TTL..."
vault token create -ttl=60 -policy=test -format=json | jq -r ".auth.client_token" > parent_token.txt
PARENT_TOKEN=$(cat parent_token.txt)

print_status "Creating child token using parent token..."
VAULT_TOKEN=$PARENT_TOKEN vault token create -ttl=180 -policy=default -format=json | jq -r ".auth.client_token" > child_token.txt
CHILD_TOKEN=$(cat child_token.txt)

print_status "Creating orphan token using parent token..."
VAULT_TOKEN=$PARENT_TOKEN vault token create -orphan -ttl=180 -policy=default -format=json | jq -r ".auth.client_token" > orphan_token.txt
ORPHAN_TOKEN_FILE=$(cat orphan_token.txt)

# Reset to root token for revocation
export VAULT_TOKEN="$ROOT_TOKEN"

print_status "Revoking parent token..."
vault token revoke $PARENT_TOKEN

print_status "Verifying parent token revocation..."
vault token lookup $PARENT_TOKEN || echo -e "${GREEN}Expected: Parent token successfully revoked${NC}"

print_status "Checking child token (should be revoked with parent)..."
vault token lookup $CHILD_TOKEN || echo -e "${GREEN}Expected: Child token revoked with parent${NC}"

print_status "Checking orphan token (should still exist)..."
vault token lookup $ORPHAN_TOKEN_FILE

print_step "Step 3.8: Apply Token Types with AppRole"
print_status "Unsetting VAULT_TOKEN for AppRole demonstration..."
unset VAULT_TOKEN

print_status "Enabling AppRole auth method..."
VAULT_TOKEN="$ROOT_TOKEN" vault auth enable approle

print_status "Creating jenkins role with periodic tokens..."
VAULT_TOKEN="$ROOT_TOKEN" vault write auth/approle/role/jenkins policies="jenkins" period="24h"

print_status "Retrieving RoleID for jenkins role..."
VAULT_TOKEN="$ROOT_TOKEN" vault read -format=json auth/approle/role/jenkins/role-id | jq -r ".data.role_id" > role_id.txt
ROLE_ID=$(cat role_id.txt)

print_status "Generating SecretID for jenkins role..."
VAULT_TOKEN="$ROOT_TOKEN" vault write -f -format=json auth/approle/role/jenkins/secret-id | jq -r ".data.secret_id" > secret_id.txt
SECRET_ID=$(cat secret_id.txt)

print_status "Authenticating with AppRole..."
AUTH_OUTPUT=$(VAULT_TOKEN="$ROOT_TOKEN" vault write auth/approle/login role_id=$ROLE_ID secret_id=$SECRET_ID -format=json)
JENKINS_TOKEN=$(echo $AUTH_OUTPUT | jq -r '.auth.client_token')

echo -e "${CYAN}Jenkins Token: ${WHITE}$JENKINS_TOKEN${NC}"

print_status "Looking up jenkins token details..."
VAULT_TOKEN="$ROOT_TOKEN" vault token lookup $JENKINS_TOKEN

print_status "Saving token policies to file and uploading to Cloud Storage..."
VAULT_TOKEN="$ROOT_TOKEN" vault token lookup -format=json $JENKINS_TOKEN | jq -r .data.policies > token_policies.txt

export PROJECT_ID=$(gcloud config get-value project)
gsutil cp token_policies.txt gs://$PROJECT_ID

echo -e "\n${GREEN}✓ TASK 3 COMPLETED: Service tokens demonstration completed successfully!${NC}"

print_success "All lab tasks completed successfully! 🎉"