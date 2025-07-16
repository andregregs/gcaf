#!/bin/bash

# Colors for output
YELLOW=$(tput setaf 3)
BOLD=$(tput bold)
GREEN=$(tput setaf 2)
RESET=$(tput sgr0)

# Get user input
echo "${YELLOW}${BOLD}=== GCP Load Balancer Setup ===${RESET}"
echo "Please enter the required values:"
read -p "${YELLOW}${BOLD}Enter REGION1: ${RESET}" REGION1
read -p "${YELLOW}${BOLD}Enter REGION2: ${RESET}" REGION2
read -p "${YELLOW}${BOLD}Enter VM_ZONE: ${RESET}" VM_ZONE

# Export variables
export REGION1 REGION2 VM_ZONE
export DEVSHELL_PROJECT_ID=$(gcloud config get-value project)
export TOKEN=$(gcloud auth application-default print-access-token)

echo "${GREEN}Starting setup with:"
echo "- Region 1: $REGION1"
echo "- Region 2: $REGION2" 
echo "- VM Zone: $VM_ZONE"
echo "- Project: $DEVSHELL_PROJECT_ID${RESET}"

# 1. Create Firewall Rules
echo "${GREEN}Creating firewall rules...${RESET}"
gcloud compute firewall-rules create default-allow-http \
  --project=$DEVSHELL_PROJECT_ID \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --source-ranges=0.0.0.0/0 \
  --target-tags=http-server \
  --action=ALLOW \
  --rules=tcp:80

gcloud compute firewall-rules create default-allow-health-check \
  --project=$DEVSHELL_PROJECT_ID \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=http-server \
  --action=ALLOW \
  --rules=tcp

# 2. Create Instance Templates
echo "${GREEN}Creating instance templates...${RESET}"
create_template() {
  local region=$1
  gcloud compute instance-templates create $region-template \
    --project=$DEVSHELL_PROJECT_ID \
    --machine-type=e2-micro \
    --network-interface=network-tier=PREMIUM,subnet=default \
    --metadata=startup-script-url=gs://cloud-training/gcpnet/httplb/startup.sh,enable-oslogin=true \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --region=$region \
    --tags=http-server,https-server \
    --create-disk=auto-delete=yes,boot=yes,device-name=$region-template,image=projects/debian-cloud/global/images/debian-11-bullseye-v20230629,mode=rw,size=10,type=pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --reservation-affinity=any
}

create_template $REGION1
create_template $REGION2

# 3. Create Managed Instance Groups with Autoscaling
echo "${GREEN}Creating managed instance groups...${RESET}"
create_mig() {
  local region=$1
  gcloud beta compute instance-groups managed create $region-mig \
    --project=$DEVSHELL_PROJECT_ID \
    --base-instance-name=$region-mig \
    --size=1 \
    --template=$region-template \
    --region=$region \
    --target-distribution-shape=EVEN \
    --instance-redistribution-type=PROACTIVE \
    --list-managed-instances-results=PAGELESS \
    --no-force-update-on-repair

  gcloud beta compute instance-groups managed set-autoscaling $region-mig \
    --project=$DEVSHELL_PROJECT_ID \
    --region=$region \
    --cool-down-period=45 \
    --max-num-replicas=2 \
    --min-num-replicas=1 \
    --mode=on \
    --target-cpu-utilization=0.8
}

create_mig $REGION1
create_mig $REGION2

# 4. Create Health Check
echo "${GREEN}Creating health check...${RESET}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "checkIntervalSec": 5,
    "description": "",
    "healthyThreshold": 2,
    "logConfig": {"enable": false},
    "name": "http-health-check",
    "tcpHealthCheck": {"port": 80, "proxyHeader": "NONE"},
    "timeoutSec": 5,
    "type": "TCP",
    "unhealthyThreshold": 2
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/healthChecks"

sleep 30

# 5. Create Backend Service
echo "${GREEN}Creating backend service...${RESET}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "backends": [
      {
        "balancingMode": "RATE",
        "capacityScaler": 1,
        "group": "projects/'"$DEVSHELL_PROJECT_ID"'/regions/'"$REGION1"'/instanceGroups/'"$REGION1-mig"'",
        "maxRatePerInstance": 50
      },
      {
        "balancingMode": "UTILIZATION", 
        "capacityScaler": 1,
        "group": "projects/'"$DEVSHELL_PROJECT_ID"'/regions/'"$REGION2"'/instanceGroups/'"$REGION2-mig"'",
        "maxRatePerInstance": 80,
        "maxUtilization": 0.8
      }
    ],
    "cdnPolicy": {
      "cacheKeyPolicy": {"includeHost": true, "includeProtocol": true, "includeQueryString": true},
      "cacheMode": "CACHE_ALL_STATIC",
      "clientTtl": 3600,
      "defaultTtl": 3600,
      "maxTtl": 86400,
      "negativeCaching": false,
      "serveWhileStale": 0
    },
    "compressionMode": "DISABLED",
    "connectionDraining": {"drainingTimeoutSec": 300},
    "enableCDN": true,
    "healthChecks": ["projects/'"$DEVSHELL_PROJECT_ID"'/global/healthChecks/http-health-check"],
    "loadBalancingScheme": "EXTERNAL",
    "logConfig": {"enable": true, "sampleRate": 1},
    "name": "http-backend"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/backendServices"

sleep 60

# 6. Create URL Map
echo "${GREEN}Creating URL map...${RESET}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "defaultService": "projects/'"$DEVSHELL_PROJECT_ID"'/global/backendServices/http-backend",
    "name": "http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/urlMaps"

sleep 30

# 7. Create Target HTTP Proxies (IPv4 and IPv6)
echo "${GREEN}Creating target proxies...${RESET}"
create_proxy() {
  local name=$1
  curl -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
      "name": "'"$name"'",
      "urlMap": "projects/'"$DEVSHELL_PROJECT_ID"'/global/urlMaps/http-lb"
    }' \
    "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/targetHttpProxies"
  sleep 30
}

create_proxy "http-lb-target-proxy"
create_proxy "http-lb-target-proxy-2"

# 8. Create Forwarding Rules (IPv4 and IPv6)
echo "${GREEN}Creating forwarding rules...${RESET}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "IPProtocol": "TCP",
    "ipVersion": "IPV4",
    "loadBalancingScheme": "EXTERNAL",
    "name": "http-lb-forwarding-rule",
    "networkTier": "PREMIUM",
    "portRange": "80",
    "target": "projects/'"$DEVSHELL_PROJECT_ID"'/global/targetHttpProxies/http-lb-target-proxy"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/forwardingRules"

sleep 30

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "IPProtocol": "TCP",
    "ipVersion": "IPV6",
    "loadBalancingScheme": "EXTERNAL", 
    "name": "http-lb-forwarding-rule-2",
    "networkTier": "PREMIUM",
    "portRange": "80",
    "target": "projects/'"$DEVSHELL_PROJECT_ID"'/global/targetHttpProxies/http-lb-target-proxy-2"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/forwardingRules"

# 9. Set Named Ports for Instance Groups
echo "${GREEN}Setting named ports...${RESET}"
set_named_ports() {
  local region=$1
  local group_name="$region-mig"
  curl -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"namedPorts": [{"name": "http", "port": 80}]}' \
    "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/regions/$region/instanceGroups/$group_name/setNamedPorts"
  sleep 30
}

set_named_ports $REGION1
set_named_ports $REGION2

# 10. Create Siege VM for Load Testing
echo "${GREEN}Creating siege VM...${RESET}"
gcloud compute instances create siege-vm \
  --project=$DEVSHELL_PROJECT_ID \
  --zone=$VM_ZONE \
  --machine-type=e2-medium \
  --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
  --metadata=enable-oslogin=true \
  --maintenance-policy=MIGRATE \
  --provisioning-model=STANDARD \
  --create-disk=auto-delete=yes,boot=yes,device-name=siege-vm,image=projects/debian-cloud/global/images/debian-11-bullseye-v20230629,mode=rw,size=10,type=projects/$DEVSHELL_PROJECT_ID/zones/$VM_ZONE/diskTypes/pd-balanced \
  --no-shielded-secure-boot \
  --shielded-vtpm \
  --shielded-integrity-monitoring \
  --reservation-affinity=any

sleep 60

# 11. Setup Cloud Armor Security Policy
echo "${GREEN}Setting up Cloud Armor...${RESET}"
export EXTERNAL_IP=$(gcloud compute instances describe siege-vm --zone=$VM_ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

curl -X POST -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "denylist-siege",
    "rules": [
      {
        "action": "deny(403)",
        "match": {
          "config": {"srcIpRanges": ["'"${EXTERNAL_IP}"'"]},
          "versionedExpr": "SRC_IPS_V1"
        },
        "priority": 1000
      },
      {
        "action": "allow",
        "match": {
          "config": {"srcIpRanges": ["*"]},
          "versionedExpr": "SRC_IPS_V1"
        },
        "priority": 2147483647
      }
    ],
    "type": "CLOUD_ARMOR"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/securityPolicies"

sleep 30

# Apply security policy to backend service
curl -X POST -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{"securityPolicy": "projects/'"$DEVSHELL_PROJECT_ID"'/global/securityPolicies/denylist-siege"}' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/backendServices/http-backend/setSecurityPolicy"

# 12. Run Load Test
echo "${GREEN}Running load test...${RESET}"
LB_IP_ADDRESS=$(gcloud compute forwarding-rules describe http-lb-forwarding-rule --global --format="value(IPAddress)")

gcloud compute ssh --zone "$VM_ZONE" "siege-vm" --project "$DEVSHELL_PROJECT_ID" --quiet \
  --command "sudo apt-get -y install siege && export LB_IP=$LB_IP_ADDRESS && siege -c 150 -t 120s http://\$LB_IP"

echo "${GREEN}${BOLD}Setup completed successfully!${RESET}"
echo "Load Balancer IP: $LB_IP_ADDRESS"