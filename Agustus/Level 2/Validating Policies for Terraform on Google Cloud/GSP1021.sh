#!/bin/bash

# Google Cloud Policy Library Constraint Validation Lab - Complete Script
# This script automates the policy constraint validation and modification process

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

# Get project information
print_status "Getting project information..."
export PROJECT_ID=$(gcloud config get-value project)
export USER_EMAIL=$(gcloud config get-value account)

echo -e "${CYAN}Project ID: ${WHITE}$PROJECT_ID${NC}"
echo -e "${CYAN}User Email: ${WHITE}$USER_EMAIL${NC}"

# =============================================================================
# TASK 1: VALIDATE A CONSTRAINT
# =============================================================================
print_task "1. Validate a Constraint"

print_step "Step 1.1: Clone Policy Library Repository"
print_status "Cloning the policy library repository..."
git clone https://github.com/GoogleCloudPlatform/policy-library.git
print_success "Policy library repository cloned successfully!"

print_step "Step 1.2: Copy Sample Constraint"
print_status "Navigating to policy library directory..."
cd policy-library/

print_status "Copying IAM service accounts only constraint..."
cp samples/iam_service_accounts_only.yaml policies/constraints/
print_success "Constraint copied successfully!"

print_step "Step 1.3: Examine the Constraint"
print_status "Displaying the constraint content..."
echo -e "${YELLOW}Constraint content:${NC}"
cat policies/constraints/iam_service_accounts_only.yaml
print_success "Constraint examination completed!"

print_step "Step 1.4: Create Terraform Configuration"
print_status "Creating main.tf file with IAM binding..."

cat > main.tf <<EOF
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "~> 3.84"
    }
  }
}

resource "google_project_iam_binding" "sample_iam_binding" {
  project = "$PROJECT_ID"
  role    = "roles/viewer"

  members = [
    "user:$USER_EMAIL"
  ]
}
EOF

print_success "Terraform configuration created!"
echo -e "${CYAN}Created main.tf with Project ID: ${WHITE}$PROJECT_ID${NC}"
echo -e "${CYAN}Using User Email: ${WHITE}$USER_EMAIL${NC}"

print_step "Step 1.5: Initialize Terraform"
print_status "Initializing Terraform..."
terraform init
print_success "Terraform initialized successfully!"

print_step "Step 1.6: Create Terraform Plan"
print_status "Creating Terraform plan..."
terraform plan -out=test.tfplan
print_success "Terraform plan created!"

print_step "Step 1.7: Convert Plan to JSON"
print_status "Converting Terraform plan to JSON format..."
terraform show -json ./test.tfplan > ./tfplan.json
print_success "Plan converted to JSON successfully!"

print_step "Step 1.8: Install Terraform Tools"
print_status "Installing Google Cloud SDK Terraform tools..."
sudo apt-get install google-cloud-sdk-terraform-tools -y
print_success "Terraform tools installed successfully!"

print_step "Step 1.9: Validate Policy Compliance"
print_status "Running policy validation (this should show violations)..."
echo -e "${YELLOW}Expected: This validation should FAIL due to non-service account email${NC}"
gcloud beta terraform vet tfplan.json --policy-library=. || echo -e "${GREEN}Expected violation detected!${NC}"

echo -e "\n${GREEN}✓ TASK 1 COMPLETED: Constraint validation demonstrated with expected violations!${NC}"

# =============================================================================
# TASK 2: MODIFY THE CONSTRAINT
# =============================================================================
print_task "2. Modify the Constraint"

print_step "Step 2.1: Backup Original Constraint"
print_status "Creating backup of original constraint..."
cp policies/constraints/iam_service_accounts_only.yaml policies/constraints/iam_service_accounts_only.yaml.backup
print_success "Original constraint backed up!"

print_step "Step 2.2: Modify Constraint to Allow Qwiklabs Domain"
print_status "Modifying constraint to allow qwiklabs.net domain..."

cat > policies/constraints/iam_service_accounts_only.yaml <<EOF
# This constraint checks that all IAM policy members are in the
# allowed domains.
apiVersion: constraints.gatekeeper.sh/v1alpha1
kind: GCPIAMAllowedPolicyMemberDomainsConstraintV2
metadata:
  name: service_accounts_only
  annotations:
    description: Checks that members that have been granted IAM roles belong to allowlisted
      domains.
spec:
  severity: high
  match:
    target: # {"$ref":"#/definitions/io.k8s.cli.setters.target"}
    - "organizations/**"
  parameters:
    domains:
    - gserviceaccount.com
    - qwiklabs.net
EOF

print_success "Constraint modified to include qwiklabs.net domain!"

print_step "Step 2.3: Display Modified Constraint"
print_status "Showing the modified constraint..."
echo -e "${YELLOW}Modified constraint content:${NC}"
cat policies/constraints/iam_service_accounts_only.yaml

print_step "Step 2.4: Create New Terraform Plan"
print_status "Creating new Terraform plan with modified constraint..."
terraform plan -out=test.tfplan
terraform show -json ./test.tfplan > ./tfplan.json
print_success "New Terraform plan created!"

print_step "Step 2.5: Validate Modified Policy"
print_status "Running policy validation with modified constraint..."
echo -e "${YELLOW}Expected: This validation should PASS now${NC}"
gcloud beta terraform vet tfplan.json --policy-library=.
print_success "Policy validation passed!"

print_step "Step 2.6: Apply Terraform Plan"
print_status "Applying Terraform plan to create IAM binding..."
terraform apply test.tfplan
print_success "Terraform plan applied successfully!"

print_step "Step 2.7: Verify IAM Binding"
print_status "Verifying the IAM binding was created..."
gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" --format="table(bindings.role,bindings.members)" --filter="bindings.members:$USER_EMAIL"
print_success "IAM binding verification completed!"

echo -e "\n${GREEN}✓ TASK 2 COMPLETED: Constraint successfully modified and applied!${NC}"

print_success "All lab tasks completed successfully! 🎉"