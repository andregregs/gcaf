#!/bin/bash

# Colors using tput (reliable across different terminals)
YELLOW=$(tput setaf 3)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
RED=$(tput setaf 1)
BOLD=$(tput bold)
RESET=$(tput sgr0)

echo "${BLUE}=== Google Cloud Load Balancer with Cloud Armor Setup ===${RESET}"
echo

# Get user input
echo "Please set the below values correctly"
read -p "${YELLOW}${BOLD}Enter the REGION1: ${RESET}" REGION1
read -p "${YELLOW}${BOLD}Enter the REGION2: ${RESET}" REGION2
read -p "${YELLOW}${BOLD}Enter the VM_ZONE: ${RESET}" VM_ZONE

# Export variables after collecting input
export REGION1 REGION2 VM_ZONE

echo
echo "${CYAN}Configuration:${RESET}"
echo "Region 1: $REGION1"
echo "Region 2: $REGION2"
echo "VM Zone: $VM_ZONE"

# Create firewall rules
echo
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
  --rules=tcp:80

# Create instance templates
echo
echo "${GREEN}Creating instance templates...${RESET}"
echo "${YELLOW}Creating template for $REGION1...${RESET}"
gcloud compute instance-templates create $REGION1-template \
  --project=$DEVSHELL_PROJECT_ID \
  --machine-type=e2-micro \
  --network-interface=network-tier=PREMIUM,subnet=default \
  --metadata=startup-script-url=gs://cloud-training/gcpnet/httplb/startup.sh,enable-oslogin=true \
  --maintenance-policy=MIGRATE \
  --provisioning-model=STANDARD \
  --region=$REGION1 \
  --tags=http-server,https-server \
  --create-disk=auto-delete=yes,boot=yes,device-name=$REGION1-template,image=projects/debian-cloud/global/images/debian-11-bullseye-v20230629,mode=rw,size=10,type=pd-balanced \
  --no-shielded-secure-boot \
  --shielded-vtpm \
  --shielded-integrity-monitoring \
  --reservation-affinity=any

echo "${YELLOW}Creating template for $REGION2...${RESET}"
gcloud compute instance-templates create $REGION2-template \
  --project=$DEVSHELL_PROJECT_ID \
  --machine-type=e2-micro \
  --network-interface=network-tier=PREMIUM,subnet=default \
  --metadata=startup-script-url=gs://cloud-training/gcpnet/httplb/startup.sh,enable-oslogin=true \
  --maintenance-policy=MIGRATE \
  --provisioning-model=STANDARD \
  --region=$REGION2 \
  --tags=http-server,https-server \
  --create-disk=auto-delete=yes,boot=yes,device-name=$REGION2-template,image=projects/debian-cloud/global/images/debian-11-bullseye-v20230629,mode=rw,size=10,type=pd-balanced \
  --no-shielded-secure-boot \
  --shielded-vtpm \
  --shielded-integrity-monitoring \
  --reservation-affinity=any

# Create managed instance groups
echo
echo "${GREEN}Creating managed instance groups with autoscaling...${RESET}"
echo "${YELLOW}Creating MIG for $REGION1...${RESET}"
gcloud beta compute instance-groups managed create $REGION1-mig \
  --project=$DEVSHELL_PROJECT_ID \
  --base-instance-name=$REGION1-mig \
  --size=1 \
  --template=$REGION1-template \
  --region=$REGION1 \
  --target-distribution-shape=EVEN \
  --instance-redistribution-type=PROACTIVE \
  --list-managed-instances-results=PAGELESS \
  --no-force-update-on-repair

gcloud beta compute instance-groups managed set-autoscaling $REGION1-mig \
  --project=$DEVSHELL_PROJECT_ID \
  --region=$REGION1 \
  --cool-down-period=45 \
  --max-num-replicas=2 \
  --min-num-replicas=1 \
  --mode=on \
  --target-cpu-utilization=0.8

echo "${YELLOW}Creating MIG for $REGION2...${RESET}"
gcloud beta compute instance-groups managed create $REGION2-mig \
  --project=$DEVSHELL_PROJECT_ID \
  --base-instance-name=$REGION2-mig \
  --size=1 \
  --template=$REGION2-template \
  --region=$REGION2 \
  --target-distribution-shape=EVEN \
  --instance-redistribution-type=PROACTIVE \
  --list-managed-instances-results=PAGELESS \
  --no-force-update-on-repair

gcloud beta compute instance-groups managed set-autoscaling $REGION2-mig \
  --project=$DEVSHELL_PROJECT_ID \
  --region=$REGION2 \
  --cool-down-period=45 \
  --max-num-replicas=2 \
  --min-num-replicas=1 \
  --mode=on \
  --target-cpu-utilization=0.8

# Setup API authentication
echo
echo "${GREEN}Setting up API authentication...${RESET}"
DEVSHELL_PROJECT_ID=$(gcloud config get-value project)
TOKEN=$(gcloud auth application-default print-access-token)

# Create health check
echo
echo "${GREEN}Creating health check...${RESET}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "checkIntervalSec": 5,
    "description": "",
    "healthyThreshold": 2,
    "logConfig": {
      "enable": false
    },
    "name": "http-health-check",
    "tcpHealthCheck": {
      "port": 80,
      "proxyHeader": "NONE"
    },
    "timeoutSec": 5,
    "type": "TCP",
    "unhealthyThreshold": 2
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/healthChecks"

echo
echo "${YELLOW}Waiting for health check creation...${RESET}"
sleep 30

# Create backend service
echo
echo "${GREEN}Creating backend service with CDN...${RESET}"
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
      "cacheKeyPolicy": {
        "includeHost": true,
        "includeProtocol": true,
        "includeQueryString": true
      },
      "cacheMode": "CACHE_ALL_STATIC",
      "clientTtl": 3600,
      "defaultTtl": 3600,
      "maxTtl": 86400,
      "negativeCaching": false,
      "serveWhileStale": 0
    },
    "compressionMode": "DISABLED",
    "connectionDraining": {
      "drainingTimeoutSec": 300
    },
    "description": "",
    "enableCDN": true,
    "healthChecks": [
      "projects/'"$DEVSHELL_PROJECT_ID"'/global/healthChecks/http-health-check"
    ],
    "loadBalancingScheme": "EXTERNAL",
    "logConfig": {
      "enable": true,
      "sampleRate": 1
    },
    "name": "http-backend"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/backendServices"

echo
echo "${YELLOW}Waiting for backend service creation...${RESET}"
sleep 60

# Create URL map
echo
echo "${GREEN}Creating URL map...${RESET}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "defaultService": "projects/'"$DEVSHELL_PROJECT_ID"'/global/backendServices/http-backend",
    "name": "http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/urlMaps"

echo
echo "${YELLOW}Waiting for URL map creation...${RESET}"
sleep 30

# Create target HTTP proxies
echo
echo "${GREEN}Creating target HTTP proxies...${RESET}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "http-lb-target-proxy",
    "urlMap": "projects/'"$DEVSHELL_PROJECT_ID"'/global/urlMaps/http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/targetHttpProxies"

sleep 30

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "http-lb-target-proxy-2",
    "urlMap": "projects/'"$DEVSHELL_PROJECT_ID"'/global/urlMaps/http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/targetHttpProxies"

# Create forwarding rules
echo
echo "${GREEN}Creating forwarding rules (IPv4 and IPv6)...${RESET}"
sleep 30

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

# Set named ports on instance groups
echo
echo "${GREEN}Setting named ports on instance groups...${RESET}"
sleep 30

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "namedPorts": [
      {
        "name": "http",
        "port": 80
      }
    ]
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/regions/$REGION1/instanceGroups/$REGION1-mig/setNamedPorts"

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "namedPorts": [
      {
        "name": "http",
        "port": 80
      }
    ]
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/regions/$REGION2/instanceGroups/$REGION2-mig/setNamedPorts"

# Create siege VM for testing
echo
echo "${GREEN}Creating siege VM for load testing...${RESET}"
gcloud compute instances create siege-vm \
  --project=$DEVSHELL_PROJECT_ID \
  --zone=$VM_ZONE \
  --machine-type=e2-medium \
  --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
  --metadata=enable-oslogin=true \
  --maintenance-policy=MIGRATE \
  --provisioning-model=STANDARD \
  --create-disk=auto-delete=yes,boot=yes,device-name=siege-vm,image=projects/debian-cloud/global/images/debian-11-bullseye-v20230629,mode=rw,size=10,type=pd-balanced \
  --no-shielded-secure-boot \
  --shielded-vtpm \
  --shielded-integrity-monitoring \
  --labels=goog-ec-src=vm_add-gcloud \
  --reservation-affinity=any

echo
echo "${YELLOW}Waiting for siege VM to be ready...${RESET}"
sleep 60

# Get siege VM external IP
echo
echo "${GREEN}Getting siege VM external IP...${RESET}"
export EXTERNAL_IP=$(gcloud compute instances describe siege-vm --zone=$VM_ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
echo "Siege VM IP: $EXTERNAL_IP"

# Create Cloud Armor denylist security policy
echo
echo "${GREEN}Creating Cloud Armor denylist security policy...${RESET}"
sleep 30

curl -X POST -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "Content-Type: application/json" \
  -d '{
    "adaptiveProtectionConfig": {
      "layer7DdosDefenseConfig": {
        "enable": false
      }
    },
    "description": "Security policy to deny specific IP addresses",
    "name": "denylist-siege",
    "rules": [
      {
        "action": "deny(403)",
        "description": "Deny siege VM IP",
        "match": {
          "config": {
            "srcIpRanges": [
               "'"${EXTERNAL_IP}"'/32"
            ]
          },
          "versionedExpr": "SRC_IPS_V1"
        },
        "preview": false,
        "priority": 1000
      },
      {
        "action": "allow",
        "description": "Default rule, higher priority overrides it",
        "match": {
          "config": {
            "srcIpRanges": [
              "*"
            ]
          },
          "versionedExpr": "SRC_IPS_V1"
        },
        "preview": false,
        "priority": 2147483647
      }
    ],
    "type": "CLOUD_ARMOR"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/securityPolicies"

# Apply security policy to backend service
echo
echo "${GREEN}Applying security policy to backend service...${RESET}"
sleep 30

curl -X POST -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "Content-Type: application/json" \
  -d "{
    \"securityPolicy\": \"projects/$DEVSHELL_PROJECT_ID/global/securityPolicies/denylist-siege\"
  }" \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/backendServices/http-backend/setSecurityPolicy"

# Get load balancer IP
echo
echo "${GREEN}Getting load balancer IP address...${RESET}"
LB_IP_ADDRESS=$(gcloud compute forwarding-rules describe http-lb-forwarding-rule --global --format="value(IPAddress)")
echo "Load Balancer IP: $LB_IP_ADDRESS"

# Test load balancer (will be blocked by Cloud Armor)
echo
echo "${RED}Testing load balancer (should be blocked by Cloud Armor)...${RESET}"
echo "${YELLOW}Note: This test will fail because siege VM IP is blocked by Cloud Armor${RESET}"
gcloud compute ssh --zone "$VM_ZONE" "siege-vm" --project "$DEVSHELL_PROJECT_ID" --quiet --command "sudo apt-get -y install siege && export LB_IP=$LB_IP_ADDRESS && siege -c 10 -t 30s http://\$LB_IP"

echo
echo "${GREEN}All operations completed successfully!${RESET}"
echo "${BLUE}================================================================${RESET}"
echo "${CYAN}Load Balancer with Cloud Armor Setup Summary:${RESET}"
echo "${CYAN}• Regions: $REGION1, $REGION2${RESET}"
echo "${CYAN}• Managed Instance Groups: Created with autoscaling${RESET}"
echo "${CYAN}• Health Check: HTTP health check configured${RESET}"
echo "${CYAN}• Backend Service: Created with CDN enabled${RESET}"
echo "${CYAN}• Load Balancer: HTTP LB with IPv4 and IPv6 support${RESET}"
echo "${CYAN}• Cloud Armor: Denylist policy applied${RESET}"
echo "${CYAN}• Siege VM: Created and blocked by security policy${RESET}"
echo "${CYAN}• Load Balancer IP: $LB_IP_ADDRESS${RESET}"
echo "${CYAN}• Blocked IP: $EXTERNAL_IP${RESET}"
echo "${BLUE}================================================================${RESET}"