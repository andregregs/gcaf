#!/bin/bash

# =====================================================
# Google Cloud Load Balancer with reCAPTCHA Setup
# Complete Infrastructure and Security Configuration
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting Google Cloud Load Balancer with reCAPTCHA setup...${RESET}"

# =====================================================
# 1. PROJECT SETUP & SERVICES
# =====================================================
echo -e "${YELLOW}Step 1: Setting up project and enabling services...${RESET}"

export PROJECT_ID=$(gcloud config get-value project)
gcloud config set project $PROJECT_ID

export REGION="${ZONE%-*}"

gcloud services enable \
  compute.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  recaptchaenterprise.googleapis.com

echo -e "${GREEN}✅ Project setup complete: $PROJECT_ID | $REGION${RESET}"

# =====================================================
# 2. FIREWALL RULES
# =====================================================
echo -e "${YELLOW}Step 2: Creating firewall rules...${RESET}"

gcloud compute firewall-rules create default-allow-health-check \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=allow-health-check

gcloud compute firewall-rules create allow-ssh \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=allow-health-check

echo -e "${GREEN}✅ Firewall rules created${RESET}"

# =====================================================
# 3. INSTANCE TEMPLATE
# =====================================================
echo -e "${YELLOW}Step 3: Creating instance template...${RESET}"

gcloud compute instance-templates create lb-backend-template \
    --machine-type=n1-standard-1 \
    --region=$REGION \
    --network=default \
    --subnet=default \
    --tags=allow-health-check \
    --metadata=startup-script='#! /bin/bash
sudo apt-get update
sudo apt-get install apache2 -y
sudo a2ensite default-ssl
sudo a2enmod ssl
sudo su
vm_hostname="$(curl -H "Metadata-Flavor:Google" http://metadata.google.internal/computeMetadata/v1/instance/name)"
echo "Page served from: $vm_hostname" | tee /var/www/html/index.html'

echo -e "${GREEN}✅ Instance template created${RESET}"

# =====================================================
# 4. MANAGED INSTANCE GROUP
# =====================================================
echo -e "${YELLOW}Step 4: Creating managed instance group...${RESET}"

sleep 40

gcloud beta compute instance-groups managed create lb-backend-example \
  --project=$PROJECT_ID \
  --base-instance-name=lb-backend-example \
  --template=projects/$PROJECT_ID/global/instanceTemplates/lb-backend-template \
  --size=1 \
  --zone=$ZONE \
  --default-action-on-vm-failure=repair \
  --no-force-update-on-repair \
  --standby-policy-mode=manual \
  --list-managed-instances-results=PAGELESS

gcloud beta compute instance-groups managed set-autoscaling lb-backend-example \
  --project=$PROJECT_ID \
  --zone=$ZONE \
  --mode=off \
  --min-num-replicas=1 \
  --max-num-replicas=10 \
  --target-cpu-utilization=0.6 \
  --cool-down-period=60

gcloud compute instance-groups set-named-ports lb-backend-example \
  --named-ports http:80 \
  --zone $ZONE

echo -e "${GREEN}✅ Managed instance group created${RESET}"

# =====================================================
# 5. LOAD BALANCER COMPONENTS (API CALLS)
# =====================================================
echo -e "${YELLOW}Step 5: Creating load balancer components...${RESET}"

DEVSHELL_PROJECT_ID=$(gcloud config get-value project)
TOKEN=$(gcloud auth application-default print-access-token)

# Health Check
echo -e "${CYAN}Creating health check...${RESET}"
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
  "https://compute.googleapis.com/compute/beta/projects/$DEVSHELL_PROJECT_ID/global/healthChecks"

sleep 30

# Security Policy
echo -e "${CYAN}Creating security policy...${RESET}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "description": "Default security policy for: http-backend",
    "name": "default-security-policy-for-backend-service-http-backend",
    "rules": [
      {
        "action": "allow",
        "match": {
          "config": {
            "srcIpRanges": [
              "*"
            ]
          },
          "versionedExpr": "SRC_IPS_V1"
        },
        "priority": 2147483647
      },
      {
        "action": "throttle",
        "description": "Default rate limiting rule",
        "match": {
          "config": {
            "srcIpRanges": [
              "*"
            ]
          },
          "versionedExpr": "SRC_IPS_V1"
        },
        "priority": 2147483646,
        "rateLimitOptions": {
          "conformAction": "allow",
          "enforceOnKey": "IP",
          "exceedAction": "deny(403)",
          "rateLimitThreshold": {
            "count": 500,
            "intervalSec": 60
          }
        }
      }
    ]
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/securityPolicies"

sleep 30

# Backend Service
echo -e "${CYAN}Creating backend service...${RESET}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "backends": [
      {
        "balancingMode": "UTILIZATION",
        "capacityScaler": 1,
        "group": "projects/'"$DEVSHELL_PROJECT_ID"'/zones/'"$ZONE"'/instanceGroups/lb-backend-example",
        "maxUtilization": 0.8
      }
    ],
    "cdnPolicy": {
      "cacheKeyPolicy": {
        "includeHost": true,
        "includeProtocol": true,
        "includeQueryString": true
      },
      "cacheMode": "USE_ORIGIN_HEADERS",
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
    "loadBalancingScheme": "EXTERNAL_MANAGED",
    "localityLbPolicy": "ROUND_ROBIN",
    "logConfig": {
      "enable": true,
      "sampleRate": 1
    },
    "name": "http-backend",
    "portName": "http",
    "protocol": "HTTP",
    "securityPolicy": "projects/'"$DEVSHELL_PROJECT_ID"'/global/securityPolicies/default-security-policy-for-backend-service-http-backend",
    "sessionAffinity": "NONE",
    "timeoutSec": 30
  }' \
  "https://compute.googleapis.com/compute/beta/projects/$DEVSHELL_PROJECT_ID/global/backendServices"

sleep 30

# Set Security Policy
echo -e "${CYAN}Setting security policy...${RESET}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "securityPolicy": "projects/'"$DEVSHELL_PROJECT_ID"'/global/securityPolicies/default-security-policy-for-backend-service-http-backend"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/backendServices/http-backend/setSecurityPolicy"

sleep 30

# URL Map
echo -e "${CYAN}Creating URL map...${RESET}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "defaultService": "projects/'"$DEVSHELL_PROJECT_ID"'/global/backendServices/http-backend",
    "name": "http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/urlMaps"

sleep 30

# Target HTTP Proxy
echo -e "${CYAN}Creating target HTTP proxy...${RESET}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "http-lb-target-proxy",
    "urlMap": "projects/'"$DEVSHELL_PROJECT_ID"'/global/urlMaps/http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/targetHttpProxies"

sleep 30

# Forwarding Rule
echo -e "${CYAN}Creating forwarding rule...${RESET}"
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "IPProtocol": "TCP",
    "ipVersion": "IPV4",
    "loadBalancingScheme": "EXTERNAL_MANAGED",
    "name": "http-lb-forwarding-rule",
    "networkTier": "PREMIUM",
    "portRange": "80",
    "target": "projects/'"$DEVSHELL_PROJECT_ID"'/global/targetHttpProxies/http-lb-target-proxy"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/forwardingRules"

sleep 30

echo -e "${GREEN}✅ Load balancer components created${RESET}"

# =====================================================
# 6. RECAPTCHA KEYS SETUP
# =====================================================
echo -e "${YELLOW}Step 6: Setting up reCAPTCHA keys...${RESET}"

TOKEN_KEY=$(gcloud recaptcha keys create --display-name=test-key-name \
  --web --allow-all-domains --integration-type=score --testing-score=0.5 \
  --waf-feature=session-token --waf-service=ca --format="value(name)")

TOKEN_KEY=$(echo "$TOKEN_KEY" | awk -F '/' '{print $NF}')

RECAPTCHA_KEY=$(gcloud recaptcha keys create --display-name=challenge-page-key \
--web --allow-all-domains --integration-type=INVISIBLE \
--waf-feature=challenge-page --waf-service=ca --format="value(name)")

RECAPTCHA_KEY=$(echo "$RECAPTCHA_KEY" | awk -F '/' '{print $NF}')

echo -e "${GREEN}✅ reCAPTCHA keys created${RESET}"

# =====================================================
# 7. DEPLOY HTML FILES TO VM
# =====================================================
echo -e "${YELLOW}Step 7: Deploying HTML files to VM...${RESET}"

INSTANCE_NAME=$(gcloud compute instances list --format="value(name)" \
  --filter="name~^lb-backend-example" | head -n 1)

cat > prepare_disk.sh <<'EOF_END'
export TOKEN_KEY="$TOKEN_KEY"

cd /var/www/html/

sudo tee index.html > /dev/null <<HTML_CONTENT
<!doctype html>
<html>
<head>
  <title>ReCAPTCHA Session Token</title>
  <script src="https://www.google.com/recaptcha/enterprise.js?render=$TOKEN_KEY&waf=session" async defer></script>
</head>
<body>
  <h1>Main Page</h1>
  <p><a href="/good-score.html">Visit allowed link</a></p>
  <p><a href="/bad-score.html">Visit blocked link</a></p>
  <p><a href="/median-score.html">Visit redirect link</a></p>
</body>
</html>
HTML_CONTENT

sudo tee good-score.html > /dev/null <<GOOD_SCORE_CONTENT
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=windows-1252">
</head>
<body>
  <h1>Congrats! You have a good score!!</h1>
</body>
</html>
GOOD_SCORE_CONTENT

sudo tee bad-score.html > /dev/null <<BAD_SCORE_CONTENT
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=windows-1252">
</head>
<body>
  <h1>Sorry, You have a bad score!</h1>
</body>
</html>
BAD_SCORE_CONTENT

sudo tee median-score.html > /dev/null <<MEDIAN_SCORE_CONTENT
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=windows-1252">
</head>
<body>
  <h1>You have a median score that we need a second verification.</h1>
</body>
</html>
MEDIAN_SCORE_CONTENT
EOF_END

gcloud compute scp prepare_disk.sh $INSTANCE_NAME:/tmp --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet

gcloud compute ssh $INSTANCE_NAME --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet --command="export TOKEN_KEY=$TOKEN_KEY && bash /tmp/prepare_disk.sh"

echo -e "${GREEN}✅ HTML files deployed${RESET}"

# =====================================================
# 8. RECAPTCHA SECURITY POLICY
# =====================================================
echo -e "${YELLOW}Step 8: Setting up reCAPTCHA security policy...${RESET}"

gcloud compute security-policies create recaptcha-policy \
    --description "policy for bot management"

gcloud compute security-policies update recaptcha-policy \
  --recaptcha-redirect-site-key "$RECAPTCHA_KEY"

gcloud compute security-policies rules create 2000 \
    --security-policy recaptcha-policy\
    --expression "request.path.matches('good-score.html') &&    token.recaptcha_session.score > 0.4"\
    --action allow

gcloud compute security-policies rules create 3000 \
    --security-policy recaptcha-policy\
    --expression "request.path.matches('bad-score.html') && token.recaptcha_session.score < 0.6"\
    --action "deny-403"

gcloud compute security-policies rules create 1000 \
    --security-policy recaptcha-policy\
    --expression "request.path.matches('median-score.html') && token.recaptcha_session.score == 0.5"\
    --action redirect \
    --redirect-type google-recaptcha

gcloud compute backend-services update http-backend \
    --security-policy recaptcha-policy --global

echo -e "${GREEN}✅ reCAPTCHA security policy configured${RESET}"

# =====================================================
# 9. GET LOAD BALANCER IP & TEST
# =====================================================
echo -e "${YELLOW}Step 9: Getting load balancer IP address...${RESET}"

LB_IP_ADDRESS=$(gcloud compute forwarding-rules describe http-lb-forwarding-rule --global --format="value(IPAddress)")

echo -e "${GREEN}✅ Load balancer IP: ${CYAN}$LB_IP_ADDRESS${RESET}"

echo -e "${GREEN}${BOLD}🎉 Complete! Google Cloud Load Balancer with reCAPTCHA is now live.${RESET}"
echo -e "${CYAN}Access URL: http://$LB_IP_ADDRESS/index.html${RESET}"

# Optional: Display logs
echo -e "${BLUE}Security policy logs:${RESET}"
gcloud logging read "resource.type:(http_load_balancer) AND jsonPayload.enforcedSecurityPolicy.name:(recaptcha-policy)" --project=$DEVSHELL_PROJECT_ID --format=json