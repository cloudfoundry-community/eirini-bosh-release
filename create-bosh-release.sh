#!/usr/bin/env bash

set -euo pipefail

if [ $# -gt 0 ]; then
  if [ "$1" = "-h" ] || [ "$1" = "--help" ] ; then
    echo "Usage: $0 [optional-args...]"
    echo
    echo "Any optional args will be passed directly on to the 'bosh create-release' command."
    echo "e.g., '$0 --force' will run 'bosh create-release --force'"
    echo
    echo "This script exists as a temporary way to create development BOSH releases while"
    echo "we address the issue of managing Go dependencies outside of pre-packaging scripts."
    echo "Use this script if 'bosh create release' fails on your development environment."
    echo "Caveat: this script won't work if the eirini-bosh-release is a git submodule."
    exit 1
  fi
fi


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

set -x

docker run --mount type=bind,source=$DIR,target=/bosh-release relintdockerhubpushbot/cf-deployment-concourse-tasks /bin/bash -c "cd bosh-release && bosh create-release $@"
