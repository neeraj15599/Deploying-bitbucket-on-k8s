#!/bin/bash

# Function to uninstall Helm releases
uninstall_helm_release() {
  local release_name=$1
  local namespace=$2

  echo "Uninstalling Helm release: $release_name in namespace: $namespace"
  helm uninstall $release_name --namespace $namespace
}

# Function to delete namespaces
delete_namespace() {
  local namespace=$1

  echo "Deleting namespace: $namespace"
  kubectl delete namespace $namespace
}

# Uninstall all Helm releases
uninstall_helm_release bitbucket bitbucket
uninstall_helm_release nfs-server nfs
uninstall_helm_release postgres15 postgres
uninstall_helm_release hostpath-provisioner kube-system

# Delete namespaces
delete_namespace bitbucket
delete_namespace nfs
delete_namespace postgres

# Remove cloned repository and configuration files
echo "Removing cloned repository and configuration files"
rm -rf data-center-helm-charts
rm -f values.yaml

# Verify deletion
echo "Verifying that all resources are deleted..."
kubectl get all --all-namespaces
kubectl get pvc --all-namespaces
echo "Cleanup complete."