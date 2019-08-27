# eirini-bosh-release

This is a BOSH release for [eirini](https://code.cloudfoundry.org/eirini).

## Deploying CF+Eirini with BOSH
1. Ensure you have the following utilities:
  - [`bosh`](https://bosh.io/docs/cli-v2-install/)
  - [`bosh-bootloader`](https://github.com/cloudfoundry/bosh-bootloader#prerequisites)
  - [`credhub`](https://github.com/cloudfoundry-incubator/credhub-cli#installing-the-cli)
1. Clone relevant repos to deploy CF.
    ```
    git clone https://github.com/cloudfoundry/cf-deployment.git
    /path/to/cf-deployment
    git clone https://github.com/cloudfoundry-community/eirini-bosh-release.git
    /path/to/eirini-bosh-release
    ```
1. Create a GCP service account for use by BBL (BOSH Bootloader): [Getting
   Started: GCP # Create a Service
   Account](https://github.com/cloudfoundry/bosh-bootloader/blob/master/docs/getting-started-gcp.md#create-a-service-account)

1. Generate a certificate for use by CF load balancers. See [Deploying CF#step-1-get-you-some-load-balancers](https://github.com/cloudfoundry/cf-deployment/blob/master/texts/deployment-guide.md#step-1-get-you-some-load-balancers) for help.
1. Create and bootstrap the directory to store your BBL (BOSH Bootloader) state:
    ```
    mkdir -p ~/path/to/envs/new_environment
    cd ~/path/to/envs/new_environment

    # export BBL_ENV_NAME=new_environment
    # export BBL_IAAS=gcp
    # export BBL_GCP_REGION=us-west1
    # export BBL_GCP_SERVICE_ACCOUNT_KEY=/path/to/key.json

    bbl plan --lb-type cf --lb-domain system.tld --lb-cert /path/to/cert --lb-key /path/to/key
    ```

1. Apply the relevant plan patches to the BBL state dir.
    ```
    cp -R ~/path/to/eirini-bosh-release/plan-patches/shared/. ~/path/to/envs/new_environment
    cp -R ~/path/to/eirini-bosh-release/plan-patches/gcp/. ~/path/to/envs/new_environment
    ```
1. Deploy the infrastructure with BBL.
    ```
    bbl up
    ```
1. Upload stemcell to BOSH director
    ```
    eval "$(bbl print-env)"
    ./upload-stemcell.sh /path/to/cf-deployment
    ```
1. Deploy CF
    ```
    eval "$(bbl print-env)"
    ./deploy.sh /path/to/cf-deployment /path/to/eirini-bosh-release
    ```
1. Create a new DNS record by following the instructions [Step 2: Update your DNS records to point to your load balancer
](https://github.com/cloudfoundry/cf-deployment/blob/master/texts/deployment-guide.md#step-2-update-your-dns-records-to-point-to-your-load-balancer).

1. Run the post-deploy errand:
    ```
    bosh -d cf run-errand configure-eirini-bosh
    ```

## Contributing

1. Fork this project into your GitHub organisation or username
1. Make sure you are up-to-date with the upstream master and then create your feature branch (`git checkout -b amazing-new-feature`)
1. Add and commit the changes (`git commit -am 'Add some amazing new feature'`)
1. Push to the branch (`git push origin amazing-new-feature`)
1. Create a PR against this repository
