#!/bin/bash

# =====================================================
# Google Cloud Setup Script - Pet Theory Lab 05
# Microservices with Cloud Run and Pub/Sub
# =====================================================

echo "Starting Google Cloud Platform setup..."

# =====================================================
# 1. INITIAL SETUP & CONFIGURATION
# =====================================================
echo "Step 1: Setting up initial configuration..."

# Check current authentication
gcloud auth list

# Set up environment variables
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

# Configure gcloud defaults
gcloud config set compute/zone $ZONE
gcloud config set compute/region $REGION

echo "Project ID: $PROJECT_ID"
echo "Zone: $ZONE"
echo "Region: $REGION"

# =====================================================
# 2. ENABLE SERVICES AND CREATE PUB/SUB TOPIC
# =====================================================
echo "Step 2: Enabling services and creating Pub/Sub topic..."

# Create Pub/Sub topic for lab reports
gcloud pubsub topics create new-lab-report

# Enable Cloud Run API
gcloud services enable run.googleapis.com

# =====================================================
# 3. CLONE REPOSITORY AND SETUP LAB-SERVICE
# =====================================================
echo "Step 3: Setting up lab-service..."

# Clone the pet-theory repository
git clone https://github.com/rosera/pet-theory.git
cd pet-theory/lab05/lab-service

# Install Node.js dependencies
npm install express
npm install body-parser
npm install @google-cloud/pubsub

# Create package.json for lab-service
cat > package.json <<EOF_CP
{
  "name": "lab05",
  "version": "1.0.0",
  "description": "This is lab05 of the Pet Theory labs",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "keywords": [],
  "author": "Patrick - IT",
  "license": "ISC",
  "dependencies": {
    "@google-cloud/pubsub": "^4.0.0",
    "body-parser": "^1.20.2",
    "express": "^4.18.2"
  }
}
EOF_CP

# Create main application file for lab-service
cat > index.js <<EOF_CP
const {PubSub} = require('@google-cloud/pubsub');
const pubsub = new PubSub();
const express = require('express');
const app = express();
const bodyParser = require('body-parser');
app.use(bodyParser.json());
const port = process.env.PORT || 8080;

app.listen(port, () => {
  console.log('Listening on port', port);
});

app.post('/', async (req, res) => {
  try {
    const labReport = req.body;
    await publishPubSubMessage(labReport);
    res.status(204).send();
  }
  catch (ex) {
    console.log(ex);
    res.status(500).send(ex);
  }
})

async function publishPubSubMessage(labReport) {
  const buffer = Buffer.from(JSON.stringify(labReport));
  await pubsub.topic('new-lab-report').publish(buffer);
}
EOF_CP

# Create Dockerfile for lab-service
cat > Dockerfile <<EOF_CP
FROM node:18
WORKDIR /usr/src/app
COPY package.json package*.json ./
RUN npm install --only=production
COPY . .
CMD [ "npm", "start" ]
EOF_CP

# Build and deploy lab-service
echo "Building and deploying lab-report-service..."
gcloud builds submit \
  --tag gcr.io/$GOOGLE_CLOUD_PROJECT/lab-report-service

gcloud run deploy lab-report-service \
  --image gcr.io/$GOOGLE_CLOUD_PROJECT/lab-report-service \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --max-instances=1

# =====================================================
# 4. SETUP EMAIL-SERVICE
# =====================================================
echo "Step 4: Setting up email-service..."

# Navigate to email-service directory
cd ~/pet-theory/lab05/email-service

# Install Node.js dependencies
npm install express
npm install body-parser

# Create package.json for email-service
cat > package.json <<EOF_CP
{
    "name": "lab05",
    "version": "1.0.0",
    "description": "This is lab05 of the Pet Theory labs",
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
      "express": "^4.18.2"
    }
  }
EOF_CP

# Create main application file for email-service
cat > index.js <<EOF_CP
const express = require('express');
const app = express();
const bodyParser = require('body-parser');
app.use(bodyParser.json());

const port = process.env.PORT || 8080;
app.listen(port, () => {
  console.log('Listening on port', port);
});

app.post('/', async (req, res) => {
  const labReport = decodeBase64Json(req.body.message.data);
  try {
    console.log(\`Email Service: Report \${labReport.id} trying...\`);
    sendEmail();
    console.log(\`Email Service: Report \${labReport.id} success :-)\`);
    res.status(204).send();
  }
  catch (ex) {
    console.log(\`Email Service: Report \${labReport.id} failure: \${ex}\`);
    res.status(500).send();
  }
})

function decodeBase64Json(data) {
  return JSON.parse(Buffer.from(data, 'base64').toString());
}

function sendEmail() {
  console.log('Sending email');
}
EOF_CP

# Create Dockerfile for email-service
cat > Dockerfile <<EOF_CP
FROM node:18
WORKDIR /usr/src/app
COPY package.json package*.json ./
RUN npm install --only=production
COPY . .
CMD [ "npm", "start" ]
EOF_CP

# Build and deploy email-service
echo "Building and deploying email-service..."
gcloud builds submit \
  --tag gcr.io/$GOOGLE_CLOUD_PROJECT/email-service

gcloud run deploy email-service \
  --image gcr.io/$GOOGLE_CLOUD_PROJECT/email-service \
  --platform managed \
  --region $REGION \
  --no-allow-unauthenticated \
  --max-instances=1

# =====================================================
# 5. SETUP IAM AND PUB/SUB SUBSCRIPTION
# =====================================================
echo "Step 5: Setting up IAM and Pub/Sub subscription for email service..."

# Get project number
PROJECT_NUMBER=$(gcloud projects list --filter="qwiklabs-gcp" --format='value(PROJECT_NUMBER)')

# Create service account for Pub/Sub to invoke Cloud Run
gcloud iam service-accounts create pubsub-cloud-run-invoker \
  --display-name "PubSub Cloud Run Invoker"

echo "Region: $REGION"

# Grant Cloud Run invoker role to service account
gcloud run services add-iam-policy-binding email-service \
  --member=serviceAccount:pubsub-cloud-run-invoker@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role=roles/run.invoker \
  --region $REGION \
  --platform managed

# Grant token creator role to Pub/Sub service account
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member=serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com \
  --role=roles/iam.serviceAccountTokenCreator

# Get email service URL
EMAIL_SERVICE_URL=$(gcloud run services describe email-service \
  --platform managed \
  --region=$REGION \
  --format="value(status.address.url)")

echo "Email Service URL: $EMAIL_SERVICE_URL"

# Create Pub/Sub subscription for email service
gcloud pubsub subscriptions create email-service-sub \
  --topic new-lab-report \
  --push-endpoint=$EMAIL_SERVICE_URL \
  --push-auth-service-account=pubsub-cloud-run-invoker@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com

# =====================================================
# 6. SETUP SMS-SERVICE
# =====================================================
echo "Step 6: Setting up sms-service..."

# Navigate to sms-service directory
cd ~/pet-theory/lab05/sms-service

# Install Node.js dependencies
npm install express
npm install body-parser

# Create package.json for sms-service
cat > package.json <<EOF_CP
{
    "name": "lab05",
    "version": "1.0.0",
    "description": "This is lab05 of the Pet Theory labs",
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
      "express": "^4.18.2"
    }
  }
EOF_CP

# Create main application file for sms-service
cat > index.js <<EOF_CP
const express = require('express');
const app = express();
const bodyParser = require('body-parser');
app.use(bodyParser.json());

const port = process.env.PORT || 8080;
app.listen(port, () => {
  console.log('Listening on port', port);
});

app.post('/', async (req, res) => {
  const labReport = decodeBase64Json(req.body.message.data);
  try {
    console.log(\`SMS Service: Report \${labReport.id} trying...\`);
    sendSms();
    console.log(\`SMS Service: Report \${labReport.id} success :-)\`);    
    res.status(204).send();
  }
  catch (ex) {
    console.log(\`SMS Service: Report \${labReport.id} failure: \${ex}\`);
    res.status(500).send();
  }
})

function decodeBase64Json(data) {
  return JSON.parse(Buffer.from(data, 'base64').toString());
}

function sendSms() {
  console.log('Sending SMS');
}
EOF_CP

# Create Dockerfile for sms-service
cat > Dockerfile <<EOF_CP
FROM node:18
WORKDIR /usr/src/app
COPY package.json package*.json ./
RUN npm install --only=production
COPY . .
CMD [ "npm", "start" ]
EOF_CP

# Build and deploy sms-service
echo "Building and deploying sms-service..."
gcloud builds submit \
  --tag gcr.io/$GOOGLE_CLOUD_PROJECT/sms-service

gcloud run deploy sms-service \
  --image gcr.io/$GOOGLE_CLOUD_PROJECT/sms-service \
  --platform managed \
  --region $REGION \
  --no-allow-unauthenticated \
  --max-instances=1

# =====================================================
# 7. SETUP COMPLETE
# =====================================================
echo "✅ Setup complete!"
echo "Services deployed:"
echo "  - lab-report-service (publicly accessible)"
echo "  - email-service (private, triggered by Pub/Sub)"
echo "  - sms-service (private)"
echo ""
echo "Pub/Sub topic 'new-lab-report' created with email-service subscription."
echo "All services are ready to use!"