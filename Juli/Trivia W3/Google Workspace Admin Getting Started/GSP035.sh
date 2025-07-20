#!/bin/bash

# =====================================================
# Google Workspace Admin Console Setup Helper
# Preparation and Guidance Script
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Google Workspace Admin Console Setup Helper${RESET}"
echo -e "${BLUE}${BOLD}===========================================${RESET}"

# =====================================================
# 1. DISPLAY CREDENTIALS INFORMATION
# =====================================================
echo -e "${YELLOW}Step 1: Lab Credentials Information${RESET}"

echo -e "${CYAN}To complete the Google Workspace setup, you'll need:${RESET}"
echo -e "${CYAN}  - User Email (from Lab Details panel)${RESET}"
echo -e "${CYAN}  - Password (from Lab Details panel)${RESET}"
echo -e "${CYAN}  - Admin Console URL${RESET}"

echo -e "${GREEN}✅ Check the Lab Details panel for your credentials${RESET}"

# =====================================================
# 2. CREATE CSV TEMPLATE FOR BULK USER UPLOAD
# =====================================================
echo -e "${YELLOW}Step 2: Creating CSV template for bulk user upload...${RESET}"

# Create directory for workspace files
mkdir -p workspace-setup
cd workspace-setup

# Create CSV template
echo -e "${CYAN}Creating bulk_users_template.csv...${RESET}"
cat > bulk_users_template.csv <<EOF
First Name [Required],Last Name [Required],Email Address [Required],Password [Required],Org Unit Path [Required],Phone [Work],Phone [Home],Phone [Mobile],Address [Work],Address [Home],Employee ID,Employee Type,Manager Email,Department,Cost Center,Building ID,Floor Name,Floor Section
John,Doe,john.doe@YOURDOMAIN.com,TempPass123,/,555-1234,555-5678,555-9012,"123 Work St","456 Home Ave",EMP001,Full-time,manager@YOURDOMAIN.com,IT,CC001,Building1,Floor1,Section A
Jane,Smith,jane.smith@YOURDOMAIN.com,TempPass456,/,555-2345,555-6789,555-0123,"789 Work Blvd","101 Home Rd",EMP002,Full-time,manager@YOURDOMAIN.com,HR,CC002,Building1,Floor2,Section B
EOF

echo -e "${GREEN}✅ CSV template created: bulk_users_template.csv${RESET}"

# =====================================================
# 3. CREATE SAMPLE LOGO
# =====================================================
echo -e "${YELLOW}Step 3: Creating sample logo for organization branding...${RESET}"

# Create a simple SVG logo
echo -e "${CYAN}Creating sample_logo.svg...${RESET}"
cat > sample_logo.svg <<EOF
<svg width="100" height="100" xmlns="http://www.w3.org/2000/svg">
  <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="blue" />
  <text x="50" y="55" font-family="Arial" font-size="16" fill="white" text-anchor="middle">LOGO</text>
</svg>
EOF

echo -e "${GREEN}✅ Sample logo created: sample_logo.svg${RESET}"

# =====================================================
# 4. CREATE SETUP CHECKLIST
# =====================================================
echo -e "${YELLOW}Step 4: Creating setup checklist...${RESET}"

echo -e "${CYAN}Creating workspace_setup_checklist.txt...${RESET}"
cat > workspace_setup_checklist.txt <<EOF
GOOGLE WORKSPACE ADMIN CONSOLE SETUP CHECKLIST
===============================================

PREREQUISITE STEPS (Done via Admin Console UI):
□ 1. Sign in to Google Workspace Admin Console
□ 2. Verify domain (click VERIFY DOMAIN and follow steps)
□ 3. Complete domain verification process

TASK 1: CONFIGURE ORGANIZATION PROFILE
□ 1. Navigate to Account > Account settings > Profile
□ 2. Update Organization Name
□ 3. Set Support message for users
□ 4. Configure Language settings
□ 5. Set Time zone
□ 6. Update Preferences (Scheduled release, New products)
□ 7. Configure Communication preferences
□ 8. Upload Custom Logo (use sample_logo.svg)

TASK 2: ADD USERS INDIVIDUALLY
□ 1. Navigate to Directory > Users
□ 2. Click "Add new user"
□ 3. Fill in First/Last name and email
□ 4. Manage password settings
□ 5. Save user credentials for testing
□ 6. Send sign-in instructions

TASK 3: BATCH ADD USERS FROM CSV
□ 1. Navigate to Users > Bulk update users
□ 2. Download blank CSV template (or use provided template)
□ 3. Fill in user information with your domain
□ 4. Upload CSV file
□ 5. Monitor import progress via Tasks icon

TASK 4: VERIFY CUSTOMIZATION
□ 1. Open Gmail in new tab
□ 2. Add another account with new user credentials
□ 3. Accept terms and change password
□ 4. Verify custom workspace appearance

IMPORTANT NOTES:
- Replace YOURDOMAIN.com in CSV with your actual domain
- Passwords must meet format guidelines (8+ characters)
- Use Org Unit Path: / for this lab
- Monitor Tasks icon for bulk import progress
EOF

echo -e "${GREEN}✅ Setup checklist created: workspace_setup_checklist.txt${RESET}"

# =====================================================
# 5. CREATE DOMAIN EXTRACTION HELPER
# =====================================================
echo -e "${YELLOW}Step 5: Creating domain extraction helper...${RESET}"

echo -e "${CYAN}Creating extract_domain.sh helper script...${RESET}"
cat > extract_domain.sh <<'EOF'
#!/bin/bash

# Helper script to extract domain from lab email
echo "Enter your lab User Email (from Lab Details panel):"
read USER_EMAIL

if [[ $USER_EMAIL == *"@"* ]]; then
    DOMAIN=$(echo $USER_EMAIL | cut -d'@' -f2)
    echo ""
    echo "Your domain is: $DOMAIN"
    echo ""
    echo "Use this domain for creating users in the CSV file:"
    echo "Example: newuser@$DOMAIN"
    echo ""
    echo "Replace YOURDOMAIN.com in bulk_users_template.csv with: $DOMAIN"
else
    echo "Invalid email format. Please enter a valid email address."
fi
EOF

chmod +x extract_domain.sh

echo -e "${GREEN}✅ Domain extraction helper created: extract_domain.sh${RESET}"

# =====================================================
# 6. CREATE PASSWORD GENERATOR
# =====================================================
echo -e "${YELLOW}Step 6: Creating password generator for users...${RESET}"

echo -e "${CYAN}Creating generate_passwords.sh...${RESET}"
cat > generate_passwords.sh <<'EOF'
#!/bin/bash

# Generate secure passwords for workspace users
echo "Generating 10 sample passwords for Google Workspace users:"
echo "========================================================="

for i in {1..10}; do
    # Generate password with uppercase, lowercase, numbers
    PASSWORD=$(openssl rand -base64 12 | tr -d "+/=" | cut -c1-10)
    # Ensure it starts with uppercase and add number
    PASSWORD="$(echo ${PASSWORD:0:1} | tr '[:lower:]' '[:upper:]')${PASSWORD:1}$(shuf -i 1-9 -n 1)"
    echo "Password $i: $PASSWORD"
done

echo ""
echo "Use these passwords in your CSV file for bulk user creation."
echo "Remember: Passwords must be at least 8 characters long."
EOF

chmod +x generate_passwords.sh

echo -e "${GREEN}✅ Password generator created: generate_passwords.sh${RESET}"

# =====================================================
# 7. DISPLAY SUMMARY AND NEXT STEPS
# =====================================================
echo ""
echo -e "${GREEN}${BOLD}🎉 Setup Complete! Files created in workspace-setup/ directory:${RESET}"
echo -e "${CYAN}  - bulk_users_template.csv (template for bulk user upload)${RESET}"
echo -e "${CYAN}  - sample_logo.svg (sample logo for organization branding)${RESET}"
echo -e "${CYAN}  - workspace_setup_checklist.txt (step-by-step checklist)${RESET}"
echo -e "${CYAN}  - extract_domain.sh (helper to extract your lab domain)${RESET}"
echo -e "${CYAN}  - generate_passwords.sh (password generator for users)${RESET}"

echo ""
echo -e "${YELLOW}${BOLD}NEXT STEPS:${RESET}"
echo -e "${CYAN}1. Run: ./extract_domain.sh to get your lab domain${RESET}"
echo -e "${CYAN}2. Edit bulk_users_template.csv with your domain and user info${RESET}"
echo -e "${CYAN}3. Use ./generate_passwords.sh for secure passwords${RESET}"
echo -e "${CYAN}4. Follow workspace_setup_checklist.txt for UI steps${RESET}"
echo -e "${CYAN}5. Open Google Workspace Admin Console and complete setup${RESET}"

echo ""
echo -e "${BLUE}${BOLD}Important URLs:${RESET}"
echo -e "${CYAN}- Google Workspace Admin Console: https://admin.google.com${RESET}"
echo -e "${CYAN}- Gmail: https://gmail.com${RESET}"

echo ""
echo -e "${YELLOW}Note: Most Google Workspace configuration must be done through the${RESET}"
echo -e "${YELLOW}Admin Console UI. This script provides preparation and guidance.${RESET}"

# List files created
echo ""
echo -e "${CYAN}Files created:${RESET}"
ls -la workspace-setup/