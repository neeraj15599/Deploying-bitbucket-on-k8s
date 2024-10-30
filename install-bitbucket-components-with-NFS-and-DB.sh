#!/bin/bash
# Define the output file
OUTPUT_FILE="deployment_details.txt"
# Delete deployment_details.txt if it exists
if [ -f "$OUTPUT_FILE" ]; then
    echo "Deleting existing $OUTPUT_FILE..."
    rm "$OUTPUT_FILE"
fi
# Add helm repositories
echo "Adding helm repositories..."
helm repo add rimusz https://charts.rimusz.net
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add atlassian-data-center https://atlassian.github.io/data-center-helm-charts
# Update helm repositories
echo "Updating helm repositories..."
helm repo update
# Install hostpath-provisioner
echo "Installing hostpath-provisioner..."
helm install hostpath-provisioner --namespace kube-system rimusz/hostpath-provisioner
# Create namespace for PostgreSQL
echo "Creating namespace for bitbucket..."
kubectl create namespace bitbucket
# Install PostgreSQL 15
echo "Installing PostgreSQL 15..."
helm install postgres15 bitnami/postgresql \
  --set image.tag=15 \
  --set global.postgresql.auth.postgresPassword=postgres \
  --namespace bitbucket
# Wait for the PostgreSQL pod to be ready
echo "Waiting for PostgreSQL pod to be ready..."
kubectl wait --namespace bitbucket --for=condition=ready pod -l app.kubernetes.io/name=postgresql --timeout=300s
# Get the PostgreSQL pod IP and save it to the output file
POSTGRES_IP=$(kubectl get pod -n bitbucket -l app.kubernetes.io/name=postgresql -o jsonpath="{.items[0].status.podIP}")
echo "PostgreSQL IP: $POSTGRES_IP"
echo "# postgres ip=$POSTGRES_IP" >> $OUTPUT_FILE
# Database details to be appended to the output file
DATABASE_NAME="bitbucket"
echo "Appending database details to $OUTPUT_FILE..."
cat <<EOF >> $OUTPUT_FILE
database:
  url: jdbc:postgresql://$POSTGRES_IP:5432/$DATABASE_NAME # Update this
  driver: org.postgresql.Driver # Update this
  credentials:
    secretName: bitbucket-database #Update this
EOF
# Retrieve the PostgreSQL password from the Kubernetes secret
POSTGRES_PASSWORD=$(kubectl get secret --namespace bitbucket postgres15-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode)
echo "Retrieved PostgreSQL password: $POSTGRES_PASSWORD"
# Create Bitbucket user role
echo "Creating Bitbucket user role..."
kubectl exec -i postgres15-postgresql-0 --namespace bitbucket -- /opt/bitnami/postgresql/bin/psql -U postgres -c "\
CREATE ROLE bitbucketuser WITH LOGIN PASSWORD 'jellyfish' VALID UNTIL 'infinity';"
# Create Bitbucket database
echo "Creating Bitbucket database..."
kubectl exec -i postgres15-postgresql-0 --namespace bitbucket -- /opt/bitnami/postgresql/bin/psql -U postgres -c "\
CREATE DATABASE bitbucket WITH ENCODING='UTF8' OWNER=bitbucketuser CONNECTION LIMIT=-1;"
# Install NFS package
echo "Installing NFS package..."
sudo apt install -y nfs-kernel-server
# Clone the sample NFS server helm chart
echo "Cloning NFS server helm chart..."
git clone https://github.com/atlassian/data-center-helm-charts.git
# Deploy NFS server
echo "Deploying NFS server..."
helm install nfs-server data-center-helm-charts/docs/docs/examples/storage/nfs/nfs-server-example --namespace bitbucket
# Wait for the NFS pod to be ready
echo "Waiting for NFS pod to be ready..."
kubectl wait --namespace bitbucket --for=condition=ready pod -l app.kubernetes.io/name=nfs-server-example --timeout=600s
# Retrieve the NFS IP
NFS_IP=$(kubectl get pod -n bitbucket -l app.kubernetes.io/name=nfs-server-example -o jsonpath='{.items[0].status.podIP}')
# Verify the NFS IP was retrieved and append NFS details to the output file
if [ -z "$NFS_IP" ]; then
  echo "Error: NFS pod IP could not be retrieved. Please check the pod status."
else
  echo "Appending NFS and volume details to $OUTPUT_FILE..."
  cat <<EOF >> $OUTPUT_FILE
volumes:
  localHome:
    persistentVolumeClaim:
      create: true # Set this to true
      storageClassName: hostpath # Update this
      resources:
        requests:
          storage: 1Gi
    customVolume: {}
    mountPath: "/var/atlassian/application-data/bitbucket"
  sharedHome:
    persistentVolume:
      create: true
      nfs:
        server: "$NFS_IP" # Update this with the NFS IP
        path: "/srv/nfs" # Update this to /srv/nfs
      mountOptions: []
    persistentVolumeClaim:
      create: true
      storageClassName: ""
      volumeName:
      accessMode: ReadWriteMany
      resources:
        requests:
          storage: 1Gi
EOF
fi
# Final message
echo "Deployment complete. Details have been saved to $OUTPUT_FILE."
