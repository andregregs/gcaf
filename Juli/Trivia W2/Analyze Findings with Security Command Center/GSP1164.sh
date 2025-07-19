#!/bin/bash

# =====================================================
# Google Cloud Security Command Center Setup
# Complete SCC Export and Monitoring Configuration
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting Google Cloud Security Command Center setup...${RESET}"

# =====================================================
# 1. AUTHENTICATION & ENVIRONMENT SETUP
# =====================================================
echo -e "${YELLOW}Step 1: Setting up authentication and environment...${RESET}"

# Check current authentication
gcloud auth list

# Set up environment variables
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

# Configure gcloud defaults
gcloud config set compute/zone "$ZONE"
gcloud config set compute/region "$REGION"

echo -e "${GREEN}✅ Environment configured: $PROJECT_ID | $REGION | $ZONE${RESET}"

# =====================================================
# 2. ENABLE SECURITY CENTER API
# =====================================================
echo -e "${YELLOW}Step 2: Enabling Security Command Center API...${RESET}"

gcloud services enable securitycenter.googleapis.com --quiet

echo -e "${GREEN}✅ Security Command Center API enabled${RESET}"

# =====================================================
# 3. SETUP PUB/SUB FOR FINDINGS EXPORT
# =====================================================
echo -e "${YELLOW}Step 3: Setting up Pub/Sub for findings export...${RESET}"

# Create Pub/Sub topic
echo -e "${CYAN}Creating Pub/Sub topic...${RESET}"
gcloud pubsub topics create projects/$DEVSHELL_PROJECT_ID/topics/export-findings-pubsub-topic

# Create Pub/Sub subscription
echo -e "${CYAN}Creating Pub/Sub subscription...${RESET}"
gcloud pubsub subscriptions create export-findings-pubsub-topic-sub \
  --topic=projects/$DEVSHELL_PROJECT_ID/topics/export-findings-pubsub-topic

echo -e "${GREEN}✅ Pub/Sub topic and subscription created${RESET}"

# =====================================================
# 4. MANUAL EXPORT CONFIGURATION
# =====================================================
echo -e "${YELLOW}Step 4: Manual export configuration required...${RESET}"

echo
echo -e "${YELLOW}${BOLD}Create an export-findings-pubsub${RESET} ${BLUE}${BOLD}https://console.cloud.google.com/security/command-center/config/continuous-exports/pubsub?project=$DEVSHELL_PROJECT_ID${RESET}"
echo

# User confirmation
while true; do
    echo -ne "${YELLOW}${BOLD}Do you Want to proceed? (Y/n): ${RESET}"
    read confirm
    case "$confirm" in
        [Yy]) 
            echo -e "${BLUE}Running the command...${RESET}"
            break
            ;;
        [Nn]|"") 
            echo "Operation canceled."
            break
            ;;
        *) 
            echo -e "${RED}Invalid input. Please enter Y or N.${RESET}" 
            ;;
    esac
done

# =====================================================
# 5. CREATE COMPUTE INSTANCE
# =====================================================
echo -e "${YELLOW}Step 5: Creating compute instance for testing...${RESET}"

gcloud compute instances create instance-1 --zone=$ZONE \
  --machine-type=e2-micro \
  --scopes=https://www.googleapis.com/auth/cloud-platform

echo -e "${GREEN}✅ Compute instance created${RESET}"

# =====================================================
# 6. SETUP BIGQUERY EXPORT
# =====================================================
echo -e "${YELLOW}Step 6: Setting up BigQuery export...${RESET}"

# Create BigQuery dataset
echo -e "${CYAN}Creating BigQuery dataset...${RESET}"
bq --location=$REGION mk --dataset $PROJECT_ID:continuous_export_dataset

# Create SCC BigQuery export
echo -e "${CYAN}Creating SCC BigQuery export...${RESET}"
gcloud scc bqexports create scc-bq-cont-export \
  --dataset=projects/$PROJECT_ID/datasets/continuous_export_dataset \
  --project=$PROJECT_ID \
  --quiet

echo -e "${GREEN}✅ BigQuery export configured${RESET}"

# =====================================================
# 7. CREATE SERVICE ACCOUNTS
# =====================================================
echo -e "${YELLOW}Step 7: Creating test service accounts...${RESET}"

for i in {0..2}; do
    echo -e "${CYAN}Creating service account sccp-test-sa-$i...${RESET}"
    gcloud iam service-accounts create sccp-test-sa-$i
    
    echo -e "${CYAN}Creating key for service account sccp-test-sa-$i...${RESET}"
    gcloud iam service-accounts keys create /tmp/sa-key-$i.json \
        --iam-account=sccp-test-sa-$i@$PROJECT_ID.iam.gserviceaccount.com
done

echo -e "${GREEN}✅ Service accounts created${RESET}"

# =====================================================
# 8. WAIT FOR FINDINGS IN BIGQUERY
# =====================================================
echo -e "${YELLOW}Step 8: Waiting for findings to appear in BigQuery...${RESET}"

# Function to query findings
query_findings() {
    bq query --apilog=/dev/null --use_legacy_sql=false --format=pretty \
        "SELECT finding_id, event_time, finding.category FROM continuous_export_dataset.findings"
}

# Function to check if findings exist
has_findings() {
    echo "$1" | grep -qE '^[|] [a-f0-9]{32} '
}

# Function to wait for findings
wait_for_findings() {
    while true; do
        result=$(query_findings)
        
        if has_findings "$result"; then
            echo -e "${GREEN}Findings detected!${RESET}"
            echo "$result"
            break
        else
            echo -e "${CYAN}No findings yet. Waiting for 100 seconds...${RESET}"
            sleep 100
        fi
    done
}

wait_for_findings

echo -e "${GREEN}✅ Findings detected in BigQuery${RESET}"

# =====================================================
# 9. SETUP CLOUD STORAGE BUCKET
# =====================================================
echo -e "${YELLOW}Step 9: Setting up Cloud Storage bucket...${RESET}"

# Set bucket name
export BUCKET_NAME="scc-export-bucket-$PROJECT_ID"

# Create bucket
echo -e "${CYAN}Creating storage bucket...${RESET}"
gsutil mb -l $REGION gs://$BUCKET_NAME/

# Set public access prevention
echo -e "${CYAN}Setting bucket security policy...${RESET}"
gsutil pap set enforced gs://$BUCKET_NAME

echo -e "${GREEN}✅ Storage bucket created and secured${RESET}"

# =====================================================
# 10. EXPORT FINDINGS TO STORAGE
# =====================================================
echo -e "${YELLOW}Step 10: Exporting findings to Cloud Storage...${RESET}"

# Wait for processing
sleep 20

# Export findings to JSON
echo -e "${CYAN}Exporting findings to JSON format...${RESET}"
gcloud scc findings list "projects/$PROJECT_ID" \
  --format=json | jq -c '.[]' > findings.jsonl

sleep 20

# Copy to bucket
echo -e "${CYAN}Copying findings to storage bucket...${RESET}"
gsutil cp findings.jsonl gs://$BUCKET_NAME/

echo -e "${GREEN}✅ Findings exported to Cloud Storage${RESET}"

# =====================================================
# 11. FINAL CONFIGURATION
# =====================================================
echo -e "${YELLOW}Step 11: Final configuration required...${RESET}"

echo
echo -e "${YELLOW}${BOLD}Create an old_findings${RESET} ${BLUE}${BOLD}https://console.cloud.google.com/bigquery?project=$DEVSHELL_PROJECT_ID${RESET}"
echo

echo -e "${GREEN}${BOLD}🎉 Security Command Center setup complete!${RESET}"
echo -e "${CYAN}Resources created:${RESET}"
echo -e "${CYAN}  - Pub/Sub topic: export-findings-pubsub-topic${RESET}"
echo -e "${CYAN}  - BigQuery dataset: continuous_export_dataset${RESET}"
echo -e "${CYAN}  - Storage bucket: $BUCKET_NAME${RESET}"
echo -e "${CYAN}  - Compute instance: instance-1${RESET}"
echo -e "${CYAN}  - Service accounts: sccp-test-sa-0,1,2${RESET}"