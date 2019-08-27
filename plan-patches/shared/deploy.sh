#!/usr/bin/env bash

set -euxo pipefail

if [ "$#" -ne 2 ]; then
  set +x
  echo "Expected usage: ${0} /path/to/cf-deployment /path/to/eirini-bosh-release"
  exit 1
fi

CF_DEPLOYMENT_PATH="$(realpath -e ${1})"
EIRINI_BOSH_RELEASE_PATH="$(realpath -e ${2})"

bosh upload-release https://bosh.io/d/github.com/cloudfoundry-community/eirini-bosh-release
# pin to version 2.28.0 of bits-service until we've added support for auth with bits-service registry
bosh upload-release https://bosh.io/d/github.com/cloudfoundry-incubator/bits-service-release?v=2.28.0

bosh -d cf deploy "${CF_DEPLOYMENT_PATH}/cf-deployment.yml" --no-redact \
  -o "${CF_DEPLOYMENT_PATH}/operations/use-compiled-releases.yml" \
  -o "${CF_DEPLOYMENT_PATH}/operations/bits-service/use-bits-service.yml" \
  -o "${EIRINI_BOSH_RELEASE_PATH}/operations/add-eirini.yml" \
  -o "${EIRINI_BOSH_RELEASE_PATH}/operations/hardcode-doppler-ip.yml" \
  -o "${CF_DEPLOYMENT_PATH}/operations/scale-to-one-az.yml" \
  -v system_domain="$(bbl outputs | bosh int - --path=/system_domain)"
