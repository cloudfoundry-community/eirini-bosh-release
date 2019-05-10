#!/usr/bin/env bash

set -ueo pipefile

k8s_service_account=opi-service-account

echo "Creating service account '$k8s_service_account'..."
kubectl apply -f <(kubectl create serviceaccount $k8s_service_account -o yaml --save-config --dry-run)

echo "Creating cluster-admin role binding for the service account..."
kubectl apply -f <(kubectl create clusterrolebinding opi-cluster-admin --clusterrole=custer-admin --serviceaccount="default:$k8s_service_account" -o yaml --save-config --dry-run)

echo "Retrieving the service account's token secret..."
service_account_token_secret="$(kubectl get serviceaccount ${k8s_service_account} -o jsonpath='{.secrets[0].name}')"
k8s_service_token="$(kubectl get secret ${service_account_token_secret} -o jsonpath='{.data.token}' | base64 -D)"

echo "Extracting CA and server address from current kubectl context..."
k8s_node_ca="$(bosh int <(kubectl config view --raw --minify) --path=/clusters/0/cluster/certificate-authority-data | base64 -D)"
k8s_host_url="$(bosh int <(kubectl config view --raw --minify) --path=/clusters/0/cluster/server)"

echo "Retrieving the currently targeted BOSH environment's name..."
bosh_env_name="$(bosh env --json | jq .Tables[0].Rows[0].name -r)"

echo "Creating credhub entries with k8s cluster info..."
credhub set --name=/$bosh_env_name/cf/k8s_host_url --value="${k8s_host_url}" -t value
credhub set --name=/$bosh_env_name/cf/k8s_service_username --value="${k8s_service_account}" -t value
credhub set --name=/$bosh_env_name/cf/k8s_service_token --value="${k8s_service_token}" -t value
credhub set --name=/$bosh_env_name/cf/k8s_node_ca --value="${k8s_node_ca}" -t value

echo
echo "Done"
