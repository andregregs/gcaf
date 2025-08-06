#!/bin/bash

# =========================================================
# Google Cloud VM Machine Type Resize Script
# =========================================================
# Deskripsi: Script untuk mengubah machine type dari
# VM instance dengan cara stop, resize, dan start kembali
# =========================================================

set -e  # Keluar jika ada error

# Konfigurasi
VM_NAME="lab-vm"
NEW_MACHINE_TYPE="e2-medium"
STOP_WAIT_TIME=10
START_WAIT_TIME=10

echo "=== Google Cloud VM Machine Type Resize ==="
echo "VM Name: $VM_NAME"
echo "New Machine Type: $NEW_MACHINE_TYPE"
echo ""

# 1. Autentikasi dan validasi akun Google Cloud
echo "Step 1: Authenticating Google Cloud account..."
gcloud auth list
echo ""

# 2. Mengatur variabel environment
echo "Step 2: Setting up environment variables..."
export ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export PROJECT_ID=$(gcloud config get-value project)

# Validasi zone default
if [ -z "$ZONE" ]; then
  echo "Warning: No default zone found, using us-central1-a"
  export ZONE="us-central1-a"
fi

echo "Using Zone: $ZONE"
echo "Using Project ID: $PROJECT_ID"
gcloud config set compute/zone "$ZONE"
echo ""

# 3. Validasi keberadaan VM
echo "Step 3: Validating VM existence..."
if ! gcloud compute instances describe "$VM_NAME" --zone="$ZONE" &>/dev/null; then
  echo "ERROR: VM '$VM_NAME' not found in zone '$ZONE'"
  echo "Available instances:"
  gcloud compute instances list --format="table(name,zone,status,machineType.basename())"
  exit 1
fi

# Menampilkan informasi VM saat ini
echo "Current VM information:"
CURRENT_STATUS=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" --format="value(status)")
CURRENT_MACHINE_TYPE=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" --format="value(machineType.basename())")

echo "- Status: $CURRENT_STATUS"
echo "- Current Machine Type: $CURRENT_MACHINE_TYPE"
echo ""

# 4. Cek apakah machine type sudah sesuai
if [ "$CURRENT_MACHINE_TYPE" = "$NEW_MACHINE_TYPE" ]; then
  echo "VM already has machine type '$NEW_MACHINE_TYPE'. No changes needed."
  exit 0
fi

# 5. Stopping VM instance
echo "Step 4: Stopping VM instance '$VM_NAME'..."
if [ "$CURRENT_STATUS" = "RUNNING" ]; then
  echo "Stopping VM..."
  gcloud compute instances stop "$VM_NAME" --zone="$ZONE" --quiet
  
  # Wait dengan progress indicator
  echo "Waiting for VM to stop completely..."
  for i in $(seq 1 $STOP_WAIT_TIME); do
    printf "."
    sleep 1
  done
  echo ""
  
  # Verifikasi status stopped
  NEW_STATUS=$(gcloud compute instances describe "$VM_NAME" \
    --zone="$ZONE" --format="value(status)")
  echo "VM Status after stop: $NEW_STATUS"
  
  if [ "$NEW_STATUS" != "TERMINATED" ]; then
    echo "Warning: VM may still be stopping. Waiting additional time..."
    sleep 5
  fi
else
  echo "VM is already stopped (Status: $CURRENT_STATUS)"
fi
echo ""

# 6. Mengubah machine type
echo "Step 5: Changing machine type from '$CURRENT_MACHINE_TYPE' to '$NEW_MACHINE_TYPE'..."
gcloud compute instances set-machine-type "$VM_NAME" \
  --machine-type="$NEW_MACHINE_TYPE" \
  --zone="$ZONE"

echo "Machine type changed successfully!"

# Wait sebelum start
echo "Waiting before starting VM..."
for i in $(seq 1 $START_WAIT_TIME); do
  printf "."
  sleep 1
done
echo ""

# 7. Starting VM instance
echo "Step 6: Starting VM instance '$VM_NAME'..."
gcloud compute instances start "$VM_NAME" --zone="$ZONE" --quiet

echo "VM start command issued. Waiting for VM to boot..."
sleep 5
echo ""

# 8. Verifikasi hasil akhir
echo "Step 7: Verifying final configuration..."
FINAL_STATUS=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" --format="value(status)")
FINAL_MACHINE_TYPE=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" --format="value(machineType.basename())")

echo "=== Resize Operation Complete ==="
echo "VM Name: $VM_NAME"
echo "Zone: $ZONE"
echo "Status: $FINAL_STATUS"
echo "Machine Type: $CURRENT_MACHINE_TYPE → $FINAL_MACHINE_TYPE"
echo ""

if [ "$FINAL_MACHINE_TYPE" = "$NEW_MACHINE_TYPE" ]; then
  echo "✅ SUCCESS: Machine type successfully changed to $NEW_MACHINE_TYPE"
else
  echo "❌ ERROR: Machine type change may have failed"
  echo "Expected: $NEW_MACHINE_TYPE"
  echo "Actual: $FINAL_MACHINE_TYPE"
  exit 1
fi

# 9. Menampilkan informasi koneksi
echo ""
echo "=== Connection Information ==="
if [ "$FINAL_STATUS" = "RUNNING" ]; then
  echo "VM is running and ready for use."
  echo "To connect via SSH, run:"
  echo "gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT_ID"
else
  echo "VM Status: $FINAL_STATUS"
  echo "VM may still be starting up. Please check status in a few moments."
fi

echo ""
echo "=== Resource Information ==="
echo "To view detailed VM information:"
echo "gcloud compute instances describe $VM_NAME --zone=$ZONE"
echo ""
echo "To view all instances:"
echo "gcloud compute instances list"