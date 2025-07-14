#!/bin/bash

# Colors for better output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}=== GCP Compute & Storage Setup ===${NC}\n"

# Check authentication
echo -e "${CYAN}Checking authentication...${NC}"
gcloud auth list

# Setup environment variables
echo -e "\n${CYAN}Setting up environment variables...${NC}"
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

echo "Zone: $ZONE"
echo "Region: $REGION"
echo "Project ID: $PROJECT_ID"

# Configure gcloud defaults
echo -e "\n${GREEN}Configuring gcloud defaults...${NC}"
gcloud config set compute/zone "$ZONE"
gcloud config set compute/region "$REGION"

# Create compute instance
echo -e "\n${GREEN}Creating compute instance...${NC}"
gcloud compute instances --project="$DEVSHELL_PROJECT_ID" create instance-1 \
  --zone="$ZONE" \
  --machine-type=e2-medium \
  --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
  --metadata=enable-oslogin=true \
  --maintenance-policy=MIGRATE \
  --provisioning-model=STANDARD \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --create-disk=auto-delete=yes,boot=yes,device-name=instance-1,image-family=debian-11,image-project=debian-cloud,mode=rw,size=10,type=projects/$DEVSHELL_PROJECT_ID/zones/$ZONE/diskTypes/pd-balanced \
  --no-shielded-secure-boot \
  --shielded-vtpm \
  --shielded-integrity-monitoring \
  --labels=goog-ec-src=vm_add-gcloud \
  --reservation-affinity=any

# Create storage bucket
echo -e "\n${GREEN}Creating storage bucket...${NC}"
gcloud storage buckets create gs://$PROJECT_ID \
  --project=$DEVSHELL_PROJECT_ID \
  --location=$REGION \
  --uniform-bucket-level-access

# Create script for data processing
echo -e "\n${GREEN}Creating data processing script...${NC}"
cat > cp_disk.sh <<'EOF_CP'
#!/bin/bash
echo "=== Starting data processing on instance ==="

# Show system info
cat /proc/cpuinfo

# Update system and install dependencies
sudo apt-get update
sudo apt-get -y -qq install git
echo "Y" | sudo apt-get install python-mpltoolkits.basemap
sudo apt install python3-pip -y

# Install Python packages
pip install --upgrade basemap basemap-data basemap-data-hires pyproj
pip install matplotlib==3.3.4 numpy==1.23.5

# Verify git installation
git --version

# Clone training repository
git clone https://github.com/GoogleCloudPlatform/training-data-analyst
cd training-data-analyst/CPB100/lab2b

# Process earthquake data
bash ingest.sh
bash install_missing.sh
python3 transform.py
ls -l

# Upload results to Cloud Storage
PROJECT_ID=$(gcloud config get-value project)
for file in earthquakes.*; do
  gsutil cp "$file" gs://${PROJECT_ID}/earthquakes/
done

echo "=== Data processing completed ==="
EOF_CP

# Transfer script to instance
echo -e "\n${GREEN}Transferring script to instance...${NC}"
gcloud compute scp cp_disk.sh instance-1:/tmp \
  --project=$DEVSHELL_PROJECT_ID \
  --zone=$ZONE \
  --quiet

# Execute script on instance
echo -e "\n${GREEN}Executing data processing on instance...${NC}"
gcloud compute ssh instance-1 \
  --project=$DEVSHELL_PROJECT_ID \
  --zone=$ZONE \
  --quiet \
  --command="bash /tmp/cp_disk.sh"

echo -e "\n${GREEN}All operations completed successfully!${NC}"
echo -e "${BLUE}=================================${NC}"