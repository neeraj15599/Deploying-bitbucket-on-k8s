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
# Create Kubernetes secrets
kubectl create secret generic bitbucket-database --from-literal=username='bitbucketuser' --from-literal=password='jellyfish' --namespace bitbucket
kubectl create secret tls atl-cd-certificate --cert=/etc/ssl/cert.pem --key=/etc/ssl/key.pem --namespace bitbucket
# Function to read database details from the YAML file
read_database_details() {
    if [ -f "deployment_details.txt" ]; then
        echo "Reading database details from deployment_details.txt..."
        DATABASE_URL=$(yq e '.database.url' deployment_details.txt)
        DATABASE_DRIVER=$(yq e '.database.driver' deployment_details.txt)
        DATABASE_SECRET_NAME=$(yq e '.database.credentials.secretName' deployment_details.txt)
        echo "Database URL: $DATABASE_URL"
        echo "Database driver: $DATABASE_DRIVER"
        echo "Database Secret Name: $DATABASE_SECRET_NAME"
    else
        echo "Error: deployment_details.txt not found. Please ensure it exists before running the script."
        exit 1
    fi
}
# Function to read NFS and volume details from the YAML file
read_nfs_and_volume_details() {
    if [ -f "deployment_details.txt" ]; then
        echo "Reading NFS and volume details from deployment_details.txt..."
        LOCALHOME_STORAGE_CLASS=$(yq e '.volumes.localHome.persistentVolumeClaim.storageClassName' deployment_details.txt)
        NFS_SERVER=$(yq e '.volumes.sharedHome.persistentVolume.nfs.server' deployment_details.txt)
        NFS_PATH=$(yq e '.volumes.sharedHome.persistentVolume.nfs.path' deployment_details.txt)
        echo "LocalHome Storage Class: $LOCALHOME_STORAGE_CLASS"
        echo "NFS Server: $NFS_SERVER"
        echo "NFS Path: $NFS_PATH"
    else
        echo "Error: deployment_details.txt not found. Please ensure it exists before running the script."
        exit 1
    fi
}
# Function to install yq if not present
install_yq() {
    if command -v yq &> /dev/null;
      then
        echo "yq is already installed."
    else
        echo "yq is not installed. Installing yq..."
        YQ_VERSION="v4.35.1"  # Specify the version you want to download
        wget "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -O yq
        chmod +x yq 
        sudo mv yq /usr/local/bin/yq
    fi
}
# Ensure yq is installed
install_yq
# Add the Helm chart repository for Atlassian DC products and update the repo
helm repo add atlassian-data-center https://atlassian.github.io/data-center-helm-charts
helm repo update
# Get the default values.yaml for the Bitbucket chart
helm show values atlassian-data-center/bitbucket > values.yaml
# Prompt the user for necessary values
prompt BITBUCKET_VERSION "Enter the desired Bitbucket version" "latest"
prompt INGRESS_HOST "Enter the Ingress Host"
prompt READINESS_PROBE "Should readinessProbe be enabled (true/false)" "false"
prompt Opensearch "Do you want to install standalone opensearch? (true/false)" "true"
# Ask user if they want to use existing database details
read -p "Do you want to use database details from deployment_details.txt? (yes/no) [yes]: " use_existing_details
use_existing_details=${use_existing_details:-yes}
if [[ "$use_existing_details" == "yes" ]]; then
    read_database_details
else
    # Prompt for database details if not using existing ones
    prompt DATABASE_URL "Enter the database URL" "jdbc:postgresql://<database IP>:5432/<database name>"
    prompt DATABASE_SECRET_NAME "Enter the database secret name" "bitbucket-database"
fi
# Ask user if they want to use existing NFS and volume details
read -p "Do you want to use NFS and volume details from deployment_details.txt? (yes/no) [yes]: " use_existing_nfs_details
use_existing_nfs_details=${use_existing_nfs_details:-yes}
if [[ "$use_existing_nfs_details" == "yes" ]]; then
    read_nfs_and_volume_details
else
    # Prompt for NFS and volume details if not using existing ones
    prompt LOCALHOME_STORAGE_CLASS "Enter the LocalHome storage  class" "hostpath"
    prompt NFS_SERVER "Enter the NFS server IP" "<NFS-server-IP>"
    prompt NFS_PATH "Enter the NFS path" "/srv/nfs"
fi
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
yq e -i "
  .image.tag = \"${BITBUCKET_VERSION}\" |
  .ingress.host = \"${INGRESS_HOST}\" |
  .ingress.create = true |
  .bitbucket.readinessProbe.enabled = ${READINESS_PROBE} |
  .opensearch.install = ${Opensearch} |
  .database.url = \"${DATABASE_URL}\" |
  .database.driver = \"${DATABASE_DRIVER}\" |
  .database.credentials.secretName = \"${DATABASE_SECRET_NAME}\" |
  .volumes.localHome.persistentVolumeClaim.create = true |
  .volumes.localHome.persistentVolumeClaim.storageClassName = \"${LOCALHOME_STORAGE_CLASS}\" |
  .volumes.sharedHome.persistentVolume.create = true |
  .volumes.sharedHome.persistentVolume.nfs.server = \"${NFS_SERVER}\" |
  .volumes.sharedHome.persistentVolume.nfs.path = \"${NFS_PATH}\" |
  .volumes.sharedHome.persistentVolumeClaim.create = true |
  .volumes.sharedHome.persistentVolumeClaim.storageClassName = \"\"
" values.yaml
# Create namespace if it does not exist
kubectl get namespace bitbucket || kubectl create namespace bitbucket
# Install Bitbucket using the updated values.yaml file
helm install bitbucket atlassian-data-center/bitbucket --namespace bitbucket --values values.yaml
echo "Bitbucket installation script completed. The values.yaml file has been updated with your inputs."