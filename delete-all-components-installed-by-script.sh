#!/bin/bash
# Function to delete Helm releases
delete_helm_release() {
    local release_name="$1"
    local namespace="$2"
    echo "Deleting Helm release $release_name in namespace $namespace..."
    helm uninstall "$release_name" --namespace "$namespace"
}
# Delete PostgreSQL Helm release
delete_helm_release "postgres15" "bitbucket"
# Delete NFS server Helm release
delete_helm_release "nfs-server" "bitbucket"
# Delete hostpath-provisioner Helm release
delete_helm_release "hostpath-provisioner" "kube-system"
# Delete Kubernetes namespace
echo "Deleting namespace bitbucket..."
kubectl delete namespace bitbucket
# Delete NFS package (if applicable)
echo "Removing NFS package..."
sudo apt remove -y nfs-kernel-server
# Remove cloned NFS server helm chart directory
if [ -d "data-center-helm-charts" ]; then
    echo "Removing cloned data-center-helm-charts directory..."
    rm -rf data-center-helm-charts
fi
# Final message
echo "All components have been deleted."