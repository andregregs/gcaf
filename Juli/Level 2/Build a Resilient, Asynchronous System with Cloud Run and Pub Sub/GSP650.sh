#!/bin/bash

# ========================================
# GOOGLE CLOUD MICROSERVICES SETUP SCRIPT
# ========================================
# This script sets up a microservices architecture with:
# - Lab Report Service (Pub/Sub Publisher)
# - Email Service (Pub/Sub Subscriber) 
# - SMS Service (Pub/Sub Subscriber)

# ========================================
# 1. INITIAL CONFIGURATION
# ========================================
echo "🔧 Setting up Google Cloud configuration..."

# Authenticate and set project variables
gcloud auth list
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

# Configure gcloud defaults
gcloud config set compute/zone $ZONE
gcloud config set compute/region $REGION

# Enable required services
gcloud services enable run.googleapis.com

echo "✅ Configuration complete!"

# ========================================
# 2. CREATE PUB/SUB TOPIC
# ========================================
echo "📡 Creating Pub/Sub topic..."

gcloud pubsub topics create new-lab-report

echo "✅ Pub/Sub topic created!"

# ========================================
# 3. SETUP PROJECT FILES
# ========================================
echo "📁 Cloning project repository..."

git clone https://github.com/rosera/pet-theory.git
cd pet-theory/lab05

echo "✅ Project files ready!"

# ========================================
# 4. LAB REPORT SERVICE (PUBLISHER)
# ========================================
echo "🚀 Setting up Lab Report Service..."

cd lab-service

# Install dependencies
npm install express body-parser @google-cloud/pubsub

# Create package.json
cat > package.json << 'EOF'
{
  "name": "lab-report-service",
  "version": "1.0.0",
  "description": "Lab Report Service - Publishes reports to Pub/Sub",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "author": "Patrick - IT",
  "license": "ISC",
  "dependencies": {
    "@google-cloud/pubsub": "^4.0.0",
    "body-parser": "^1.20.2",
    "express": "^4.18.2"
  }
}
EOF

# Create main application
cat > index.js << 'EOF'
const { PubSub } = require('@google-cloud/pubsub');
const express = require('express');
const bodyParser = require('body-parser');

const pubsub = new PubSub();
const app = express();
const port = process.env.PORT || 8080;

app.use(bodyParser.json());

app.listen(port, () => {
  console.log(`Lab Report Service listening on port ${port}`);
});

// Endpoint to receive lab reports and publish to Pub/Sub
app.post('/', async (req, res) => {
  try {
    const labReport = req.body;
    console.log(`Publishing lab report: ${labReport.id}`);
    
    await publishPubSubMessage(labReport);
    res.status(204).send();
  } catch (error) {
    console.error('Error publishing message:', error);
    res.status(500).send(error);
  }
});

async function publishPubSubMessage(labReport) {
  const buffer = Buffer.from(JSON.stringify(labReport));
  await pubsub.topic('new-lab-report').publish(buffer);
  console.log(`Lab report ${labReport.id} published successfully`);
}
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM node:18
WORKDIR /usr/src/app
COPY package.json package*.json ./
RUN npm install --only=production
COPY . .
CMD ["npm", "start"]
EOF

# Build and deploy
echo "🔨 Building and deploying Lab Report Service..."
gcloud builds submit --tag gcr.io/$PROJECT_ID/lab-report-service

gcloud run deploy lab-report-service \
  --image gcr.io/$PROJECT_ID/lab-report-service \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --max-instances=1

echo "✅ Lab Report Service deployed!"

# ========================================
# 5. EMAIL SERVICE (SUBSCRIBER)
# ========================================
echo "📧 Setting up Email Service..."

cd ../email-service

# Install dependencies
npm install express body-parser

# Create package.json
cat > package.json << 'EOF'
{
  "name": "email-service",
  "version": "1.0.0",
  "description": "Email Service - Processes lab reports from Pub/Sub",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "author": "Patrick - IT",
  "license": "ISC",
  "dependencies": {
    "body-parser": "^1.20.2",
    "express": "^4.18.2"
  }
}
EOF

# Create main application
cat > index.js << 'EOF'
const express = require('express');
const bodyParser = require('body-parser');

const app = express();
const port = process.env.PORT || 8080;

app.use(bodyParser.json());

app.listen(port, () => {
  console.log(`Email Service listening on port ${port}`);
});

// Endpoint to receive Pub/Sub messages
app.post('/', async (req, res) => {
  try {
    const labReport = decodeBase64Json(req.body.message.data);
    console.log(`Email Service: Processing report ${labReport.id}...`);
    
    await sendEmail(labReport);
    console.log(`Email Service: Report ${labReport.id} processed successfully ✉️`);
    
    res.status(204).send();
  } catch (error) {
    console.error(`Email Service: Report processing failed:`, error);
    res.status(500).send();
  }
});

function decodeBase64Json(data) {
  return JSON.parse(Buffer.from(data, 'base64').toString());
}

async function sendEmail(labReport) {
  // Simulate email sending
  console.log(`Sending email notification for report ${labReport.id}`);
  // Add actual email logic here
}
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM node:18
WORKDIR /usr/src/app
COPY package.json package*.json ./
RUN npm install --only=production
COPY . .
CMD ["npm", "start"]
EOF

# Build and deploy
echo "🔨 Building and deploying Email Service..."
gcloud builds submit --tag gcr.io/$PROJECT_ID/email-service

gcloud run deploy email-service \
  --image gcr.io/$PROJECT_ID/email-service \
  --platform managed \
  --region $REGION \
  --no-allow-unauthenticated \
  --max-instances=1

echo "✅ Email Service deployed!"

# ========================================
# 6. SMS SERVICE (SUBSCRIBER)
# ========================================
echo "📱 Setting up SMS Service..."

cd ../sms-service

# Install dependencies
npm install express body-parser

# Create package.json
cat > package.json << 'EOF'
{
  "name": "sms-service",
  "version": "1.0.0",
  "description": "SMS Service - Processes lab reports from Pub/Sub",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "author": "Patrick - IT",
  "license": "ISC",
  "dependencies": {
    "body-parser": "^1.20.2",
    "express": "^4.18.2"
  }
}
EOF

# Create main application
cat > index.js << 'EOF'
const express = require('express');
const bodyParser = require('body-parser');

const app = express();
const port = process.env.PORT || 8080;

app.use(bodyParser.json());

app.listen(port, () => {
  console.log(`SMS Service listening on port ${port}`);
});

// Endpoint to receive Pub/Sub messages
app.post('/', async (req, res) => {
  try {
    const labReport = decodeBase64Json(req.body.message.data);
    console.log(`SMS Service: Processing report ${labReport.id}...`);
    
    await sendSms(labReport);
    console.log(`SMS Service: Report ${labReport.id} processed successfully 📱`);
    
    res.status(204).send();
  } catch (error) {
    console.error(`SMS Service: Report processing failed:`, error);
    res.status(500).send();
  }
});

function decodeBase64Json(data) {
  return JSON.parse(Buffer.from(data, 'base64').toString());
}

async function sendSms(labReport) {
  // Simulate SMS sending
  console.log(`Sending SMS notification for report ${labReport.id}`);
  // Add actual SMS logic here
}
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM node:18
WORKDIR /usr/src/app
COPY package.json package*.json ./
RUN npm install --only=production
COPY . .
CMD ["npm", "start"]
EOF

# Build and deploy
echo "🔨 Building and deploying SMS Service..."
gcloud builds submit --tag gcr.io/$PROJECT_ID/sms-service

gcloud run deploy sms-service \
  --image gcr.io/$PROJECT_ID/sms-service \
  --platform managed \
  --region $REGION \
  --no-allow-unauthenticated \
  --max-instances=1

echo "✅ SMS Service deployed!"

# ========================================
# 7. SETUP PUB/SUB SUBSCRIPTIONS
# ========================================
echo "🔗 Setting up Pub/Sub subscriptions..."

# Get project number and create service account
PROJECT_NUMBER=$(gcloud projects list --filter="$PROJECT_ID" --format='value(PROJECT_NUMBER)')

gcloud iam service-accounts create pubsub-cloud-run-invoker \
  --display-name "PubSub Cloud Run Invoker"

# Grant permissions for email service
gcloud run services add-iam-policy-binding email-service \
  --member=serviceAccount:pubsub-cloud-run-invoker@$PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/run.invoker \
  --region $REGION \
  --platform managed

# Grant permissions for SMS service
gcloud run services add-iam-policy-binding sms-service \
  --member=serviceAccount:pubsub-cloud-run-invoker@$PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/run.invoker \
  --region $REGION \
  --platform managed

# Grant token creator role
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com \
  --role=roles/iam.serviceAccountTokenCreator

# Get service URLs
EMAIL_SERVICE_URL=$(gcloud run services describe email-service \
  --platform managed \
  --region=$REGION \
  --format="value(status.address.url)")

SMS_SERVICE_URL=$(gcloud run services describe sms-service \
  --platform managed \
  --region=$REGION \
  --format="value(status.address.url)")

# Create subscriptions
gcloud pubsub subscriptions create email-service-sub \
  --topic new-lab-report \
  --push-endpoint=$EMAIL_SERVICE_URL \
  --push-auth-service-account=pubsub-cloud-run-invoker@$PROJECT_ID.iam.gserviceaccount.com

gcloud pubsub subscriptions create sms-service-sub \
  --topic new-lab-report \
  --push-endpoint=$SMS_SERVICE_URL \
  --push-auth-service-account=pubsub-cloud-run-invoker@$PROJECT_ID.iam.gserviceaccount.com

echo "✅ Pub/Sub subscriptions created!"

# ========================================
# 8. DEPLOYMENT SUMMARY
# ========================================
echo ""
echo "🎉 DEPLOYMENT COMPLETE!"
echo "======================================"
echo "Architecture Overview:"
echo "1. Lab Report Service - Receives HTTP requests and publishes to Pub/Sub"
echo "2. Email Service - Subscribes to Pub/Sub and processes email notifications"
echo "3. SMS Service - Subscribes to Pub/Sub and processes SMS notifications"
echo ""
echo "Services deployed:"
echo "📋 Lab Report Service: $(gcloud run services describe lab-report-service --platform managed --region=$REGION --format="value(status.address.url)")"
echo "📧 Email Service: $EMAIL_SERVICE_URL"
echo "📱 SMS Service: $SMS_SERVICE_URL"
echo ""
echo "Test your setup by sending a POST request to the Lab Report Service!"
echo "======================================"