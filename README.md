# eirini-bosh-release

This is a BOSH release for [eirini](https://code.cloudfoundry.org/eirini).

## Deploying CF+Eirini with BOSH

1. Ensure you have the following utilities:
  - `jq`
  - `bosh`
  - `credhub`
  - `kubectl`
1. Create a k8s cluster and add it as the current context to your kubectl config.
1. Ensure that the BOSH & CredHub CLI connection environment variables are properly set.
1. Run `scripts/pre-deploy-configure-k8s.sh`
1. Create and upload the following BOSH releases:
    - [`bits-service-release`](https://github.com/cloudfoundry-incubator/bits-service-release)
        - At least git tag > `2.26.0-dev.8`
    - This BOSH release
1. Deploy `cf-deployment` with the following ops files (in this order):
    - `<CF_DEPLOYMENT>/operations/bits-service/use-bits-service.yml`
    - `eirini-bosh-release/operations/add-eirini.yml`
1. Run `scripts/post-deploy-configure-k8s.sh <LB_CA_CERT_VALUE> <SYSTEM_DOMAIN>`
    - The value of `LB_CA_CERT_VALUE` must be the CA of the cert of whatever in your deployment is terminating TLS (usually either an IaaS load balancer or the gorouter itself)

## Contributing

1. Fork this project into your GitHub organisation or username
1. Make sure you are up-to-date with the upstream master and then create your feature branch (`git checkout -b amazing-new-feature`)
1. Add and commit the changes (`git commit -am 'Add some amazing new feature'`)
1. Push to the branch (`git push origin amazing-new-feature`)
1. Create a PR against this repository
