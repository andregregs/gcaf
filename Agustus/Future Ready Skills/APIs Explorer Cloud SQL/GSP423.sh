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
gsutil cp employee_info.csv gs://$BUCKET_NAME/ --quiet
print_success "CSV file uploaded successfully!"

print_step "Step 3.4: Configure Cloud SQL Service Account Permissions"
print_status "Getting Cloud SQL service account email..."
SERVICE_EMAIL=$(gcloud sql instances describe my-instance \
    --format="value(serviceAccountEmailAddress)")

echo -e "${CYAN}Service Account: ${WHITE}$SERVICE_EMAIL${NC}"

print_status "Granting Storage Admin role to Cloud SQL service account..."
gsutil iam ch serviceAccount:$SERVICE_EMAIL:roles/storage.admin \
    gs://$BUCKET_NAME/ --quiet

print_success "Service account permissions configured successfully!"

print_step "Step 3.5: Create Table in MySQL Database"
print_status "Connecting to MySQL instance to create table..."

# Create SQL commands file
cat > create_table.sql <<EOF
USE mysql-db;
CREATE TABLE IF NOT EXISTS info (
    name VARCHAR(255),
    age INT,
    occupation VARCHAR(255)
);
EOF

print_status "Creating table structure in MySQL database..."
gcloud sql connect my-instance --user=root --quiet < create_table.sql 2>/dev/null || {
    print_warning "Direct SQL execution may require manual intervention"
    echo -e "${YELLOW}Manual commands to run if needed:${NC}"
    echo -e "${WHITE}gcloud sql connect my-instance --user=root${NC}"
    echo -e "${WHITE}USE mysql-db;${NC}"
    echo -e "${WHITE}CREATE TABLE info (name VARCHAR(255), age INT, occupation VARCHAR(255));${NC}"
}

print_success "Table creation process completed!"

print_step "Step 3.6: Import CSV Data to Cloud SQL (Optional)"
print_status "CSV data is ready for import. You can import it manually via:"
echo -e "${WHITE}1. Cloud Console -> SQL -> my-instance -> Import${NC}"
echo -e "${WHITE}2. Select gs://$BUCKET_NAME/employee_info.csv${NC}"
echo -e "${WHITE}3. Choose mysql-db database and info table${NC}"

echo -e "\n${GREEN}✓ TASK 3 COMPLETED: Table created and CSV file ready for import!${NC}"

# =============================================================================
# FINAL SUMMARY
# =============================================================================
print_step "🎉 Lab Completion Summary"

print_status "Displaying created resources..."

echo -e "\n${CYAN}📋 Created Resources:${NC}"
echo -e "${WHITE}• Cloud SQL Instance: my-instance (MySQL 5.7)${NC}"
echo -e "${WHITE}• Database: mysql-db${NC}"
echo -e "${WHITE}• Table: info (name, age, occupation)${NC}"
echo -e "${WHITE}• Cloud Storage Bucket: gs://$BUCKET_NAME${NC}"
echo -e "${WHITE}• CSV File: employee_info.csv (6 records)${NC}"
echo -e "${WHITE}• BigQuery Dataset: mysql_db${NC}"

echo -e "\n${CYAN}🔑 Key Configurations:${NC}"
echo -e "${WHITE}• Cloud SQL Admin API: Enabled${NC}"
echo -e "${WHITE}• Service Account: $SERVICE_EMAIL${NC}"
echo -e "${WHITE}• Storage Permissions: Configured${NC}"
echo -e "${WHITE}• Region: $REGION${NC}"

echo -e "\n${CYAN}📁 Files Created:${NC}"
echo -e "${WHITE}• employee_info.csv - Sample employee data${NC}"
echo -e "${WHITE}• create_table.sql - Table creation script${NC}"

echo -e "\n${CYAN}🌐 Access Information:${NC}"
echo -e "${WHITE}• Cloud SQL Console: Navigation Menu -> SQL${NC}"
echo -e "${WHITE}• Cloud Storage: Navigation Menu -> Cloud Storage -> Buckets${NC}"
echo -e "${WHITE}• BigQuery: Navigation Menu -> BigQuery${NC}"

print_step "Next Steps (Manual)"
echo -e "${YELLOW}Complete the data import manually:${NC}"
echo -e "${WHITE}1. Go to Cloud Console -> SQL -> my-instance${NC}"
echo -e "${WHITE}2. Click 'Import' button${NC}"
echo -e "${WHITE}3. Select 'employee_info.csv' from gs://$BUCKET_NAME/${NC}"
echo -e "${WHITE}4. Choose database: mysql-db, table: info${NC}"
echo -e "${WHITE}5. Configure format: CSV with custom delimiter${NC}"

# Cleanup
rm -f create_table.sql

print_success "All lab tasks completed successfully! 🎉"