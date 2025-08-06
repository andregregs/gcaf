#!/bin/bash

# =========================================================
# Google App Engine Java HTTP Server Deployment Script
# =========================================================
# Deskripsi: Script untuk download, deploy, dan test
# aplikasi Java HTTP Server di Google App Engine
# =========================================================

set -e  # Keluar jika ada error

# Konfigurasi
APP_NAME="Java HTTP Server"
SOURCE_BUCKET="gs://spls/gsp068/appengine-java21/appengine-java21/*"
APP_DIRECTORY="helloworld/http-server"

echo "=== Google App Engine Java Deployment ==="
echo "Application: $APP_NAME"
echo "Deployment Mode: Standard Environment"
echo ""

# 1. Autentikasi dan setup environment
echo "Step 1: Setting up Google Cloud environment..."
gcloud auth list
echo ""

# Get project info
export PROJECT_ID=$(gcloud config get-value project)
echo "Using Project ID: $PROJECT_ID"

# Enable required APIs
echo "Enabling required Google Cloud APIs..."
gcloud services enable appengine.googleapis.com cloudbuild.googleapis.com --quiet
echo "✅ APIs enabled successfully"
echo ""

# 2. Download sample HTTP Server app
echo "Step 2: Downloading sample HTTP Server application..."
echo "Source: $SOURCE_BUCKET"

# Bersihkan directory jika sudah ada
if [ -d "helloworld" ]; then
  echo "Removing existing helloworld directory..."
  rm -rf helloworld
fi

echo "Copying files from Google Cloud Storage..."
gcloud storage cp -r "$SOURCE_BUCKET" .

if [ $? -eq 0 ]; then
  echo "✅ Files downloaded successfully"
else
  echo "❌ ERROR: Failed to download files"
  exit 1
fi

# Tampilkan struktur files yang di-download
echo ""
echo "Downloaded files structure:"
find helloworld -type f -name "*.java" -o -name "*.xml" -o -name "*.gradle" | head -10
echo ""

# 3. Navigate to application directory
echo "Step 3: Navigating to application directory..."
if [ ! -d "$APP_DIRECTORY" ]; then
  echo "❌ ERROR: Application directory '$APP_DIRECTORY' not found"
  echo "Available directories:"
  ls -la
  exit 1
fi

cd "$APP_DIRECTORY"
echo "✅ Current directory: $(pwd)"
echo ""

# 4. Tampilkan informasi aplikasi
echo "Step 4: Application Information..."
echo "=== Main.java Source Code Preview ==="
if [ -f "src/main/java/com/example/appengine/Main.java" ]; then
  echo "Found Main.java file:"
  head -20 src/main/java/com/example/appengine/Main.java
  echo "..."
  echo ""
else
  echo "❌ WARNING: Main.java not found in expected location"
fi

echo "=== Application Features ==="
echo "- HTTP Server with Java 21"
echo "- Endpoint '/': Returns 'Hello World!'"
echo "- Endpoint '/foo': Returns 'Foo!'"
echo "- Port: Environment variable PORT or default 8080"
echo ""

# 5. Verify App Engine configuration
echo "Step 5: Verifying App Engine configuration..."
if [ -f "../../src/main/webapp/WEB-INF/appengine-web.xml" ]; then
  echo "Found appengine-web.xml configuration"
  echo "Configuration preview:"
  cat ../../src/main/webapp/WEB-INF/appengine-web.xml
else
  echo "❌ WARNING: appengine-web.xml not found"
fi
echo ""

# 6. Create App Engine application if needed
echo "Step 6: Checking App Engine application status..."

# Check if App Engine app already exists
APP_EXISTS=$(gcloud app describe --format="value(id)" 2>/dev/null || echo "")
if [ -n "$APP_EXISTS" ]; then
  echo "✅ App Engine application already exists: $APP_EXISTS"
else
  echo "⚠️  App Engine application not found. Creating new application..."
  echo "Available regions for App Engine:"
  echo "- us-central (Iowa)"
  echo "- us-west2 (Los Angeles)" 
  echo "- us-east1 (South Carolina)"
  echo "- europe-west (Belgium)"
  echo "- asia-northeast1 (Tokyo)"
  echo ""
  
  # Auto-detect region or use default
  REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central")
  echo "Creating App Engine application in region: $REGION"
  
  if gcloud app create --region="$REGION"; then
    echo "✅ App Engine application created successfully!"
  else
    echo "❌ Failed to create App Engine application."
    echo "Try manually with: gcloud app create --region=REGION_NAME"
    echo "Available regions: us-central, us-west2, us-east1, europe-west, asia-northeast1"
    exit 1
  fi
fi
echo ""

# 7. Deploy aplikasi
echo "Step 7: Deploying application to Google App Engine..."
echo "Deploying... This may take several minutes."
echo ""

# Deploy dengan error handling dan retry logic
DEPLOY_SUCCESS="false"
for attempt in 1 2 3; do
  echo "Deployment attempt $attempt/3..."
  
  if gcloud app deploy --quiet --promote; then
    echo "✅ Deployment successful!"
    DEPLOY_SUCCESS="true"
    break
  else
    echo "❌ Deployment attempt $attempt failed."
    if [ $attempt -lt 3 ]; then
      echo "Retrying in 10 seconds..."
      sleep 10
    fi
  fi
done

if [ "$DEPLOY_SUCCESS" = "false" ]; then
  echo "❌ All deployment attempts failed. Common issues:"
  echo "- App Engine API not enabled"
  echo "- Billing not set up"
  echo "- Invalid configuration files"
  echo "- Network connectivity issues"
  echo ""
  echo "Manual troubleshooting steps:"
  echo "1. Check if App Engine API is enabled:"
  echo "   gcloud services enable appengine.googleapis.com"
  echo "2. Verify billing is set up in Cloud Console"
  echo "3. Try manual deployment:"
  echo "   gcloud app deploy"
  exit 1
fi
echo ""

# 8. Get application URL
echo "Step 8: Getting application URL..."
APP_URL=$(gcloud app browse --no-launch-browser 2>&1 | grep -o 'https://[^[:space:]]*' | head -1)

if [ -n "$APP_URL" ]; then
  echo "✅ Application deployed successfully!"
  echo "Application URL: $APP_URL"
else
  echo "❌ Could not retrieve application URL"
  echo "Trying alternative method..."
  gcloud app browse
fi
echo ""

# 9. Test endpoints
echo "Step 9: Testing application endpoints..."
if [ -n "$APP_URL" ]; then
  echo "=== Endpoint Testing ==="
  echo "Main page (/):"
  echo "URL: $APP_URL"
  echo "Expected response: 'Hello World!'"
  echo ""
  
  echo "Foo page (/foo):"
  echo "URL: $APP_URL/foo"
  echo "Expected response: 'Foo!'"
  echo ""
  
  echo "Testing with curl (if available)..."
  if command -v curl &> /dev/null; then
    echo "Testing main endpoint:"
    curl -s "$APP_URL" || echo "Curl test failed - this is normal if the app is still starting"
    echo ""
    echo "Testing /foo endpoint:"
    curl -s "$APP_URL/foo" || echo "Curl test failed - this is normal if the app is still starting"
  else
    echo "Curl not available - please test manually in browser"
  fi
else
  echo "⚠️  Cannot test endpoints - URL not available"
fi
echo ""

# 10. Deployment summary
echo "=== Deployment Summary ==="
echo "✅ Application: $APP_NAME"
echo "✅ Platform: Google App Engine Standard Environment"
echo "✅ Runtime: Java 21"
echo "✅ Project: $PROJECT_ID"
if [ -n "$APP_URL" ]; then
  echo "✅ URL: $APP_URL"
fi
echo ""

echo "✅ Deployment completed successfully!"