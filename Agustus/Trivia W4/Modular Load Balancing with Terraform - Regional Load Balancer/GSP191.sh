#!/bin/bash

# =========================================================
# Google Cloud Load Balancer Setup with Terraform
# =========================================================
# Deskripsi: Script untuk mengatur load balancer di GCP
# menggunakan Terraform dengan konfigurasi dasar
# =========================================================

set -e  # Keluar jika ada error

echo "=== Starting Google Cloud Load Balancer Setup ==="

# 1. Autentikasi dan validasi akun Google Cloud
echo "Step 1: Authenticating Google Cloud account..."
gcloud auth list

# 2. Mengatur region default berdasarkan project metadata
echo "Step 2: Setting up default region..."
export REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")

if [ -z "$REGION" ]; then
  echo "Warning: No default region found, using us-central1"
  export REGION="us-central1"
fi

echo "Using region: $REGION"
gcloud config set compute/region "$REGION"

# 3. Clone repository Terraform untuk load balancer
echo "Step 3: Cloning Terraform load balancer repository..."
if [ ! -d "terraform-google-lb" ]; then
  git clone https://github.com/GoogleCloudPlatform/terraform-google-lb
else
  echo "Repository already exists, skipping clone..."
fi

# 4. Pindah ke direktori contoh basic
echo "Step 4: Navigating to basic example directory..."
cd ~/terraform-google-lb/examples/basic

# 5. Mengatur variabel project ID
echo "Step 5: Setting up project variables..."
export GOOGLE_PROJECT=$(gcloud config get-value project)
echo "Using project: $GOOGLE_PROJECT"

# 6. Inisialisasi Terraform
echo "Step 6: Initializing Terraform..."
terraform init

# 7. Update konfigurasi region di variables.tf
echo "Step 7: Updating region configuration..."
sed -i 's/us-central1/'"$REGION"'/g' variables.tf
echo "Region updated to: $REGION"

# 8. Membuat dan menampilkan execution plan
echo "Step 8: Creating Terraform execution plan..."
echo "$GOOGLE_PROJECT" | terraform plan -out=tfplan

# 9. Menerapkan konfigurasi Terraform
echo "Step 9: Applying Terraform configuration..."
echo "$GOOGLE_PROJECT" | terraform apply --auto-approve

# 10. Mengambil IP address dari load balancer
echo "Step 10: Retrieving load balancer IP address..."
EXTERNAL_IP=$(terraform output load_balancer_default_ip 2>/dev/null | tr -d '"' | xargs echo -n)

# Fallback jika output command di atas tidak berhasil
if [ -z "$EXTERNAL_IP" ]; then
  EXTERNAL_IP=$(terraform output | grep load_balancer_default_ip | cut -d = -f2 | xargs echo -n | tr -d '"')
fi

# 11. Menampilkan hasil akhir
echo ""
echo "=== Setup Complete! ==="
echo "Load Balancer External IP: $EXTERNAL_IP"
echo "Access URL: http://${EXTERNAL_IP}"
echo ""
echo "You can now access your load balancer at the URL above."
echo "To destroy resources later, run: terraform destroy"