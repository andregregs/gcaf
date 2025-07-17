#!/bin/bash

# ================================
# INITIAL SETUP & CONFIGURATION
# ================================

# Check authentication and set project variables
gcloud auth list
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

# Configure gcloud defaults
gcloud config set compute/zone $ZONE
gcloud config set compute/region $REGION

# Enable required services
gcloud services enable run.googleapis.com

# Create Pub/Sub topic
gcloud pubsub topics create new-lab-report

# Clone repository
git clone https://github.com/rosera/pet-theory.git

# ================================
# SHARED FUNCTIONS
# ================================

create_package_json() {
    local service_name=$1
    local dependencies=$2
    
    cat > package.json <<EOF
{
  "name": "$service_name",
  "version": "1.0.0",
  "description": "Pet Theory Lab - $service_name",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "keywords": [],
  "author": "Patrick - IT",
  "license": "ISC",
  "dependencies": {
    "body-parser": "^1.20.2",
    "express": "^4.18.2"$dependencies
  }
}
EOF
}

create_dockerfile() {
    cat > Dockerfile <<EOF
FROM node:18
WORKDIR /usr/src/app
COPY package.json package*.json ./
RUN npm install --only=production
COPY . .
CMD [ "npm", "start" ]
EOF
}

deploy_service() {
    local service_name=$1
    local allow_unauthenticated=$2
    
    gcloud builds submit --tag gcr.io/$GOOGLE_CLOUD_PROJECT/$service_name
    
    if [ "$allow_unauthenticated" = "true" ]; then
        gcloud run deploy $service_name \
            --image gcr.io/$GOOGLE_CLOUD_PROJECT/$service_name \
            --platform managed \
            --region $REGION \
            --allow-unauthenticated \
            --max-instances=1
    else
        gcloud run deploy $service_name \
            --image gcr.io/$GOOGLE_CLOUD_PROJECT/$service_name \
            --platform managed \
            --region $REGION \
            --no-allow-unauthenticated \
            --max-instances=1
    fi
}

# ================================
# LAB REPORT SERVICE
# ================================

cd pet-theory/lab05/lab-service
npm install express body-parser @google-cloud/pubsub

# Create package.json with Pub/Sub dependency
create_package_json "lab-report-service" ',
    "@google-cloud/pubsub": "^4.0.0"'

# Create lab report service
cat > index.js <<EOF
const {PubSub} = require('@google-cloud/pubsub');
const pubsub = new PubSub();
const express = require('express');
const app = express();
const bodyParser = require('body-parser');

app.use(bodyParser.json());
const port = process.env.PORT || 8080;

app.listen(port, () => {
  console.log('Lab Report Service listening on port', port);
});

app.post('/', async (req, res) => {
  try {
    const labReport = req.body;
    await publishPubSubMessage(labReport);
    res.status(204).send();
  } catch (ex) {
    console.log(ex);
    res.status(500).send(ex);
  }
});

async function publishPubSubMessage(labReport) {
  const buffer = Buffer.from(JSON.stringify(labReport));
  await pubsub.topic('new-lab-report').publish(buffer);
}
EOF

create_dockerfile
deploy_service "lab-report-service" "true"

# ================================
# EMAIL SERVICE
# ================================

cd ~/pet-theory/lab05/email-service
npm install express body-parser

# Create package.json for email service
create_package_json "email-service" ""

# Create email service
cat > index.js <<EOF
const express = require('express');
const app = express();
const bodyParser = require('body-parser');

app.use(bodyParser.json());
const port = process.env.PORT || 8080;

app.listen(port, () => {
  console.log('Email Service listening on port', port);
});

app.post('/', async (req, res) => {
  const labReport = decodeBase64Json(req.body.message.data);
  try {
    console.log(\`Email Service: Report \${labReport.id} trying...\`);
    sendEmail();
    console.log(\`Email Service: Report \${labReport.id} success :-)\`);
    res.status(204).send();
  } catch (ex) {
    console.log(\`Email Service: Report \${labReport.id} failure: \${ex}\`);
    res.status(500).send();
  }
});

function decodeBase64Json(data) {
  return JSON.parse(Buffer.from(data, 'base64').toString());
}

function sendEmail() {
  console.log('Sending email');
}
EOF

create_dockerfile
deploy_service "email-service" "false"

# ================================
# SMS SERVICE
# ================================

cd ~/pet-theory/lab05/sms-service
npm install express body-parser

# Create package.json for SMS service
create_package_json "sms-service" ""

# Create SMS service
cat > index.js <<EOF
const express = require('express');
const app = express();
const bodyParser = require('body-parser');

app.use(bodyParser.json());
const port = process.env.PORT || 8080;

app.listen(port, () => {
  console.log('SMS Service listening on port', port);
});

app.post('/', async (req, res) => {
  const labReport = decodeBase64Json(req.body.message.data);
  try {
    console.log(\`SMS Service: Report \${labReport.id} trying...\`);
    sendSms();
    console.log(\`SMS Service: Report \${labReport.id} success :-)\`);    
    res.status(204).send();
  } catch (ex) {
    console.log(\`SMS Service: Report \${labReport.id} failure: \${ex}\`);
    res.status(500).send();
  }
});

function decodeBase64Json(data) {
  return JSON.parse(Buffer.from(data, 'base64').toString());
}

function sendSms() {
  console.log('Sending SMS');
}
EOF

create_dockerfile
deploy_service "sms-service" "false"

# ================================
# IAM & PUB/SUB SETUP
# ================================

# Get project number and create service account
PROJECT_NUMBER=$(gcloud projects list --filter="qwiklabs-gcp" --format='value(PROJECT_NUMBER)')
gcloud iam service-accounts create pubsub-cloud-run-invoker \
    --display-name "PubSub Cloud Run Invoker"

# Set IAM permissions
gcloud run services add-iam-policy-binding email-service \
    --member=serviceAccount:pubsub-cloud-run-invoker@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
    --role=roles/run.invoker \
    --region $REGION \
    --platform managed

gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
    --member=serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com \
    --role=roles/iam.serviceAccountTokenCreator

# Get email service URL and create subscription
EMAIL_SERVICE_URL=$(gcloud run services describe email-service \
    --platform managed \
    --region=$REGION \
    --format="value(status.address.url)")

echo "Email Service URL: $EMAIL_SERVICE_URL"

gcloud pubsub subscriptions create email-service-sub \
    --topic new-lab-report \
    --push-endpoint=$EMAIL_SERVICE_URL \
    --push-auth-service-account=pubsub-cloud-run-invoker@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com

echo "Setup completed successfully!"
echo "Services deployed:"
echo "- Lab Report Service (public)"
echo "- Email Service (private with Pub/Sub subscription)"
echo "- SMS Service (private)"