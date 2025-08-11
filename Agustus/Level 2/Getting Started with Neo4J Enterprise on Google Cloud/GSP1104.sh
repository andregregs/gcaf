#!/bin/bash

# Neo4j Data Loading Automation Script
# This script automates Neo4j data operations after manual login

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print colored status messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "\n${PURPLE}════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════════════════════════════${NC}"
}

print_task() {
    echo -e "\n${CYAN}▶ TASK: $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════${NC}"
}

print_manual() {
    echo -e "\n${RED}🚨 MANUAL STEP REQUIRED:${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${WHITE}Press ENTER when completed...${NC}"
    read -r
}

# Neo4j connection settings
NEO4J_USER="neo4j"
NEO4J_PASSWORD="foobar123%'"
NEO4J_PORT="7474"

# =============================================================================
# TASK 1: CONNECT TO NEO4J
# =============================================================================
print_task "1. Connect to Neo4j"

print_step "Step 1.1: Get Region and Zone from Project Metadata"
print_status "Retrieving zone and region from project metadata..."

export ZONE=$(gcloud compute project-info describe \
    --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe \
    --format="value(commonInstanceMetadata.items[google-compute-default-region])")

echo -e "${CYAN}Region: ${WHITE}$REGION${NC}"
echo -e "${CYAN}Zone: ${WHITE}$ZONE${NC}"

print_step "Step 1.2: Find Neo4j VM Instance"
print_status "Looking for Neo4j VM instance..."

# Get the Neo4j VM info including zone
NEO4J_VM_INFO=$(gcloud compute instances list --filter="name~'neo4j'" --format="value(name,zone)" | head -1)

if [ -z "$NEO4J_VM_INFO" ]; then
    print_error "Neo4j VM not found! Please wait for deployment to complete."
    exit 1
fi

# Split the output to get name and zone
NEO4J_VM=$(echo $NEO4J_VM_INFO | cut -d' ' -f1)
NEO4J_ZONE=$(echo $NEO4J_VM_INFO | cut -d' ' -f2)

# Get the external IP using the correct zone
NEO4J_EXTERNAL_IP=$(gcloud compute instances describe $NEO4J_VM --zone=$NEO4J_ZONE --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

echo -e "${CYAN}Neo4j VM: ${WHITE}$NEO4J_VM${NC}"
echo -e "${CYAN}Neo4j Zone: ${WHITE}$NEO4J_ZONE${NC}"
echo -e "${CYAN}External IP: ${WHITE}$NEO4J_EXTERNAL_IP${NC}"
echo -e "${CYAN}Neo4j URL: ${WHITE}http://$NEO4J_EXTERNAL_IP:$NEO4J_PORT${NC}"

print_step "Step 1.3: Check Neo4j Service Availability"
print_status "Checking if Neo4j service is ready..."

for i in {1..30}; do
    if curl -s "http://$NEO4J_EXTERNAL_IP:$NEO4J_PORT" >/dev/null; then
        print_success "Neo4j service is ready!"
        break
    fi
    echo "Attempt $i: Service not ready yet, waiting 30 seconds..."
    sleep 30
done

print_step "Step 1.4: Manual Login Required"
print_manual "Please open your browser and go to: http://$NEO4J_EXTERNAL_IP:$NEO4J_PORT
Login with:
- Connect URL: (leave default)
- Database: (leave empty)  
- Authentication: Username/Password
- Username: $NEO4J_USER
- Password: $NEO4J_PASSWORD

Click Connect and then return here."

echo -e "\n${GREEN}✓ TASK 1 COMPLETED: Neo4j connection established!${NC}"

# =============================================================================
# TASK 2: MOVE DATA TO NEO4J (SAMPLE DATA)
# =============================================================================
print_task "2. Move Data to Neo4j (Sample Day)"

print_step "Step 2.1: Load Sample Data from CSV"
print_status "Preparing Cypher query for sample data loading..."

SAMPLE_QUERY="LOAD CSV WITH HEADERS FROM 'https://storage.googleapis.com/neo4j-datasets/form13/2022-02-17.csv' AS row
MERGE (m:Manager {filingManager:row.filingManager})
MERGE (c:Company {nameOfIssuer:row.nameOfIssuer, cusip:row.cusip})
MERGE (m)-[r1:Owns {value:toInteger(row.value), shares:toInteger(row.shares), reportCalendarOrQuarter:row.reportCalendarOrQuarter}]->(c)"

echo -e "${YELLOW}Copy and paste this query in Neo4j browser:${NC}"
echo -e "${WHITE}$SAMPLE_QUERY${NC}"

print_manual "Copy the above Cypher query and paste it in the Neo4j browser query field. Click the blue triangle to run it."

echo -e "\n${GREEN}✓ TASK 2 COMPLETED: Sample data loaded!${NC}"

# =============================================================================
# TASK 3: EXPLORE THE DATA
# =============================================================================
print_task "3. Explore the Data Using Neo4j"

print_step "Step 3.1: Explore Manager Nodes"
print_manual "In Neo4j browser:
1. Click on 'Manager' under Node Labels to generate a query
2. Click on any manager node to expand it
3. Click the graph icon to see company connections
4. Click on relationships to view transaction details"

print_step "Step 3.2: Find Duplicate Nodes"
DUPLICATE_QUERY="MATCH (n:Company{cusip:\"78462F103\"}) RETURN n LIMIT 25"

echo -e "${YELLOW}Run this query to find duplicate nodes:${NC}"
echo -e "${WHITE}$DUPLICATE_QUERY${NC}"

print_manual "Copy the above query to see duplicate company entries with same CUSIP."

print_step "Step 3.3: Delete Sample Data"
DELETE_QUERY="MATCH (n) DETACH DELETE n;"

echo -e "${YELLOW}Delete all data with this query:${NC}"
echo -e "${WHITE}$DELETE_QUERY${NC}"

print_manual "Copy and run the delete query to clear all sample data."

echo -e "\n${GREEN}✓ TASK 3 COMPLETED: Data exploration finished!${NC}"

# =============================================================================
# TASK 4: LOAD FULL YEAR DATA
# =============================================================================
print_task "4. A Year of Data"

print_step "Step 4.1: Create Constraints"
print_status "Preparing constraint creation queries..."

CONSTRAINT_QUERIES=(
    "CREATE CONSTRAINT IF NOT EXISTS FOR (p:Company) REQUIRE (p.cusip) IS NODE KEY;"
    "CREATE CONSTRAINT IF NOT EXISTS FOR (p:Manager) REQUIRE (p.filingManager) IS NODE KEY;"
    "CREATE CONSTRAINT IF NOT EXISTS FOR (p:Holding) REQUIRE (p.filingManager, p.cusip, p.reportCalendarOrQuarter) IS NODE KEY;"
)

echo -e "${YELLOW}Run these constraint queries one by one:${NC}"
for query in "${CONSTRAINT_QUERIES[@]}"; do
    echo -e "${WHITE}$query${NC}"
done

print_manual "Copy and run each constraint query above in Neo4j browser."

print_step "Step 4.2: Load Companies"
COMPANY_QUERY="LOAD CSV WITH HEADERS FROM 'https://storage.googleapis.com/neo4j-datasets/form13/2021.csv' AS row
MERGE (c:Company {cusip:row.cusip})
ON CREATE SET
    c.nameOfIssuer=row.nameOfIssuer"

echo -e "${YELLOW}Load companies with this query:${NC}"
echo -e "${WHITE}$COMPANY_QUERY${NC}"

print_manual "Copy and run the company loading query."

print_step "Step 4.3: Load Managers"
MANAGER_QUERY="LOAD CSV WITH HEADERS FROM 'https://storage.googleapis.com/neo4j-datasets/form13/2021.csv' AS row
MERGE (m:Manager {filingManager:row.filingManager})"

echo -e "${YELLOW}Load managers with this query:${NC}"
echo -e "${WHITE}$MANAGER_QUERY${NC}"

print_manual "Copy and run the manager loading query."

print_step "Step 4.4: Load Holdings"
HOLDING_QUERY="LOAD CSV WITH HEADERS FROM 'https://storage.googleapis.com/neo4j-datasets/form13/2021.csv' AS row
MERGE (h:Holding {filingManager:row.filingManager, cusip:row.cusip, reportCalendarOrQuarter:row.reportCalendarOrQuarter})
ON CREATE SET
    h.value=row.value,
    h.shares=row.shares,
    h.target=row.target,
    h.nameOfIssuer=row.nameOfIssuer"

echo -e "${YELLOW}Load holdings with this query:${NC}"
echo -e "${WHITE}$HOLDING_QUERY${NC}"

print_manual "Copy and run the holdings loading query."

print_step "Step 4.5: Create OWNS Relationships"
OWNS_QUERY="LOAD CSV WITH HEADERS FROM 'https://storage.googleapis.com/neo4j-datasets/form13/2021.csv' AS row
MATCH (m:Manager {filingManager:row.filingManager})
MATCH (h:Holding {filingManager:row.filingManager, cusip:row.cusip, reportCalendarOrQuarter:row.reportCalendarOrQuarter})
MERGE (m)-[r:OWNS]->(h)"

echo -e "${YELLOW}Create OWNS relationships with this query:${NC}"
echo -e "${WHITE}$OWNS_QUERY${NC}"

print_manual "Copy and run the OWNS relationship query."

print_step "Step 4.6: Create PARTOF Relationships"
PARTOF_QUERY="LOAD CSV WITH HEADERS FROM 'https://storage.googleapis.com/neo4j-datasets/form13/2021.csv' AS row
MATCH (h:Holding {filingManager:row.filingManager, cusip:row.cusip, reportCalendarOrQuarter:row.reportCalendarOrQuarter})
MATCH (c:Company {cusip:row.cusip})
MERGE (h)-[r:PARTOF]->(c)"

echo -e "${YELLOW}Create PARTOF relationships with this query:${NC}"
echo -e "${WHITE}$PARTOF_QUERY${NC}"

print_manual "Copy and run the PARTOF relationship query."

echo -e "\n${GREEN}✓ TASK 4 COMPLETED: Full year data loaded with optimized structure!${NC}"

print_step "Summary of Manual Steps Required"
echo -e "${CYAN}What you need to do manually:${NC}"
echo -e "${WHITE}1. Login to Neo4j browser interface${NC}"
echo -e "${WHITE}2. Copy and paste Cypher queries provided by this script${NC}"
echo -e "${WHITE}3. Click run button for each query${NC}"
echo -e "${WHITE}4. Explore the graph visually in the browser${NC}"

print_success "All automation completed! Follow the manual steps as prompted. 🎉"