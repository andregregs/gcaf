#!/bin/bash

# =====================================================
# Python Package Upload to Artifact Registry
# Complete Python Package Build and Upload Script
# =====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}Starting Python package upload to Artifact Registry...${RESET}"

# =====================================================
# 1. AUTHENTICATION & SERVICES
# =====================================================
echo -e "${YELLOW}Step 1: Setting up authentication and services...${RESET}"

# Check current authentication
gcloud auth list

# Enable Artifact Registry API
gcloud services enable artifactregistry.googleapis.com

echo -e "${GREEN}✅ Authentication and services configured${RESET}"

# =====================================================
# 2. ENVIRONMENT SETUP
# =====================================================
echo -e "${YELLOW}Step 2: Setting up environment variables...${RESET}"

# Set up environment variables
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

# Configure gcloud defaults
gcloud config set compute/region $REGION
gcloud config set project $PROJECT_ID

echo -e "${GREEN}✅ Environment configured: $PROJECT_ID | $REGION${RESET}"

# =====================================================
# 3. CREATE PYTHON REPOSITORY
# =====================================================
echo -e "${YELLOW}Step 3: Creating Python repository in Artifact Registry...${RESET}"

gcloud artifacts repositories create my-python-repo \
    --repository-format=python \
    --location="$REGION" \
    --description="Python package repository"

echo -e "${GREEN}✅ Python repository created${RESET}"

# =====================================================
# 4. INSTALL REQUIRED PACKAGES
# =====================================================
echo -e "${YELLOW}Step 4: Installing required Python packages...${RESET}"

echo -e "${CYAN}Installing Google Artifact Registry authentication...${RESET}"
pip install keyrings.google-artifactregistry-auth

echo -e "${CYAN}Installing twine for package publishing...${RESET}"
pip install twine

echo -e "${GREEN}✅ Required packages installed${RESET}"

# =====================================================
# 5. CONFIGURE PIP
# =====================================================
echo -e "${YELLOW}Step 5: Configuring pip for Artifact Registry...${RESET}"

pip config set global.extra-index-url https://"$REGION"-python.pkg.dev/"$PROJECT_ID"/my-python-repo/simple

echo -e "${GREEN}✅ Pip configuration updated${RESET}"

# =====================================================
# 6. CREATE PYTHON PACKAGE
# =====================================================
echo -e "${YELLOW}Step 6: Creating Python package structure...${RESET}"

# Create package directory
mkdir my-package
cd my-package

# Set default email if not provided
EMAIL=${EMAIL:-"user@example.com"}

# Create setup.py
echo -e "${CYAN}Creating setup.py...${RESET}"
cat > setup.py <<EOF
from setuptools import setup, find_packages
setup(
    name='my_package',
    version='0.1.0',
    author='cls',
    author_email='$EMAIL',
    packages=find_packages(exclude=['tests']),
    install_requires=[
        # List your dependencies here
    ],
    description='A sample Python package',
)
EOF

# Create package directory and module
echo -e "${CYAN}Creating package module...${RESET}"
mkdir -p my_package
cat > my_package/my_module.py <<EOF
def hello_world():
    return 'Hello, world!'
EOF

# Create __init__.py for proper package structure
echo -e "${CYAN}Creating __init__.py...${RESET}"
cat > my_package/__init__.py <<EOF
from .my_module import hello_world

__version__ = '0.1.0'
__all__ = ['hello_world']
EOF

echo -e "${GREEN}✅ Python package structure created${RESET}"

# =====================================================
# 7. BUILD PACKAGE
# =====================================================
echo -e "${YELLOW}Step 7: Building Python package...${RESET}"

echo -e "${CYAN}Creating source distribution and wheel...${RESET}"
python setup.py sdist bdist_wheel

echo -e "${GREEN}✅ Package built successfully${RESET}"

# =====================================================
# 8. UPLOAD PACKAGE
# =====================================================
echo -e "${YELLOW}Step 8: Uploading package to Artifact Registry...${RESET}"

python3 -m twine upload --repository-url https://"$REGION"-python.pkg.dev/"$PROJECT_ID"/my-python-repo/ dist/*

echo -e "${GREEN}✅ Package uploaded successfully${RESET}"

# =====================================================
# 9. VERIFY PACKAGE
# =====================================================
echo -e "${YELLOW}Step 9: Verifying uploaded package...${RESET}"

echo -e "${CYAN}Listing packages in repository:${RESET}"
gcloud artifacts packages list --repository=my-python-repo --location="$REGION"

echo -e "${GREEN}${BOLD}🎉 Complete! Python package is now available in Artifact Registry.${RESET}"
echo -e "${CYAN}Package: my_package@0.1.0${RESET}"
echo -e "${CYAN}Repository: https://$REGION-python.pkg.dev/$PROJECT_ID/my-python-repo/simple${RESET}"
echo -e "${CYAN}Install command: pip install my-package --extra-index-url https://$REGION-python.pkg.dev/$PROJECT_ID/my-python-repo/simple${RESET}"