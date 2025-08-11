#!/bin/bash

# Ultra-Fast Cloud SQL Lab Script - ABHI Killer Edition
# Optimized for maximum speed and parallel execution

# Setup
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
export DEVSHELL_PROJECT_ID=$PROJECT_ID
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)
[ -z "$REGION" ] && export REGION="us-central1"

# Parallel API enablement (faster than sequential)
gcloud services enable sqladmin.googleapis.com bigquery.googleapis.com --async &

# Create CSV file immediately (no waiting)
cat > employee_info.csv <<'EOF'
"Sean",23,"Content Creator"
"Emily",34,"Cloud Engineer"
"Rocky",40,"Event Coordinator"
"Kate",28,"Data Analyst"
"Juan",51,"Program Manager"
"Jennifer",32,"Web Developer"
EOF

# Create bucket immediately (parallel with API enablement)
gsutil mb gs://$DEVSHELL_PROJECT_ID &
BUCKET_PID=$!

# Wait for API enablement to complete
wait

# Start SQL instance creation (longest operation) in background
gcloud sql instances create my-instance \
  --project=$DEVSHELL_PROJECT_ID \
  --region=$REGION \
  --database-version=MYSQL_5_7 \
  --tier=db-n1-standard-1 \
  --async &
SQL_PID=$!

# Wait for bucket creation
wait $BUCKET_PID

# Upload CSV immediately while SQL instance is creating
gsutil cp employee_info.csv gs://$DEVSHELL_PROJECT_ID/ &
UPLOAD_PID=$!

# Create BigQuery dataset in parallel
bq mk --dataset $DEVSHELL_PROJECT_ID:mysql_db &
BQ_DATASET_PID=$!

# Wait for SQL instance to be ready
wait $SQL_PID

# Create database immediately after SQL instance is ready
gcloud sql databases create mysql-db --instance=my-instance --project=$DEVSHELL_PROJECT_ID &
DB_PID=$!

# Wait for BigQuery dataset, then create table
wait $BQ_DATASET_PID
bq query --use_legacy_sql=false --format=none \
"CREATE TABLE \`${DEVSHELL_PROJECT_ID}.mysql_db.info\` (
  name STRING,
  age INT64,
  occupation STRING
);" &

# Wait for file upload
wait $UPLOAD_PID

# Get service account and set permissions in parallel
SERVICE_EMAIL=$(gcloud sql instances describe my-instance --format="value(serviceAccountEmailAddress)" 2>/dev/null) &
SA_PID=$!

# Wait for database creation
wait $DB_PID

# Wait for service account email and set permissions
wait $SA_PID
SERVICE_EMAIL=$(gcloud sql instances describe my-instance --format="value(serviceAccountEmailAddress)")
gsutil iam ch serviceAccount:$SERVICE_EMAIL:roles/storage.admin gs://$DEVSHELL_PROJECT_ID/

# Victory message
echo "🚀 ULTRA-FAST COMPLETION! All tasks done in parallel! 🚀"