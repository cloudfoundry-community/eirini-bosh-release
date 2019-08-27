#!/usr/bin/env bash

set -euxo pipefail

if [ "$#" -ne 1 ]; then
  set +x
  echo "Expected usage: ${0} /path/to/cf-deployment"
  exit 1
fi

CF_DEPLOYMENT_PATH="$(realpath -e ${1})"
STEMCELL_VERSION=$(bosh int --path /stemcells/0/version ${CF_DEPLOYMENT_PATH}/cf-deployment.yml)
bosh upload-stemcell "https://s3.amazonaws.com/bosh-gce-light-stemcells/$STEMCELL_VERSION/light-bosh-stemcell-$STEMCELL_VERSION-google-kvm-ubuntu-xenial-go_agent.tgz"
