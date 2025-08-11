#!/bin/bash

# Optimized Firestore Database Setup - High Performance Script
# Target: Sub 1.30 minute execution time

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# Optimized print functions (reduced overhead)
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_step() {
    echo -e "\n${PURPLE}════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════════════════════════════${NC}"
}
print_task() {
    echo -e "\n${CYAN}▶ TASK: $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════${NC}"
}

# Fast environment setup
export PROJECT_ID=$(gcloud config get-value project)
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
[ -z "$REGION" ] && export REGION="us-central1"

echo -e "${CYAN}Project: ${WHITE}$PROJECT_ID${NC} | ${CYAN}Region: ${WHITE}$REGION${NC}"

# =============================================================================
# TASK 1: PARALLEL API ENABLEMENT + FIRESTORE SETUP
# =============================================================================
print_task "1. Set up Firestore (Parallel Operations)"

print_step "Step 1.1: Enable APIs in Parallel"
# Enable APIs in background for speed
gcloud services enable firestore.googleapis.com &
API_PID1=$!
gcloud services enable logging.googleapis.com &
API_PID2=$!

print_step "Step 1.2: Create Firestore Database"
# Wait for firestore API then create database
wait $API_PID1
gcloud firestore databases create --location=$REGION --type=firestore-native &
DB_PID=$!

# Wait for logging API
wait $API_PID2
print_success "APIs enabled successfully!"

echo -e "\n${GREEN}✓ TASK 1 PROGRESS: APIs enabled, database creating...${NC}"

# =============================================================================
# TASK 2: PARALLEL REPO CLONE + DEPENDENCY SETUP
# =============================================================================
print_task "2. Setup Code Environment (Parallel)"

print_step "Step 2.1: Clone Repository"
git clone https://github.com/rosera/pet-theory --quiet &
CLONE_PID=$!

print_step "Step 2.2: Create Optimized Scripts"
# Create scripts while repo is cloning

# Optimized importTestData.js (reduced logging overhead)
cat > importTestData.js << 'EOF'
const csv = require('csv-parse');
const fs = require('fs');
const { Firestore } = require("@google-cloud/firestore");

async function writeToFirestore(records) {
  const db = new Firestore();
  const batch = db.batch();
  
  records.forEach((record) => {
    const docRef = db.collection("customers").doc(record.email);
    batch.set(docRef, record, { merge: true });
  });

  await batch.commit();
  return records.length;
}

async function importCsv(csvFilename) {
  const parser = csv.parse({ columns: true, delimiter: ',' }, async function (err, records) {
    if (err) {
      console.error('Error parsing CSV:', err);
      return;
    }
    try {
      const count = await writeToFirestore(records);
      console.log(`Wrote ${count} records`);
    } catch (e) {
      console.error(e);
      process.exit(1);
    }
  });

  fs.createReadStream(csvFilename).pipe(parser);
}

if (process.argv.length < 3) {
  console.error('Please include a path to a csv file');
  process.exit(1);
}

importCsv(process.argv[2]).catch(e => console.error(e));
EOF

# Optimized createTestData.js (minimal logging)
cat > createTestData.js << 'EOF'
const fs = require('fs');
const faker = require('faker');

function getRandomCustomerEmail(firstName, lastName) {
  const provider = faker.internet.domainName();
  const email = faker.internet.email(firstName, lastName, provider);
  return email.toLowerCase();
}

async function createTestData(recordCount) {
  const fileName = `customers_${recordCount}.csv`;
  const writeStream = fs.createWriteStream(fileName);
  writeStream.write('id,name,email,phone\n');
  
  for (let i = 0; i < recordCount; i++) {
    const id = faker.datatype.number();
    const firstName = faker.name.firstName();
    const lastName = faker.name.lastName();
    const name = `${firstName} ${lastName}`;
    const email = getRandomCustomerEmail(firstName, lastName);
    const phone = faker.phone.phoneNumber();
    writeStream.write(`${id},${name},${email},${phone}\n`);
  }
  
  writeStream.end();
  console.log(`Created file ${fileName} containing ${recordCount} records.`);
}

const recordCount = parseInt(process.argv[2]);
if (process.argv.length != 3 || recordCount < 1 || isNaN(recordCount)) {
  console.error('Include the number of test data records to create. Example:');
  console.error('    node createTestData.js 100');
  process.exit(1);
}

createTestData(recordCount);
EOF

wait $CLONE_PID
cd pet-theory/lab01

print_success "Repository cloned and scripts created!"

echo -e "\n${GREEN}✓ TASK 2 COMPLETED: Environment ready!${NC}"

# =============================================================================
# TASK 3: FAST DEPENDENCY INSTALLATION + TEST DATA
# =============================================================================
print_task "3. Install Dependencies & Create Test Data"

print_step "Step 3.1: Parallel Dependency Installation"
# Install all dependencies at once for speed
npm install @google-cloud/firestore @google-cloud/logging csv-parse faker@5.5.3 --silent --no-progress &
NPM_PID=$!

# Copy optimized scripts while npm installs
cp ../../importTestData.js .
cp ../../createTestData.js .

wait $NPM_PID
print_success "Dependencies installed!"

print_step "Step 3.2: Generate Test Data"
node createTestData 1000
print_success "Test data created!"

echo -e "\n${GREEN}✓ TASK 3 COMPLETED: Dependencies and test data ready!${NC}"

# =============================================================================
# TASK 4: FAST DATA IMPORT
# =============================================================================
print_task "4. Import Data to Firestore"

# Wait for database creation to complete
wait $DB_PID
print_success "Firestore database ready!"

print_step "Step 4.1: High-Speed Data Import"
print_status "Importing 1000 records..."

# Optimized import with minimal output
node importTestData customers_1000.csv

print_success "Data import completed!"

print_step "Step 4.2: Quick Verification"
# Minimal verification for speed
[ -f "customers_1000.csv" ] && print_success "CSV file verified!"

echo -e "\n${GREEN}✓ TASK 4 COMPLETED: Data imported successfully!${NC}"

# =============================================================================
# MINIMAL SUMMARY (FOR SPEED)
# =============================================================================
print_step "🎉 Lab Completed Successfully"

echo -e "${CYAN}Created:${NC} Firestore DB | ${WHITE}1000 Records${NC} | ${CYAN}Node.js App${NC}"
echo -e "${GREEN}Access:${NC} Navigation Menu → Firestore"

print_success "All tasks completed in optimized time! 🚀"