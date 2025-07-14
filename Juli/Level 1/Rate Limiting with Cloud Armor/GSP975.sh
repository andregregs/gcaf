#!/bin/bash

# Colors using tput (more reliable across different terminals)
if command -v tput > /dev/null 2>&1; then
    GREEN=$(tput setaf 2)
    BLUE=$(tput setaf 4)
    CYAN=$(tput setaf 6)
    YELLOW=$(tput setaf 3)
    RED=$(tput setaf 1)
    BOLD=$(tput bold)
    NC=$(tput sgr0)
else
    # Fallback - no colors
    GREEN=""
    BLUE=""
    CYAN=""
    YELLOW=""
    RED=""
    BOLD=""
    NC=""
fi

echo "${BLUE}=== Google Cloud HTTP Load Balancer Setup ===${NC}"
echo

# Get user input for regions and zones
echo "${CYAN}Please set the below values correctly${NC}"
read -p "${YELLOW}${BOLD}Enter the REGION1: ${NC}" REGION1
read -p "${YELLOW}${BOLD}Enter the REGION2: ${NC}" REGION2
read -p "${YELLOW}${BOLD}Enter the ZONE3: ${NC}" ZONE3

# Check authentication
echo
echo "${CYAN}Checking authentication...${NC}"
gcloud auth list

# Enable required services
echo
echo "${GREEN}Enabling OS Config API...${NC}"
gcloud services enable osconfig.googleapis.com

# Setup environment variables
echo
echo "${CYAN}Setting up environment variables...${NC}"
export REGION3="${ZONE3%-*}"
export PROJECT_ID=`gcloud config get-value project`
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

echo "Region 1: $REGION1"
echo "Region 2: $REGION2"
echo "Zone 3: $ZONE3"
echo "Region 3: $REGION3"
echo "Project ID: $PROJECT_ID"

# Create firewall rules
echo
echo "${GREEN}Creating firewall rules...${NC}"
gcloud compute --project=$PROJECT_ID firewall-rules create default-allow-http \
  --direction=INGRESS --priority=1000 --network=default --action=ALLOW \
  --rules=tcp:80 --source-ranges=0.0.0.0/0 --target-tags=http-server

gcloud compute --project=$PROJECT_ID firewall-rules create default-allow-health-check \
  --direction=INGRESS --priority=1000 --network=default --action=ALLOW \
  --rules=tcp:80 --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=http-server

# Create instance templates
echo
echo "${GREEN}Creating instance templates for both regions...${NC}"
echo "${YELLOW}Creating template for $REGION1...${NC}"
gcloud compute instance-templates create $REGION1-template \
  --project=$PROJECT_ID --machine-type=e2-medium \
  --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
  --metadata=startup-script-url=gs://cloud-training/gcpnet/httplb/startup.sh,enable-oslogin=true \
  --maintenance-policy=MIGRATE --provisioning-model=STANDARD \
  --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
  --region=$REGION1 --tags=http-server \
  --create-disk=auto-delete=yes,boot=yes,device-name=$REGION1-template,image=projects/debian-cloud/global/images/debian-12-bookworm-v20250311,mode=rw,size=10,type=pd-balanced \
  --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --reservation-affinity=any

echo "${YELLOW}Creating template for $REGION2...${NC}"
gcloud compute instance-templates create $REGION2-template \
  --project=$PROJECT_ID --machine-type=e2-medium \
  --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
  --metadata=startup-script-url=gs://cloud-training/gcpnet/httplb/startup.sh,enable-oslogin=true \
  --maintenance-policy=MIGRATE --provisioning-model=STANDARD \
  --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
  --region=$REGION2 --tags=http-server \
  --create-disk=auto-delete=yes,boot=yes,device-name=$REGION2-template,image=projects/debian-cloud/global/images/debian-12-bookworm-v20250311,mode=rw,size=10,type=pd-balanced \
  --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --reservation-affinity=any

# Create managed instance groups with autoscaling
echo
echo "${GREEN}Creating managed instance groups with autoscaling...${NC}"
echo "${YELLOW}Creating MIG for $REGION1...${NC}"
gcloud beta compute instance-groups managed create $REGION1-mig \
  --project=$PROJECT_ID --base-instance-name=$REGION1-mig \
  --template=projects/$PROJECT_ID/global/instanceTemplates/$REGION1-template \
  --size=1 --region=$REGION1 --target-distribution-shape=EVEN \
  --instance-redistribution-type=proactive --default-action-on-vm-failure=repair \
  --no-force-update-on-repair --standby-policy-mode=manual --list-managed-instances-results=pageless

gcloud beta compute instance-groups managed set-autoscaling $REGION1-mig \
  --project=$PROJECT_ID --region=$REGION1 --mode=on --min-num-replicas=1 --max-num-replicas=5 \
  --target-cpu-utilization=0.8 --cpu-utilization-predictive-method=none --cool-down-period=45

echo "${YELLOW}Creating MIG for $REGION2...${NC}"
gcloud beta compute instance-groups managed create $REGION2-mig \
  --project=$PROJECT_ID --base-instance-name=$REGION2-mig \
  --template=projects/$PROJECT_ID/global/instanceTemplates/$REGION2-template \
  --size=1 --region=$REGION2 --target-distribution-shape=EVEN \
  --instance-redistribution-type=proactive --default-action-on-vm-failure=repair \
  --no-force-update-on-repair --standby-policy-mode=manual --list-managed-instances-results=pageless

gcloud beta compute instance-groups managed set-autoscaling $REGION2-mig \
  --project=$PROJECT_ID --region=$REGION2 --mode=on --min-num-replicas=1 --max-num-replicas=5 \
  --target-cpu-utilization=0.8 --cpu-utilization-predictive-method=none --cool-down-period=45

# Setup API authentication for REST calls
echo
echo "${GREEN}Setting up API authentication...${NC}"
token=$(gcloud auth application-default print-access-token)
project_id=$(gcloud config get-value project)

# Create health check
echo
echo "${GREEN}Creating health check...${NC}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
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
  "https://compute.googleapis.com/compute/beta/projects/$project_id/global/healthChecks"

echo
echo "${YELLOW}Waiting for health check creation...${NC}"
sleep 30

# Create security policy
echo
echo "${GREEN}Creating default security policy...${NC}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "description": "Default security policy for: http-backend",
    "name": "default-security-policy-for-backend-service-http-backend",
    "rules": [
      {
        "action": "allow",
        "match": {"config": {"srcIpRanges": ["*"]}, "versionedExpr": "SRC_IPS_V1"},
        "priority": 2147483647
      },
      {
        "action": "throttle",
        "description": "Default rate limiting rule",
        "match": {"config": {"srcIpRanges": ["*"]}, "versionedExpr": "SRC_IPS_V1"},
        "priority": 2147483646,
        "rateLimitOptions": {"conformAction": "allow", "enforceOnKey": "IP", "exceedAction": "deny(403)", "rateLimitThreshold": {"count": 500, "intervalSec": 60}}
      }
    ]
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$project_id/global/securityPolicies"

echo
echo "${YELLOW}Waiting for security policy creation...${NC}"
sleep 30

# Create backend service
echo
echo "${GREEN}Creating backend service...${NC}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "backends": [
      {"balancingMode": "RATE", "capacityScaler": 1, "group": "projects/'"$project_id"'/regions/'"$REGION1"'/instanceGroups/'"$REGION1"'-mig", "maxRatePerInstance": 50},
      {"balancingMode": "UTILIZATION", "capacityScaler": 1, "group": "projects/'"$project_id"'/regions/'"$REGION2"'/instanceGroups/'"$REGION2"'-mig", "maxRatePerInstance": 100, "maxUtilization": 0.8}
    ],
    "enableCDN": true,
    "healthChecks": ["projects/'"$project_id"'/global/healthChecks/http-health-check"],
    "loadBalancingScheme": "EXTERNAL_MANAGED",
    "name": "http-backend",
    "portName": "http",
    "protocol": "HTTP",
    "securityPolicy": "projects/'"$project_id"'/global/securityPolicies/default-security-policy-for-backend-service-http-backend",
    "sessionAffinity": "NONE",
    "timeoutSec": 30
  }' \
  "https://compute.googleapis.com/compute/beta/projects/$project_id/global/backendServices"

echo
echo "${YELLOW}Waiting for backend service creation...${NC}"
sleep 60

# Create URL map
echo
echo "${GREEN}Creating URL map...${NC}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "defaultService": "projects/'"$project_id"'/global/backendServices/http-backend",
    "name": "http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$project_id/global/urlMaps"

echo
echo "${YELLOW}Waiting for URL map creation...${NC}"
sleep 30

# Create target HTTP proxies
echo
echo "${GREEN}Creating target HTTP proxies...${NC}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "name": "http-lb-target-proxy",
    "urlMap": "projects/'"$project_id"'/global/urlMaps/http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$project_id/global/targetHttpProxies"

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "name": "http-lb-target-proxy-2",
    "urlMap": "projects/'"$project_id"'/global/urlMaps/http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$project_id/global/targetHttpProxies"

echo
echo "${YELLOW}Waiting for target proxy creation...${NC}"
sleep 30

# Create forwarding rules
echo
echo "${GREEN}Creating forwarding rules (IPv4 and IPv6)...${NC}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "IPProtocol": "TCP",
    "ipVersion": "IPV4",
    "loadBalancingScheme": "EXTERNAL_MANAGED",
    "name": "http-lb-forwarding-rule",
    "networkTier": "PREMIUM",
    "portRange": "80",
    "target": "projects/'"$project_id"'/global/targetHttpProxies/http-lb-target-proxy"
  }' \
  "https://compute.googleapis.com/compute/beta/projects/$project_id/global/forwardingRules"

sleep 20

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "IPProtocol": "TCP",
    "ipVersion": "IPV6",
    "loadBalancingScheme": "EXTERNAL_MANAGED",
    "name": "http-lb-forwarding-rule-2",
    "networkTier": "PREMIUM",
    "portRange": "80",
    "target": "projects/'"$project_id"'/global/targetHttpProxies/http-lb-target-proxy-2"
  }' \
  "https://compute.googleapis.com/compute/beta/projects/$project_id/global/forwardingRules"

# Set named ports on instance groups
echo
echo "${GREEN}Setting named ports on instance groups...${NC}"
sleep 20

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{"namedPorts": [{"name": "http", "port": 80}]}' \
  "https://compute.googleapis.com/compute/beta/projects/$project_id/regions/$REGION1/instanceGroups/$REGION1-mig/setNamedPorts"

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{"namedPorts": [{"name": "http", "port": 80}]}' \
  "https://compute.googleapis.com/compute/beta/projects/$project_id/regions/$REGION2/instanceGroups/$REGION2-mig/setNamedPorts"

# Create siege VM for testing
echo
echo "${GREEN}Creating siege VM for load testing...${NC}"
gcloud compute instances create siege-vm \
  --project=$PROJECT_ID --zone=$ZONE3 --machine-type=e2-medium \
  --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
  --metadata=enable-osconfig=TRUE,enable-oslogin=true \
  --maintenance-policy=MIGRATE --provisioning-model=STANDARD \
  --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
  --create-disk=auto-delete=yes,boot=yes,device-name=siege-vm,image=projects/debian-cloud/global/images/debian-12-bookworm-v20250311,mode=rw,size=10,type=pd-balanced \
  --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring \
  --labels=goog-ops-agent-policy=v2-x86-template-1-4-0,goog-ec-src=vm_add-gcloud --reservation-affinity=any

# Setup ops agent and snapshot policy
echo
echo "${GREEN}Setting up ops agent and snapshot policy...${NC}"
printf 'agentsRule:\n  packageState: installed\n  version: latest\ninstanceFilter:\n  inclusionLabels:\n  - labels:\n      goog-ops-agent-policy: v2-x86-template-1-4-0\n' > config.yaml

gcloud compute instances ops-agents policies create goog-ops-agent-v2-x86-template-1-4-0-$ZONE3 \
  --project=$PROJECT_ID --zone=$ZONE3 --file=config.yaml

gcloud compute resource-policies create snapshot-schedule default-schedule-1 \
  --project=$PROJECT_ID --region=$REGION3 --max-retention-days=14 \
  --on-source-disk-delete=keep-auto-snapshots --daily-schedule --start-time=16:00

gcloud compute disks add-resource-policies siege-vm \
  --project=$PROJECT_ID --zone=$ZONE3 \
  --resource-policies=projects/$PROJECT_ID/regions/$REGION3/resourcePolicies/default-schedule-1

# Install siege tool
echo
echo "${GREEN}Installing siege tool on test VM...${NC}"
sleep 10 
gcloud compute ssh --zone "$ZONE3" "siege-vm" --project "$PROJECT_ID" \
  --command "sudo apt-get -y install siege" --quiet

# Create rate limiting security policy
echo
echo "${GREEN}Creating rate limiting security policy...${NC}"
gcloud compute security-policies create rate-limit-siege \
    --description "policy for rate limiting"

gcloud beta compute security-policies rules create 100 \
    --security-policy=rate-limit-siege \
    --expression="true" \
    --action=rate-based-ban \
    --rate-limit-threshold-count=50 \
    --rate-limit-threshold-interval-sec=120 \
    --ban-duration-sec=300 \
    --conform-action=allow \
    --exceed-action=deny-404 \
    --enforce-on-key=IP

# Apply rate limiting to backend service
echo
echo "${GREEN}Applying rate limiting to backend service...${NC}"
gcloud compute backend-services update http-backend \
    --security-policy rate-limit-siege --global

echo
echo "${GREEN}All operations completed successfully!${NC}"
echo "${BLUE}================================================================${NC}"
echo "${CYAN}HTTP Load Balancer Setup Summary:${NC}"
echo "${CYAN}• Regions: $REGION1, $REGION2${NC}"
echo "${CYAN}• Managed Instance Groups: Created with autoscaling${NC}"
echo "${CYAN}• Health Checks: HTTP health check configured${NC}"
echo "${CYAN}• Security Policies: Default + Rate limiting enabled${NC}"
echo "${CYAN}• Load Balancer: HTTP LB with IPv4 and IPv6 support${NC}"
echo "${CYAN}• Testing VM: siege-vm created in $ZONE3${NC}"
echo "${CYAN}• Rate Limiting: 50 requests per 120 seconds${NC}"
echo "${CYAN}• CDN: Enabled on backend service${NC}"
echo "${BLUE}================================================================${NC}"