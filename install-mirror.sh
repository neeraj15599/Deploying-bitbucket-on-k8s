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
# Add Helm repositories
echo "Adding Helm repositories..."
helm repo add rimusz https://charts.rimusz.net
helm repo add atlassian-data-center https://atlassian.github.io/data-center-helm-charts
# Update Helm repositories
echo "Updating Helm repositories..."
helm repo update
# Install hostpath-provisioner
echo "Installing hostpath-provisioner in 'kube-system' namespace..."
helm install hostpath-provisioner --namespace kube-system rimusz/hostpath-provisioner
# Create namespace for Bitbucket Mirror
echo "Creating namespace for Bitbucket Mirror..."
kubectl create namespace bitbucket-mirror
# Create SSL certificate secret
echo "Creating SSL certificate secret..."
kubectl create secret tls atl-cd-certificate --cert=/etc/ssl/cert.pem --key=/etc/ssl/key.pem --namespace bitbucket-mirror
# Prompt for user input
prompt UPSTREAM_URL "Enter the upstream URL in this format: https://<hostname>"
prompt SETUP_BASEURL "Enter the SETUP_BASEURL in this format https://<hostname>"
prompt INGRESS_HOST "Enter the Ingress Host, do not use https, just provide the hostname of the mirror server"
# Create values-mirror.yaml file
echo "Creating values-mirror.yaml file..."
cat <<EOF > values-mirror.yaml
replicaCount: 1
image:
  repository: atlassian/bitbucket
  pullPolicy: IfNotPresent
  tag: "8.9.10"
bitbucket:
  mode: mirror
  displayName: Bitbucket Mirror Farm
  clustering:
    enabled: true
  applicationMode: "mirror"
  mirror:
    upstreamUrl: "${UPSTREAM_URL}"
  readinessProbe:
    enabled: false
  additionalEnvironmentVariables:
    - name: SETUP_BASEURL
      value: "${SETUP_BASEURL}"
ingress:
  create: true
  host: "${INGRESS_HOST}"
  tlsSecretName: atl-cd-certificate
volumes:
  localHome:
    persistentVolumeClaim:
      create: true
EOF
# Spin up a single-node Bitbucket Mirror
echo "Installing Bitbucket Mirror..."
helm install bitbucket-mirror atlassian-data-center/bitbucket --namespace bitbucket-mirror --values values-mirror.yaml
echo "Bitbucket Mirror setup complete."