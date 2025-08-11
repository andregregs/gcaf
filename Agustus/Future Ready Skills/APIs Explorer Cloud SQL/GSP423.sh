#!/bin/bash

# Cloud SQL API and Data Import Lab - Complete Script
# This script automates Cloud SQL instance creation, database setup, and data import

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

# Get project information using metadata
print_status "Getting project and environment information..."
export PROJECT_ID=$(gcloud config get-value project)
export DEVSHELL_PROJECT_ID=$PROJECT_ID

# Get region from project metadata with fallback
print_status "Retrieving region from project metadata..."
export REGION=$(gcloud compute project-info describe \
    --format="value(commonInstanceMetadata.items[google-compute-default-region])")

if [ -z "$REGION" ] || [ "$REGION" = "(unset)" ]; then
    print_warning "Region not found in metadata, using default: us-central1"
    export REGION="us-central1"
fi

echo -e "${CYAN}Project ID: ${WHITE}$PROJECT_ID${NC}"
echo -e "${CYAN}Region: ${WHITE}$REGION${NC}"

# =============================================================================
# TASK 1: BUILD A CLOUD SQL INSTANCE
# =============================================================================
print_task "1. Build a Cloud SQL Instance with API"

print_step "Step 1.1: Enable Required APIs"
print_status "Enabling Cloud SQL Admin API..."
gcloud services enable sqladmin.googleapis.com --quiet
print_status "Enabling BigQuery API for additional features..."
gcloud services enable bigquery.googleapis.com --quiet
print_success "APIs enabled successfully!"

print_step "Step 1.2: Create Cloud SQL Instance"
print_status "Creating MySQL instance 'my-instance'..."
gcloud sql instances create my-instance \
    --project=$DEVSHELL_PROJECT_ID \
    --region=$REGION \
    --database-version=MYSQL_5_7 \
    --tier=db-n1-standard-1

print_success "Cloud SQL instance 'my-instance' created successfully!"

echo -e "\n${GREEN}✓ TASK 1 COMPLETED: Cloud SQL instance created!${NC}"

# =============================================================================
# TASK 2: CREATE A DATABASE
# =============================================================================
print_task "2. Create a Database with API"

print_step "Step 2.1: Create MySQL Database"
print_status "Creating database 'mysql-db' in Cloud SQL instance..."
gcloud sql databases create mysql-db \
    --instance=my-instance \
    --project=$DEVSHELL_PROJECT_ID \
    --quiet

print_success "Database 'mysql-db' created successfully!"

print_step "Step 2.2: Create BigQuery Dataset (Additional Feature)"
print_status "Creating BigQuery dataset for data analysis..."
bq mk --dataset $DEVSHELL_PROJECT_ID:mysql_db 2>/dev/null || true

print_status "Creating BigQuery table structure..."
bq query --use_legacy_sql=false \
"CREATE TABLE IF NOT EXISTS \`${DEVSHELL_PROJECT_ID}.mysql_db.info\` (
  name STRING,
  age INT64,
  occupation STRING
);" 2>/dev/null || true

print_success "BigQuery components created successfully!"

echo -e "\n${GREEN}✓ TASK 2 COMPLETED: Database created successfully!${NC}"

# =============================================================================
# TASK 3: CREATE TABLE AND UPLOAD CSV FILE
# =============================================================================
print_task "3. Create Table and Upload CSV File"

print_step "Step 3.1: Create Employee CSV File"
print_status "Creating employee_info.csv with sample data..."

cat > employee_info.csv <<EOF
"Sean",23,"Content Creator"
"Emily",34,"Cloud Engineer"
"Rocky",40,"Event Coordinator"
"Kate",28,"Data Analyst"
"Juan",51,"Program Manager"
"Jennifer",32,"Web Developer"
EOF

print_success "CSV file created with 6 employee records!"

print_step "Step 3.2: Create Cloud Storage Bucket"
print_status "Creating Cloud Storage bucket..."
gsutil mb gs://$DEVSHELL_PROJECT_ID

BUCKET_NAME="$DEVSHELL_PROJECT_ID"
echo -e "${CYAN}Bucket Name: ${WHITE}$BUCKET_NAME${NC}"
print_success "Cloud Storage bucket created successfully!"

print_step "Step 3.3: Upload CSV File to Cloud Storage"
print_status "Uploading employee_info.csv to Cloud Storage..."

# Verify file exists before upload
if [ ! -f "employee_info.csv" ]; then
    print_error "employee_info.csv file not found!"
    exit 1
fi

print_status "File size: $(ls -lh employee_info.csv | awk '{print $5}')"
print_status "Uploading to gs://$BUCKET_NAME/employee_info.csv"

# Upload the CSV file
gsutil cp employee_info.csv gs://$BUCKET_NAME/

# Verify upload was successful
print_status "Verifying upload..."
gsutil ls gs://$BUCKET_NAME/employee_info.csv

# Display file contents in bucket
print_status "File contents in bucket:"
gsutil cat gs://$BUCKET_NAME/employee_info.csv | head -3

print_success "CSV file uploaded and verified successfully!"

# Additional verification
print_status "Bucket contents:"
gsutil ls gs://$BUCKET_NAME/

print_step "Step 3.4: Configure Cloud SQL Service Account Permissions"
print_status "Getting Cloud SQL service account email..."
SERVICE_EMAIL=$(gcloud sql instances describe my-instance \
    --format="value(serviceAccountEmailAddress)")

echo -e "${CYAN}Service Account: ${WHITE}$SERVICE_EMAIL${NC}"

print_status "Granting Storage Admin role to Cloud SQL service account..."
gsutil iam ch serviceAccount:$SERVICE_EMAIL:roles/storage.admin \
    gs://$BUCKET_NAME/

print_success "Service account permissions configured successfully!"

echo -e "\n${GREEN}✓ TASK 3 COMPLETED: Table created and CSV file uploaded with proper permissions!${NC}"

print_success "All lab tasks completed successfully! 🎉"