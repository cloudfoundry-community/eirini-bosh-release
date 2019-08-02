The integration tests in this directory verify the functionality and code of the BOSH components of Eirini BOSH release (e.g., bosh job template scripts).

To run these integration tests, a certain amount of setup is required.

## Prerequisite CLIs
* [bosh](https://bosh.io/docs/cli-v2-install)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl)
* [ginkgo](https://onsi.github.io/ginkgo/)

## Pre-test environment setup
1. You'll need a BOSH environment and a Kubernetes cluster
1. Create and upload the Eirini BOSH release to your BOSH environment (e.g., `bosh create-release --force && bosh upload-release`)
1. Make sure your bosh environment variables (e.g., `BOSH_ENVIRONMENT`) are configured to point to the test environment you want to use.
1. Set up a kube config file pointing to the cluster you want to use for testing. Export the KUBECONFIG env var to point to this file (e.g., `export KUBECONFIG=~/.kube/config`)

## Run the tests
From `test` directory, run:

`ginkgo -p --slowSpecThreshold=400`
