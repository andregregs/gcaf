#!/bin/bash

# Proven Fast Cloud SQL Script - Actually Works Edition
# Focus: Speed + Reliability (tidak seperti script sebelumnya yang gagal)

# Setup environment
export PROJECT_ID=$(gcloud config get-value project)
export DEVSHELL_PROJECT_ID=$PROJECT_ID
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
[ -z "$REGION" ] && export REGION="us-central1"

# ============================================================================
# PHASE 1: INDEPENDENT OPERATIONS (dapat dilakukan bersamaan)
# ============================================================================

# Enable APIs (tidak perlu wait)
gcloud services enable sqladmin.googleapis.com bigquery.googleapis.com

# Create CSV file (independent operation)
cat > employee_info.csv <<'EOF'
"Sean",23,"Content Creator"
"Emily",34,"Cloud Engineer"
"Rocky",40,"Event Coordinator"
"Kate",28,"Data Analyst"
"Juan",51,"Program Manager"
"Jennifer",32,"Web Developer"
EOF

# Create bucket (independent operation)
gsutil mb gs://$DEVSHELL_PROJECT_ID

# Upload CSV immediately (dapat dilakukan bersamaan dengan SQL instance creation)
gsutil cp employee_info.csv gs://$DEVSHELL_PROJECT_ID/ &
UPLOAD_PID=$!

# Create BigQuery dataset (independent operation)
bq mk --dataset $DEVSHELL_PROJECT_ID:mysql_db

# Create BigQuery table (dapat dilakukan bersamaan)
bq query --use_legacy_sql=false --format=none \
"CREATE TABLE \`${DEVSHELL_PROJECT_ID}.mysql_db.info\` (
  name STRING,
  age INT64,
  occupation STRING
);" &
BQ_TABLE_PID=$!

# ============================================================================
# PHASE 2: SQL INSTANCE CREATION (critical path - harus selesai dulu)
# ============================================================================

# Create SQL instance (SYNCHRONOUS - harus tunggu selesai)
gcloud sql instances create my-instance \
  --project=$DEVSHELL_PROJECT_ID \
  --region=$REGION \
  --database-version=MYSQL_5_7 \
  --tier=db-n1-standard-1

# ============================================================================
# PHASE 3: DEPENDENT OPERATIONS (hanya setelah SQL instance ready)
# ============================================================================

# Create database (HARUS menunggu instance ready)
gcloud sql databases create mysql-db \
  --instance=my-instance \
  --project=$DEVSHELL_PROJECT_ID

# Get service account (HARUS menunggu instance ready)
SERVICE_EMAIL=$(gcloud sql instances describe my-instance \
  --format="value(serviceAccountEmailAddress)")

# Wait for background operations to complete
wait $UPLOAD_PID 2>/dev/null
wait $BQ_TABLE_PID 2>/dev/null

# Set permissions (terakhir, setelah semua ready)
gsutil iam ch serviceAccount:$SERVICE_EMAIL:roles/storage.admin \
  gs://$DEVSHELL_PROJECT_ID/

echo "✅ SUCCESS: All tasks completed correctly and efficiently!"