#!/bin/bash

# =====================================================
# Google Cloud API Keys and Natural Language API
# Complete API Key Setup and Remote Execution Script
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting API Keys and Natural Language API setup...${RESET}"

# =====================================================
# 1. AUTHENTICATION & SERVICES
# =====================================================
echo -e "${YELLOW}Step 1: Setting up authentication and services...${RESET}"

# Check current authentication
gcloud auth list

# Enable API Keys service
gcloud services enable apikeys.googleapis.com

echo -e "${GREEN}✅ Authentication and services configured${RESET}"

# =====================================================
# 2. DISCOVER COMPUTE INSTANCE
# =====================================================
echo -e "${YELLOW}Step 2: Discovering target compute instance...${RESET}"

# Get zone of the linux-instance
export ZONE=$(gcloud compute instances list --filter="name=('linux-instance')" --format="value(zone)")

if [ -z "$ZONE" ]; then
    echo -e "${RED}❌ Error: linux-instance not found${RESET}"
    exit 1
fi

echo -e "${GREEN}✅ Target instance found: linux-instance in zone $ZONE${RESET}"

# =====================================================
# 3. CREATE API KEY
# =====================================================
echo -e "${YELLOW}Step 3: Creating API key...${RESET}"

# Create API key with display name
gcloud alpha services api-keys create --display-name="techcps"

# Get the key name
KEY_NAME=$(gcloud alpha services api-keys list --format="value(name)" --filter="displayName=techcps")

# Get the actual API key string
API_KEY=$(gcloud alpha services api-keys get-key-string $KEY_NAME --format="value(keyString)")

echo -e "${GREEN}✅ API key created: ${CYAN}$API_KEY${RESET}"

# =====================================================
# 4. CREATE REMOTE EXECUTION SCRIPT
# =====================================================
echo -e "${YELLOW}Step 4: Creating remote execution script...${RESET}"

echo -e "${CYAN}Generating techcps.sh for remote execution...${RESET}"
cat > techcps.sh <<EOF_CP
#!/bin/bash

# Colors for remote script
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "\${BLUE}\${BOLD}Running Natural Language API analysis on remote instance...\${RESET}"

# Get API key information
echo -e "\${YELLOW}Getting API key...\${RESET}"
KEY_NAME=\$(gcloud alpha services api-keys list --format="value(name)" --filter="displayName=techcps")
API_KEY=\$(gcloud alpha services api-keys get-key-string \$KEY_NAME --format="value(keyString)")

echo -e "\${GREEN}✅ API Key: \${CYAN}\$API_KEY\${RESET}"

# Create request JSON for Natural Language API
echo -e "\${YELLOW}Creating request payload...\${RESET}"
cat > request.json <<EOF
{
  "document":{
    "type":"PLAIN_TEXT",
    "content":"Joanne Rowling, who writes under the pen names J. K. Rowling and Robert Galbraith, is a British novelist and screenwriter who wrote the Harry Potter fantasy series."
  },
  "encodingType":"UTF8"
}
EOF

echo -e "\${GREEN}✅ Request payload created\${RESET}"

# Call Natural Language API
echo -e "\${YELLOW}Calling Natural Language API for entity analysis...\${RESET}"
curl "https://language.googleapis.com/v1/documents:analyzeEntities?key=\${API_KEY}" \\
  -s -X POST -H "Content-Type: application/json" --data-binary @request.json > result.json

echo -e "\${GREEN}✅ API call completed\${RESET}"

# Display results
echo -e "\${BLUE}\${BOLD}Analysis Results:\${RESET}"
cat result.json

echo -e "\${GREEN}\${BOLD}🎉 Natural Language API analysis complete!\${RESET}"
EOF_CP

echo -e "${GREEN}✅ Remote execution script created${RESET}"

# =====================================================
# 5. COPY SCRIPT TO REMOTE INSTANCE
# =====================================================
echo -e "${YELLOW}Step 5: Copying script to remote instance...${RESET}"

gcloud compute scp techcps.sh linux-instance:/tmp \
    --project=$DEVSHELL_PROJECT_ID \
    --zone=$ZONE \
    --quiet

echo -e "${GREEN}✅ Script copied to linux-instance:/tmp/techcps.sh${RESET}"

# =====================================================
# 6. EXECUTE SCRIPT ON REMOTE INSTANCE
# =====================================================
echo -e "${YELLOW}Step 6: Executing script on remote instance...${RESET}"

echo -e "${CYAN}Running Natural Language API analysis remotely...${RESET}"
gcloud compute ssh linux-instance \
    --project=$DEVSHELL_PROJECT_ID \
    --zone=$ZONE \
    --quiet \
    --command="bash /tmp/techcps.sh"

echo -e "${GREEN}${BOLD}🎉 Complete! API key created and Natural Language API executed successfully.${RESET}"
echo -e "${CYAN}API Key: $API_KEY${RESET}"
echo -e "${CYAN}Instance: linux-instance (zone: $ZONE)${RESET}"