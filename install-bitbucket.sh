#!/bin/bash
# Function to prompt user input with a default value
prompt() {
    local varname="$1"
    local prompt="$2"
    local default="$3"
    read -p "$prompt [$default]: " input
    # If input is empty, use default value
    export "$varname"="${input:-$default}"
}
# Add the Helm chart repository for Atlassian DC products and update the repo
helm repo add atlassian-data-center https://atlassian.github.io/data-center-helm-charts
helm repo update
# Get the default values.yaml for the Bitbucket chart
helm show values atlassian-data-center/bitbucket > values.yaml
# Function to install yq if not present
install_yq() {
    if command -v yq &> /dev/null; then
        echo "yq is already installed."
    else
        echo "yq is not installed. Installing y yq..."
        YQ_VERSION="v4.35.1"  # Specify the version you want to download
        wget "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -O yq
        chmod +x yq
        sudo mv yq /usr/local/bin/yq
    fi
}

# Create a new namespace for Bitbucket
kubectl create namespace bitbucket

# Prompt the user for necessary values
prompt BITBUCKET_VERSION "Enter the desired Bitbucket version" "latest"
prompt INGRESS_HOST "Enter the Ingress Host"
prompt READINESS_PROBE "Should readinessProbe be enabled (true/false)" "false"
# Ensure yq is installed
install_yq
# Backup the existing values.yaml file
if [ -f values.yaml ]; then
    echo "Backing up existing values.yaml to values.yaml.bkp"
    cp values.yaml values.yaml.bkp
else
    echo "No existing values.yaml found. Please ensure it is present before running the script."
    exit 1
fi
# Modify the existing values.yaml file with yq
echo "Updating values.yaml with new user inputs..."
# Update the YAML file using yq with the user's input
yq e -i "
  .image.tag = \"${BITBUCKET_VERSION}\" |
  .ingress.host = \"${INGRESS_HOST}\" |
  .ingress.create = true |
  .bitbucket.readinessProbe.enabled = ${READINESS_PROBE}
" values.yaml
# Install Bitbucket using the updated values.yaml file
helm install bitbucket atlassian-data-center/bitbucket --namespace bitbucket --values values.yaml
echo "Bitbucket installation script completed. The values.yaml file has been updated with your inputs."
