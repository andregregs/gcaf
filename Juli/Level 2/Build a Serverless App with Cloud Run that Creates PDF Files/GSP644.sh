#!/bin/bash

# Colors for better output formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== GCP PDF Converter Cloud Run with Pub/Sub ===${NC}\n"

# ===============================
# 1. AUTHENTICATION & ENVIRONMENT SETUP
# ===============================
echo -e "${GREEN}1. Setting up authentication and environment...${NC}"

# Check current authentication
gcloud auth list

# Export environment variables
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

echo -e "${CYAN}Zone: $ZONE${NC}"
echo -e "${CYAN}Region: $REGION${NC}"
echo -e "${CYAN}Project ID: $GOOGLE_CLOUD_PROJECT${NC}"

# ===============================
# 2. ENABLE CLOUD RUN API
# ===============================
echo -e "\n${GREEN}2. Configuring Cloud Run API...${NC}"

# Disable and re-enable Cloud Run API to refresh
gcloud services disable run.googleapis.com
gcloud services enable run.googleapis.com

# Wait for API to be fully enabled
echo -e "${PURPLE}Waiting for API to be fully enabled...${NC}"
sleep 45

echo -e "${CYAN}Cloud Run API configured${NC}"

# ===============================
# 3. DOWNLOAD AND SETUP SOURCE CODE
# ===============================
echo -e "\n${GREEN}3. Setting up source code...${NC}"

# Clone the pet-theory repository
git clone https://github.com/rosera/pet-theory.git
cd pet-theory/lab03

# Modify package.json to add start script
sed -i '6a\    "start": "node index.js",' package.json

# Install required npm dependencies
echo -e "${PURPLE}Installing npm dependencies...${NC}"
npm install express
npm install body-parser
npm install child_process
npm install @google-cloud/storage

echo -e "${CYAN}Source code setup completed${NC}"

# ===============================
# 4. INITIAL BUILD AND DEPLOYMENT
# ===============================
echo -e "\n${GREEN}4. Building and deploying initial Cloud Run service...${NC}"

# Build container image
echo -e "${PURPLE}Building container image...${NC}"
gcloud builds submit --tag gcr.io/$GOOGLE_CLOUD_PROJECT/pdf-converter

# Deploy Cloud Run service (initial version)
echo -e "${PURPLE}Deploying Cloud Run service...${NC}"
gcloud run deploy pdf-converter \
  --image gcr.io/$GOOGLE_CLOUD_PROJECT/pdf-converter \
  --platform managed \
  --region $REGION \
  --no-allow-unauthenticated \
  --max-instances=1

# Get service URL
SERVICE_URL=$(gcloud beta run services describe pdf-converter --platform managed --region $REGION --format="value(status.url)")
echo -e "${CYAN}Service URL: $SERVICE_URL${NC}"

# ===============================
# 5. TEST INITIAL DEPLOYMENT
# ===============================
echo -e "\n${GREEN}5. Testing initial deployment...${NC}"

# Test without authentication (should fail)
echo -e "${PURPLE}Testing without authentication (expected to fail):${NC}"
curl -X POST $SERVICE_URL

echo

# Test with authentication
echo -e "${PURPLE}Testing with authentication:${NC}"
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" $SERVICE_URL

echo

# ===============================
# 6. SETUP CLOUD STORAGE BUCKETS
# ===============================
echo -e "\n${GREEN}6. Setting up Cloud Storage buckets...${NC}"

# Create upload bucket
gsutil mb gs://$GOOGLE_CLOUD_PROJECT-upload

# Create processed bucket
gsutil mb gs://$GOOGLE_CLOUD_PROJECT-processed

# Create Pub/Sub notification for upload bucket
gsutil notification create -t new-doc -f json -e OBJECT_FINALIZE gs://$GOOGLE_CLOUD_PROJECT-upload

echo -e "${CYAN}Cloud Storage buckets created and configured${NC}"

# ===============================
# 7. SETUP IAM AND PUBSUB
# ===============================
echo -e "\n${GREEN}7. Configuring IAM and Pub/Sub...${NC}"

# Create service account for Pub/Sub to invoke Cloud Run
gcloud iam service-accounts create pubsub-cloud-run-invoker \
  --display-name "PubSub Cloud Run Invoker"

# Grant Cloud Run invoker role to service account
gcloud beta run services add-iam-policy-binding pdf-converter \
  --member=serviceAccount:pubsub-cloud-run-invoker@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role=roles/run.invoker \
  --platform managed \
  --region $REGION

# Get project number
PROJECT_NUMBER=$(gcloud projects describe $GOOGLE_CLOUD_PROJECT --format='value(projectNumber)')

# Grant token creator role to Pub/Sub service account
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member=serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com \
  --role=roles/iam.serviceAccountTokenCreator

# Create Pub/Sub subscription with push endpoint
gcloud beta pubsub subscriptions create pdf-conv-sub \
  --topic new-doc \
  --push-endpoint=$SERVICE_URL \
  --push-auth-service-account=pubsub-cloud-run-invoker@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com

echo -e "${CYAN}IAM and Pub/Sub configured${NC}"

# ===============================
# 8. TEST WITH SAMPLE FILES
# ===============================
echo -e "\n${GREEN}8. Testing with sample files...${NC}"

# Copy sample files to test
echo -e "${PURPLE}Uploading sample files...${NC}"
gsutil -m cp gs://spls/gsp644/* gs://$GOOGLE_CLOUD_PROJECT-upload

# Wait for processing
echo -e "${PURPLE}Waiting for processing (30 seconds)...${NC}"
sleep 30

# Clean up test files
echo -e "${PURPLE}Cleaning up test files...${NC}"
gsutil -m rm gs://$GOOGLE_CLOUD_PROJECT-upload/*

echo -e "${CYAN}Sample file testing completed${NC}"

# ===============================
# 9. CREATE ENHANCED APPLICATION FILES
# ===============================
echo -e "\n${GREEN}9. Creating enhanced application files...${NC}"

# Create enhanced Dockerfile
cat > Dockerfile <<'EOF'
FROM node:20
RUN apt-get update -y \
    && apt-get install -y libreoffice \
    && apt-get clean
WORKDIR /usr/src/app
COPY package.json package*.json ./
RUN npm install --only=production
COPY . .
CMD [ "npm", "start" ]
EOF

# Create enhanced index.js
cat > index.js <<'EOF'
const {promisify} = require('util');
const {Storage}   = require('@google-cloud/storage');
const exec        = promisify(require('child_process').exec);
const storage     = new Storage();
const express     = require('express');
const bodyParser  = require('body-parser');
const app         = express();

app.use(bodyParser.json());

const port = process.env.PORT || 8080;
app.listen(port, () => {
  console.log('Listening on port', port);
});

app.post('/', async (req, res) => {
  try {
    const file = decodeBase64Json(req.body.message.data);
    await downloadFile(file.bucket, file.name);
    const pdfFileName = await convertFile(file.name);
    await uploadFile(process.env.PDF_BUCKET, pdfFileName);
    await deleteFile(file.bucket, file.name);
  }
  catch (ex) {
    console.log(`Error: ${ex}`);
  }
  res.set('Content-Type', 'text/plain');
  res.send('\n\nOK\n\n');
})

function decodeBase64Json(data) {
  return JSON.parse(Buffer.from(data, 'base64').toString());
}

async function downloadFile(bucketName, fileName) {
  const options = {destination: `/tmp/${fileName}`};
  await storage.bucket(bucketName).file(fileName).download(options);
}

async function convertFile(fileName) {
  const cmd = 'libreoffice --headless --convert-to pdf --outdir /tmp ' +
              `"/tmp/${fileName}"`;
  console.log(cmd);
  const { stdout, stderr } = await exec(cmd);
  if (stderr) {
    throw stderr;
  }
  console.log(stdout);
  pdfFileName = fileName.replace(/\.\w+$/, '.pdf');
  return pdfFileName;
}

async function deleteFile(bucketName, fileName) {
  await storage.bucket(bucketName).file(fileName).delete();
}

async function uploadFile(bucketName, fileName) {
  await storage.bucket(bucketName).upload(`/tmp/${fileName}`);
}
EOF

echo -e "${CYAN}Enhanced application files created${NC}"

# ===============================
# 10. REBUILD AND REDEPLOY
# ===============================
echo -e "\n${GREEN}10. Rebuilding and redeploying enhanced service...${NC}"

# Rebuild container image with enhanced code
echo -e "${PURPLE}Rebuilding container image...${NC}"
gcloud builds submit --tag gcr.io/$GOOGLE_CLOUD_PROJECT/pdf-converter

# Redeploy with enhanced configuration
echo -e "${PURPLE}Redeploying with enhanced configuration...${NC}"
gcloud run deploy pdf-converter \
  --image gcr.io/$GOOGLE_CLOUD_PROJECT/pdf-converter \
  --platform managed \
  --region $REGION \
  --memory=2Gi \
  --no-allow-unauthenticated \
  --max-instances=1 \
  --set-env-vars PDF_BUCKET=$GOOGLE_CLOUD_PROJECT-processed

echo -e "${CYAN}Enhanced service deployed successfully${NC}"

# ===============================
# 11. DEPLOYMENT SUMMARY
# ===============================
echo -e "\n${GREEN}=== PDF Converter Deployment Summary ===${NC}"

echo -e "${CYAN}Service Configuration:${NC}"
echo -e "${CYAN}  • Service Name: pdf-converter${NC}"
echo -e "${CYAN}  • Region: $REGION${NC}"
echo -e "${CYAN}  • Memory: 2GB${NC}"
echo -e "${CYAN}  • Max Instances: 1${NC}"
echo -e "${CYAN}  • Authentication: Required${NC}"

echo -e "\n${CYAN}Storage Buckets:${NC}"
echo -e "${CYAN}  • Upload: gs://$GOOGLE_CLOUD_PROJECT-upload${NC}"
echo -e "${CYAN}  • Processed: gs://$GOOGLE_CLOUD_PROJECT-processed${NC}"

echo -e "\n${CYAN}Pub/Sub Configuration:${NC}"
echo -e "${CYAN}  • Topic: new-doc${NC}"
echo -e "${CYAN}  • Subscription: pdf-conv-sub${NC}"
echo -e "${CYAN}  • Trigger: OBJECT_FINALIZE${NC}"

echo -e "\n${YELLOW}Testing Commands:${NC}"
echo -e "${CYAN}1. Upload a document to test:${NC}"
echo -e "   gsutil cp [your-document] gs://$GOOGLE_CLOUD_PROJECT-upload/"
echo -e "${CYAN}2. Check processed files:${NC}"
echo -e "   gsutil ls gs://$GOOGLE_CLOUD_PROJECT-processed/"
echo -e "${CYAN}3. View service logs:${NC}"
echo -e "   gcloud logs read --filter='resource.labels.service_name=pdf-converter'"

echo -e "\n${GREEN}🎉 PDF Converter service deployed successfully!${NC}"
echo -e "${CYAN}Upload any document to gs://$GOOGLE_CLOUD_PROJECT-upload/ and it will be automatically converted to PDF.${NC}"