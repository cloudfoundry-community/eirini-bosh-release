#!/bin/sh

export BBL_STATE_DIRECTORY="$BBL_STATE_DIR"
"${BBL_STATE_DIR}/create-director.sh"

bosh_director_name="$(bbl outputs | bosh int - --path=/director_name)"
k8s_host_url="$(bbl outputs | bosh int - --path=/k8s_host_url)"
k8s_service_username="$(bbl outputs | bosh int - --path=/k8s_service_username)"
k8s_service_token="$(bbl outputs | bosh int - --path=/k8s_service_account_data/token)"
k8s_ca="$(bbl outputs | bosh int - --path=/k8s_ca)"

eval "$(bbl print-env -s ${BBL_STATE_DIR})"
credhub set --name=/${bosh_director_name}/cf/k8s_host_url --value="${k8s_host_url}" -t value
credhub set --name=/${bosh_director_name}/cf/k8s_service_username --value="${k8s_service_username}" -t value
credhub set --name=/${bosh_director_name}/cf/k8s_service_token --value="${k8s_service_token}" -t value
credhub set --name=/${bosh_director_name}/cf/k8s_node_ca --value="${k8s_ca}" -t value
