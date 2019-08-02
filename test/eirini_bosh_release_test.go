package bosh_release_tests_test

import (
	"fmt"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	. "github.com/onsi/gomega/gbytes"
	. "github.com/onsi/gomega/gexec"
)

var _ = Describe("EiriniBoshRelease", func() {
	When("Eirini has been BOSH-deployed successfully", func() {
		var (
			deploymentName                    string
			boshDeployOpsFiles                []string
			kubeServiceAccountRoleBindingName string
			kubeNamespace                     string
		)

		BeforeEach(func() {
			boshDeployOpsFiles = []string{}
		})

		JustBeforeEach(func() {
			deploymentName = fmt.Sprintf("eirini-%d-%d", time.Now().Unix(), GinkgoParallelNode())
			kubeNamespace = createTestKubeNamespace()
			var kubeServiceAccountName, kubeServiceAccountToken string
			kubeServiceAccountName, kubeServiceAccountToken, kubeServiceAccountRoleBindingName = createTestServiceAccountAndRoleBinding(kubeNamespace)
			boshDeploy(deploymentName, kubeNamespace, kubeServiceAccountName, kubeServiceAccountToken, boshDeployOpsFiles...)
		})

		AfterEach(func() {
			cancelAllBoshTasks(deploymentName)
			boshDeleteDeployment(deploymentName)
			deleteTestKubeNamespace(kubeNamespace)
			deleteClusterRoleBinding(kubeServiceAccountRoleBindingName)
		})

		Context("and I run the configure-eirini-bosh errand", func() {
			var session *Session

			JustBeforeEach(func() {
				session = boshRunErrand(deploymentName, "configure-eirini-bosh")
			})

			When("configured to reference an image that does not exist", func() {
				BeforeEach(func() {
					boshDeployOpsFiles = []string{"operations/invalid-image-reference-for-errand.yml"}
				})

				It("exits with an error and displays a failure message", func() {
					Eventually(session, 20*time.Minute).Should(Say("timed out"))
					Eventually(session).Should(Exit(1))
				})
			})

			When("configured with an invalid service account", func() {
				BeforeEach(func() {
					boshDeployOpsFiles = []string{"operations/invalid-service-account-for-errand.yml"}
				})

				It("error out with a meaningful message", func() {
					Eventually(session, 20*time.Minute).Should(Say("Unauthorized"))
					Eventually(session).Should(Exit(1))
				})
			})

			When("configured correctly", func() {
				It("succeeds", func() {
					Eventually(session, 20*time.Minute).Should(Exit(0))
				})

				Context("and the errand has been running longer than a configurable timeout", func() {
					BeforeEach(func() {
						boshDeployOpsFiles = []string{"operations/short-timeout-for-errand.yml"}
					})

					It("the errand should error", func() {
						Eventually(session, 20*time.Minute).Should(Say("timed out"))
						Eventually(session).Should(Exit(1))
					})
				})
			})
		})
	})
})
