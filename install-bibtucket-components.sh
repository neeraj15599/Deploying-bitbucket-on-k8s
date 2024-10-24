#!/bin/bash
# Define the output file
OUTPUT_FILE="deployment_details.txt"
# Add helm repositories
echo "Adding helm repositories..." | tee -a $OUTPUT_FILE
helm repo add rimusz https://charts.rimusz.net | tee -a $OUTPUT_FILE
helm repo add bitnami https://charts.bitnami.com/bitnami | tee -a $OUTPUT_FILE
helm repo add atlassian-data-center https://atlassian.github.io/data-center-helm-charts | tee -a $OUTPUT_FILE
# Update helm repositories
echo "Updating helm repositories..." | tee -a $OUTPUT_FILE
helm repo update | tee -a $OUTPUT_FILE
# Install hostpath-provisioner
echo "Installing hostpath-provisioner..." | tee -a $OUTPUT_FILE
helm install hostpath -provisioner --namespace kube-system rimusz/hostpath-provisioner | tee -a $OUTPUT_FILE
# Create namespace for PostgreSQL
echo "Creating namespace for PostgreSQL..." | tee -a $OUTPUT_FILE
kubectl create namespace postgres | tee -a $OUTPUT_FILE
# Install PostgreSQL 15
echo "Installing PostgreSQL 15..." | tee -a $OUTPUT_FILE
helm install postgres15 bitnami/postgresql \
  --set image.tag=15 \
  --set global.postgresql.auth.postgresPassword=postgres \
  --namespace postgres | tee -a $OUTPUT_FILE
# Wait for the PostgreSQL pod to be ready
echo "Waiting for PostgreSQL pod to be ready..." | tee -a $OUTPUT_FILE
kubectl wait --namespace postgres --for=condition=ready pod -l app.kubernetes.io/name=postgresql --timeout=300s | tee -a $OUTPUT_FILE
# Retrieve the PostgreSQL password from the Kubernetes secret
POSTGRES_PASSWORD=$(kubectl get secret --namespace postgres postgres15-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode)
echo "Retrieved PostgreSQL password: $POSTGRES_PASSWORD" | tee -a $OUTPUT_FILE
# Create Bitbucket user role
echo "Creating Bitbucket user role..." | tee -a $OUTPUT_FILE
kubectl exec -i postgres15-postgresql-0 --namespace postgres -- /opt/bitnami/postgresql/bin/psql -U postgres -c "\
CREATE ROLE bitbucketuser WITH LOGIN PASSWORD 'jellyfish' VALID UNTIL 'infinity';" | tee -a $OUTPUT_FILE
# Create Bitbucket database
echo "Creating Bitbucket database..." | tee -a $OUTPUT_FILE
kubectl exec -i postgres15-postgresql-0 --namespace postgres -- /opt/bitnami/postgresql/bin/psql -U postgres -c "\
CREATE DATABASE bitbucket WITH ENCODING='UTF8' OWNER=bitbucketuser CONNECTION LIMIT=-1;" | tee -a $OUTPUT_FILE
# Install NFS package
echo "Installing NFS package..." | tee -a $OUTPUT_FILE
sudo apt install -y nfs-kernel-server | tee -a $OUTPUT_FILE
# Create namespace for NFS
echo "Creating namespace for NFS..." | tee -a $OUTPUT_FILE
kubectl create namespace nfs | tee -a $OUTPUT_FILE
# Clone the sample NFS
# server helm chart
echo "Cloning NFS server helm chart..." | tee -a $OUTPUT_FILE
git clone https://github.com/atlassian/data-center-helm-charts.git | tee -a $OUTPUT_FILE
# Deploy NFS server
echo "Deploying NFS server..." | tee -a $OUTPUT_FILE
helm install nfs-server data-center-helm-charts/docs/docs/examples/storage/nfs/nfs-server-example --namespace nfs | tee -a $OUTPUT_FILE
# Final message
echo "Deployment complete. Details have been saved to $OUTPUT_FILE." | tee -a $OUTPUT_FILE
